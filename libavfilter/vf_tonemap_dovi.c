/*
 * Copyright (c) 2024 Gnattu OC
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/**
 * @file
 * dovi reshaping and tone mapping
 */

#include <float.h>
#include <stdio.h>
#include <string.h>

#include "libavutil/csp.h"
#include "libavutil/imgutils.h"
#include "libavutil/internal.h"
#include "libavutil/intreadwrite.h"
#include "libavutil/opt.h"
#include "libavutil/pixdesc.h"
#include "libavutil/float_dsp.h"
#include "libavutil/avassert.h"

#include "avfilter.h"
#include "colorspace.h"
#include "formats.h"
#include "internal.h"
#include "video.h"

typedef struct DoviTonemapContext {
    const AVClass *class;

    double param;
    double peak;
    enum AVChromaLocation chroma_loc;

    float *lin_lut;
    float *inverse_lut;
    float* rgb_matrix;
    float* yuv_matrix;
    float* ycc2rgb_offset;
    float* lms2rgb_matrix;
    float* rgb2rgb_matrix;
    struct DoviMetadata *dovi;
} DoviTonemapContext;

typedef struct ThreadData {
    AVFrame *in, *out;
    const AVPixFmtDescriptor *desc;
    double peak;
} ThreadData;

static const double dovi_lms2rgb_matrix[3][3] =
    {
        { 3.06441879, -2.16597676,  0.10155818},
        {-0.65612108,  1.78554118, -0.12943749},
        { 0.01736321, -0.04725154,  1.03004253},
    };

static void apply_matrix(const float matrix[3][3], const float input[3], float output[3])
{
    output[0] = matrix[0][0] * input[0] + matrix[0][1] * input[1] + matrix[0][2] * input[2];
    output[1] = matrix[1][0] * input[0] + matrix[1][1] * input[1] + matrix[1][2] * input[2];
    output[2] = matrix[2][0] * input[0] + matrix[2][1] * input[1] + matrix[2][2] * input[2];
}

#define LUT_SIZE (1 << 10)
#define LUT_TRC (LUT_SIZE - 1)
static int compute_trc_luts(AVFilterContext *avctx)
{
    DoviTonemapContext *ctx = avctx->priv;
    int i;

    if (!ctx->lin_lut && !(ctx->lin_lut = av_calloc(LUT_SIZE, sizeof(float))))
        return AVERROR(ENOMEM);
    for (i = 0; i < LUT_SIZE; i++) {
        float x = (float)i / (LUT_SIZE - 1);
        ctx->lin_lut[i] = eotf_st2084(x, REFERENCE_WHITE);
    }
    if (!ctx->inverse_lut && !(ctx->inverse_lut = av_calloc(LUT_SIZE, sizeof(float))))
        return AVERROR(ENOMEM);
    for (i = 0; i < LUT_SIZE; i++) {
        float x = (float)i / (LUT_SIZE - 1);
        ctx->inverse_lut[i] = inverse_eotf_st2084(x, REFERENCE_WHITE);
    }

    return 0;
}

inline static void mix(float* dest, const float* x, const float* y, float a, int len)
{
    int i;
    for (i = 0; i < len; i++) {
        dest[i] = (y[i]-x[i]) * a + x[i];
    }
}

inline static float dot(const float* x, const float* y, int len)
{
    int i;
    float result = 0;
    for (i = 0; i < len; i++) {
        result += x[i] * y[i];
    }
    return result;
}

inline static float le10bitToFloat(uint16_t x) {
    return (float)(x)/1024.0f;
}

inline static uint16_t floatTo10bitLE(float x) {
    return (uint16_t)(x * 1024);
}

#define CLAMP(a, b, c) (FFMIN(FFMAX((a), (b)), (c)))
inline static float linearize(float x, float* lin_lut)
{
    return lin_lut[CLAMP((int)(x * LUT_TRC), 0, LUT_TRC)];
}

inline static float delinearize(float x, float* inverse_lut)
{
    return inverse_lut[CLAMP((int)(x * LUT_TRC), 0, LUT_TRC)];
}

inline static float reinhard(float s, float param, float peak) {
    return s / (s + param) * (peak + param) / peak;
}

static av_cold void uninit(AVFilterContext *ctx)
{
    DoviTonemapContext *s = ctx->priv;
}

static av_cold int init(AVFilterContext *ctx)
{
    DoviTonemapContext *s = ctx->priv;

    if (!isnan(s->param))
        s->param = (1.0f - s->param) / s->param;

    if (isnan(s->param))
        s->param = 1.0f;
    compute_trc_luts(ctx);

    return 0;
}

inline static float lrgb2y(float r, float g, float b, const float* matrix, float* inverse_lut)
{
    float y = (delinearize(r, inverse_lut)*matrix[0])
        + (delinearize(g, inverse_lut)*matrix[1])
        + (delinearize(b, inverse_lut)*matrix[2]);
    y = (219.0f * y + 16.0f) / 255.0f;
    return y;
}

inline static void lrgb2uv(float* dest, float r, float g, float b, const float* matrix, float* inverse_lut)
{
    float u = (delinearize(r, inverse_lut)*matrix[3]) + (delinearize(g, inverse_lut)*matrix[4]) + (delinearize(b, inverse_lut)*matrix[5]);
    float v = (delinearize(r, inverse_lut)*matrix[6]) + (delinearize(g, inverse_lut)*matrix[7]) + (delinearize(b, inverse_lut)*matrix[8]);
    u = (224.0f * u + 128.0f) / 255.0f;
    v = (224.0f * v + 128.0f) / 255.0f;
    dest[1] = u;
    dest[2] = v;
}

inline static void rgb2lrgb(float* dest, float r, float g, float b, const float* rgb2rgb, float *lin_lut)
{
    float lr = linearize(r, lin_lut);
    float lg = linearize(g, lin_lut);
    float lb = linearize(b, lin_lut);
    dest[0] = (rgb2rgb[0] * lr) + (rgb2rgb[1] * lg) + (rgb2rgb[2] * lb);
    dest[1] = (rgb2rgb[3] * lr) + (rgb2rgb[4] * lg) + (rgb2rgb[5] * lb);
    dest[2] = (rgb2rgb[6] * lr) + (rgb2rgb[7] * lg) + (rgb2rgb[8] * lb);
}

inline static void ycc2rgb(float* dest, float y, float cb, float cr, const double nonlinear[3][3], const float* ycc2rgb_offset)
{
    float offset1 = ycc2rgb_offset[0] * (float)nonlinear[0][0] + ycc2rgb_offset[1] * (float)nonlinear[0][1] + ycc2rgb_offset[2] * (float)nonlinear[0][2];
    float offset2 = ycc2rgb_offset[0] * (float)nonlinear[1][0] + ycc2rgb_offset[1] * (float)nonlinear[1][1] + ycc2rgb_offset[2] * (float)nonlinear[1][2];
    float offset3 = ycc2rgb_offset[0] * (float)nonlinear[2][0] + ycc2rgb_offset[1] * (float)nonlinear[2][1] + ycc2rgb_offset[2] * (float)nonlinear[2][2];

    dest[0] = (y * (float)nonlinear[0][0] + cb * (float)nonlinear[0][1] + cr * (float)nonlinear[0][2]) - offset1;
    dest[1] = (y * (float)nonlinear[1][0] + cb * (float)nonlinear[1][1] + cr * (float)nonlinear[1][2]) - offset2;
    dest[2] = (y * (float)nonlinear[2][0] + cb * (float)nonlinear[2][1] + cr * (float)nonlinear[2][2]) - offset3;
}

// This implementation does not do the costly linearization and de-linearization for performance reasons
// The output color accuracy will be affected due to this
inline static void lms2rgb(float* dest, float l, float m, float s, const double linear[3][3])
{
    double lms2rgb_matrix[3][3];
    ff_matrix_mul_3x3(lms2rgb_matrix, dovi_lms2rgb_matrix, linear);
    dest[0] = l * (float)lms2rgb_matrix[0][0] + m * (float)lms2rgb_matrix[0][1] + s * (float)lms2rgb_matrix[0][2];
    dest[1] = l * (float)lms2rgb_matrix[1][0] + m * (float)lms2rgb_matrix[1][1] + s * (float)lms2rgb_matrix[1][2];
    dest[2] = l * (float)lms2rgb_matrix[2][0] + m * (float)lms2rgb_matrix[2][1] + s * (float)lms2rgb_matrix[2][2];
}

inline static float reshape_poly(float s, float* coeffs) {
    return (coeffs[2] * s + coeffs[1]) * s + coeffs[0];
}

static float reshape_mmr(const float* sig, const float* coeffs, const struct ReshapeData *comp, int pivot_index) {
    int min_order = 3, max_order = 1;
    int order = (int)coeffs[3];
    float s = coeffs[0];
    float sigX[7] = {sig[0], sig[1], sig[2],
                     sig[0] * sig[1], sig[0] * sig[2], sig[1] * sig[2], sig[0] * sig[1] * sig[2]};
    min_order = FFMIN(min_order, comp->mmr_order[pivot_index]);
    max_order = FFMAX(max_order, comp->mmr_order[pivot_index]);

    s += dot(comp->mmr_coeffs[pivot_index][0], sigX, 7);

    if (max_order >= 2 && (min_order >= 2 || order >= 2)) {
        float sigX2[7] = {sig[0] * sig[0], sig[1] * sig[1], sig[2] * sig[2],
                          sigX[0] * sigX[0], sigX[1] * sigX[1], sigX[2] * sigX[2], sigX[3] * sigX[3]};
        s += dot(comp->mmr_coeffs[pivot_index][1], sigX2, 7);

        if (max_order == 3 && (min_order == 3 || order >= 3)) {
            float sigX3[7] = {sig[0] * sig[0] * sig[0], sig[1] * sig[1] * sig[1], sig[2] * sig[2] * sig[2],
                              sigX2[0] * sigX[0], sigX2[1] * sigX[1], sigX2[2] * sigX[2], sigX2[3] * sigX[3]};
            s += dot(comp->mmr_coeffs[pivot_index][2], sigX3, 7);
        }
    }

    return s;
}

static void reshape_dovi_yuv(float* dest, float* src, DoviTonemapContext *ctx)
{
    int i, k;
    float s;
    float coeffs[4] = {0, 0, 0, 0};

    float sig_arr[3] = {CLAMP(src[0], 0.0f, 1.0f), CLAMP(src[1], 0.0f, 1.0f), CLAMP(src[2], 0.0f, 1.0f)};
    for (i = 0; i < 3; i++) {
        const struct ReshapeData *comp = &ctx->dovi->comp[i];
        s = sig_arr[i];
        if (comp->num_pivots >= 9 && s >= comp->pivots[7]) {
            switch (comp->method[7]) {
                case 0: // polynomial
                    coeffs[3] = 0.0f; // order=0 signals polynomial
                    for (k = 0; k < 3; k++)
                        coeffs[k] = comp->poly_coeffs[7][k];
                    s = reshape_poly(s, coeffs);
                    break;
                case 1:
                    coeffs[0] = comp->mmr_constant[7];
                    coeffs[1] = (float)(2 * i);
                    coeffs[3] = (float)comp->mmr_order[7];
                    s = reshape_mmr(sig_arr, coeffs, comp, 7);
                    break;
            }
        } else if (comp->num_pivots >= 8 && s >= comp->pivots[6]) {
            switch (comp->method[6]) {
                case 0: // polynomial
                    coeffs[3] = 0.0f; // order=0 signals polynomial
                    for (k = 0; k < 3; k++)
                        coeffs[k] = comp->poly_coeffs[6][k];
                    s = reshape_poly(s, coeffs);
                    break;
                case 1:
                    coeffs[0] = comp->mmr_constant[6];
                    coeffs[1] = (float)(2 * i);
                    coeffs[3] = (float)comp->mmr_order[6];
                    s = reshape_mmr(sig_arr, coeffs, comp, 6);
                    break;
            }
        } else if (comp->num_pivots >= 7 && s >= comp->pivots[5]) {
            switch (comp->method[5]) {
                case 0: // polynomial
                    coeffs[3] = 0.0f; // order=0 signals polynomial
                    for (k = 0; k < 3; k++)
                        coeffs[k] = comp->poly_coeffs[5][k];
                    s = reshape_poly(s, coeffs);
                    break;
                case 1:
                    coeffs[0] = comp->mmr_constant[5];
                    coeffs[1] = (float)(2 * i);
                    coeffs[3] = (float)comp->mmr_order[5];
                    s = reshape_mmr(sig_arr, coeffs, comp, 5);
                    break;
            }
        } else if (comp->num_pivots >= 6 && s >= comp->pivots[4]) {
            switch (comp->method[4]) {
                case 0: // polynomial
                    coeffs[3] = 0.0f; // order=0 signals polynomial
                    for (k = 0; k < 3; k++)
                        coeffs[k] = comp->poly_coeffs[4][k];
                    s = reshape_poly(s, coeffs);
                    break;
                case 1:
                    coeffs[0] = comp->mmr_constant[4];
                    coeffs[1] = (float)(2 * i);
                    coeffs[3] = (float)comp->mmr_order[4];
                    s = reshape_mmr(sig_arr, coeffs, comp, 4);
                    break;
            }
        } else if (comp->num_pivots >= 5 && s >= comp->pivots[3]) {
            switch (comp->method[3]) {
                case 0: // polynomial
                    coeffs[3] = 0.0f; // order=0 signals polynomial
                    for (k = 0; k < 3; k++)
                        coeffs[k] = comp->poly_coeffs[3][k];
                    s = reshape_poly(s, coeffs);
                    break;
                case 1:
                    coeffs[0] = comp->mmr_constant[3];
                    coeffs[1] = (float)(2 * i);
                    coeffs[3] = (float)comp->mmr_order[3];
                    s = reshape_mmr(sig_arr, coeffs, comp, 3);
                    break;
            }
        } else if (comp->num_pivots >= 4 && s >= comp->pivots[2]) {
            switch (comp->method[2]) {
                case 0: // polynomial
                    coeffs[3] = 0.0f; // order=0 signals polynomial
                    for (k = 0; k < 3; k++)
                        coeffs[k] = comp->poly_coeffs[2][k];
                    s = reshape_poly(s, coeffs);
                    break;
                case 1:
                    coeffs[0] = comp->mmr_constant[2];
                    coeffs[1] = (float)(2 * i);
                    coeffs[3] = (float)comp->mmr_order[2];
                    s = reshape_mmr(sig_arr, coeffs, comp, 2);
                    break;
            }
        } else if (comp->num_pivots >= 3 && s >= comp->pivots[1]) {
            switch (comp->method[1]) {
                case 0: // polynomial
                    coeffs[3] = 0.0f; // order=0 signals polynomial
                    for (k = 0; k < 3; k++)
                        coeffs[k] = comp->poly_coeffs[1][k];
                    s = reshape_poly(s, coeffs);
                    break;
                case 1:
                    coeffs[0] = comp->mmr_constant[1];
                    coeffs[1] = (float)(2 * i);
                    coeffs[3] = (float)comp->mmr_order[1];
                    s = reshape_mmr(sig_arr, coeffs, comp, 1);
                    break;
            }
        } else {
            switch (comp->method[0]) {
                case 0: // polynomial
                    coeffs[3] = 0.0f; // order=0 signals polynomial
                    for (k = 0; k < 3; k++)
                        coeffs[k] = comp->poly_coeffs[0][k];
                    s = reshape_poly(s, coeffs);
                    break;
                case 1:
                    coeffs[0] = comp->mmr_constant[0];
                    coeffs[1] = (float)(2 * i);
                    coeffs[3] = (float)comp->mmr_order[0];
                    s = reshape_mmr(sig_arr, coeffs, comp, 0);
                    break;
            }
        }
        sig_arr[i] = CLAMP(s, comp->pivots[0], comp->pivots[comp->num_pivots-1]);
    }
    *dest = *sig_arr;
}

static void tonemap(DoviTonemapContext *s, AVFrame *out, const AVFrame *in,
                    const AVPixFmtDescriptor *desc, int x, int y)
{
    int i = 0;
    // Load Data
    int map[3] = { desc->comp[0].plane, desc->comp[1].plane, desc->comp[2].plane };
    const uint16_t *y1_in, *y2_in, *y3_in, *y4_in, *cb_in, *cr_in;
    uint16_t *y1_out, *y2_out, *y3_out, *y4_out, *cb_out, *cr_out;
    float y1, y2, y3, y4, cb, cr;
    float yuv1[3], yuv2[3], yuv3[3], yuv4[3], chroma_sample[3];
    float c1[3], c2[3], c3[3], c4[3];
    float r4[4], g4[4], b4[4];
    float sig[4], sig_o[4];

    y1_in = (const uint16_t*)(in->data[map[0]] + 2*x * desc->comp[map[0]].step + 2*y * in->linesize[map[0]]);
    y2_in = (const uint16_t*)(in->data[map[0]] + 2*(x+1) * desc->comp[map[0]].step + 2*y * in->linesize[map[0]]);
    y3_in = (const uint16_t*)(in->data[map[0]] + 2*x * desc->comp[map[0]].step + 2*(y+1) * in->linesize[map[0]]);
    y4_in = (const uint16_t*)(in->data[map[0]] + 2*(x+1) * desc->comp[map[0]].step + 2*(y+1) * in->linesize[map[0]]);
    cb_in = (const uint16_t*)(in->data[map[1]] + x * desc->comp[map[1]].step + y * in->linesize[map[1]]);
    cr_in = (const uint16_t*)(in->data[map[2]] + x * desc->comp[map[2]].step + y * in->linesize[map[2]]);

    y1_out = (uint16_t*)(out->data[map[0]] + 2*x * desc->comp[map[0]].step + 2*y * out->linesize[map[0]]);
    y2_out = (uint16_t*)(out->data[map[0]] + 2*(x+1) * desc->comp[map[0]].step + 2*y * out->linesize[map[0]]);
    y3_out = (uint16_t*)(out->data[map[0]] + 2*x * desc->comp[map[0]].step + 2*(y+1) * out->linesize[map[0]]);
    y4_out = (uint16_t*)(out->data[map[0]] + 2*(x+1) * desc->comp[map[0]].step + 2*(y+1) * out->linesize[map[0]]);
    cb_out = (uint16_t*)(out->data[map[1]] + x * desc->comp[map[1]].step + y * out->linesize[map[1]]);
    cr_out = (uint16_t*)(out->data[map[2]] + x * desc->comp[map[2]].step + y * out->linesize[map[2]]);

    y1 = le10bitToFloat(*y1_in);
    y2 = le10bitToFloat(*y2_in);
    y3 = le10bitToFloat(*y3_in);
    y4 = le10bitToFloat(*y4_in);
    cb = le10bitToFloat(*cb_in);
    cr = le10bitToFloat(*cr_in);
    yuv1[0] = y1;
    yuv2[0] = y2;
    yuv3[0] = y3;
    yuv4[0] = y4;
    yuv1[1] = yuv2[1] = yuv3[1] = yuv4[1] = cb;
    yuv1[2] = yuv2[2] = yuv3[2] = yuv4[2] = cr;

    // Convert DOVI ICT to RGB
    reshape_dovi_yuv(yuv1, yuv1, s);
    reshape_dovi_yuv(yuv2, yuv2, s);
    reshape_dovi_yuv(yuv3, yuv3, s);
    reshape_dovi_yuv(yuv4, yuv4, s);
    ycc2rgb(c1, yuv1[0], yuv1[1], yuv1[2], s->dovi->nonlinear, s->dovi->nonlinear_offset);
    ycc2rgb(c2, yuv2[0], yuv2[1], yuv2[2], s->dovi->nonlinear, s->dovi->nonlinear_offset);
    ycc2rgb(c3, yuv3[0], yuv3[1], yuv3[2], s->dovi->nonlinear, s->dovi->nonlinear_offset);
    ycc2rgb(c4, yuv4[0], yuv4[1], yuv4[2], s->dovi->nonlinear, s->dovi->nonlinear_offset);
    lms2rgb(c1, c1[0], c1[1], c1[2], s->dovi->linear);
    lms2rgb(c2, c2[0], c2[1], c2[2], s->dovi->linear);
    lms2rgb(c3, c3[0], c3[1], c3[2], s->dovi->linear);
    lms2rgb(c4, c4[0], c4[1], c4[2], s->dovi->linear);
    rgb2lrgb(c1, c1[0], c1[1], c1[2], s->rgb2rgb_matrix, s->lin_lut);
    rgb2lrgb(c2, c2[0], c2[1], c2[2], s->rgb2rgb_matrix, s->lin_lut);
    rgb2lrgb(c3, c3[0], c3[1], c3[2], s->rgb2rgb_matrix, s->lin_lut);
    rgb2lrgb(c4, c4[0], c4[1], c4[2], s->rgb2rgb_matrix, s->lin_lut);

    // Hardcoded MAX Tone Mapping
    r4[0] = c1[0];
    r4[1] = c2[0];
    r4[2] = c3[0];
    r4[3] = c4[0];

    g4[0] = c1[1];
    g4[1] = c2[1];
    g4[2] = c3[1];
    g4[3] = c4[1];

    b4[0] = c1[2];
    b4[1] = c2[2];
    b4[2] = c3[2];
    b4[3] = c4[2];

    sig[0] = FFMAX(FFMAX3(r4[0], g4[0], b4[0]), FLOAT_EPS);
    sig[1] = FFMAX(FFMAX3(r4[1], g4[1], b4[1]), FLOAT_EPS);
    sig[2] = FFMAX(FFMAX3(r4[2], g4[2], b4[2]), FLOAT_EPS);
    sig[3] = FFMAX(FFMAX3(r4[3], g4[3], b4[3]), FLOAT_EPS);
    *sig_o = *sig;
    sig[0] = FFMIN(reinhard(sig[0], (float)s->param, (float)s->peak), 1.0f);
    sig[1] = FFMIN(reinhard(sig[1], (float)s->param, (float)s->peak), 1.0f);
    sig[2] = FFMIN(reinhard(sig[2], (float)s->param, (float)s->peak), 1.0f);
    sig[3] = FFMIN(reinhard(sig[3], (float)s->param, (float)s->peak), 1.0f);

    c1[0] = c1[0] * sig[0] / sig_o[0];
    c1[1] = c1[1] * sig[0] / sig_o[0];
    c1[2] = c1[2] * sig[0] / sig_o[0];

    c2[0] = c2[0] * sig[1] / sig_o[1];
    c2[1] = c2[1] * sig[1] / sig_o[1];
    c2[2] = c2[2] * sig[1] / sig_o[1];

    c3[0] = c3[0] * sig[2] / sig_o[2];
    c3[1] = c3[1] * sig[2] / sig_o[2];
    c3[2] = c3[2] * sig[2] / sig_o[2];

    c4[0] = c4[0] * sig[3] / sig_o[3];
    c4[1] = c4[1] * sig[3] / sig_o[3];
    c4[2] = c4[2] * sig[3] / sig_o[3];

    // Convert back to YUV and write output
    *y1_out = floatTo10bitLE(lrgb2y(c1[0], c1[1], c1[2], s->yuv_matrix, s->inverse_lut));
    *y2_out = floatTo10bitLE(lrgb2y(c2[0], c2[1], c2[2], s->yuv_matrix, s->inverse_lut));
    *y3_out = floatTo10bitLE(lrgb2y(c3[0], c3[1], c3[2], s->yuv_matrix, s->inverse_lut));
    *y4_out = floatTo10bitLE(lrgb2y(c4[0], c4[1], c4[2], s->yuv_matrix, s->inverse_lut));

    switch (s->chroma_loc) {
        case AVCHROMA_LOC_LEFT:
            for (i = 0; i < 3; i++) {
                chroma_sample[i] = (c1[i] + c3[i]) * 0.5f;
            }
            break;
        case AVCHROMA_LOC_TOPLEFT:
            *chroma_sample = *c1;
            break;
        case AVCHROMA_LOC_TOP:
            for (i = 0; i < 3; i++) {
                chroma_sample[i] = (c1[i] + c2[i]) * 0.5f;
            }
            break;
        case AVCHROMA_LOC_BOTTOMLEFT:
            *chroma_sample = *c3;
            break;
        case AVCHROMA_LOC_BOTTOM:
            for (i = 0; i < 3; i++) {
                chroma_sample[i] = (c3[i] + c4[i]) * 0.5f;
            }
            break;
        default:
            for (i = 0; i < 3; i++) {
                chroma_sample[i] = (c1[i] + c2[i] + c3[i] + c4[i]) * 0.25f;
            }
            break;
    }

    // lrgb2uv(chroma_sample, chroma_sample[0], chroma_sample[1], chroma_sample[2], s->yuv_matrix, s->inverse_lut);
//    *cb_out = floatTo10bitLE(chroma_sample[1]);
//    *cr_out = floatTo10bitLE(chroma_sample[2]);
    *cb_out = 0;
    *cr_out = 0;
}

static int tonemap_slice(AVFilterContext *ctx, void *arg, int jobnr, int nb_jobs)
{
    DoviTonemapContext *s = ctx->priv;
    ThreadData *td = arg;
    AVFrame *in = td->in;
    AVFrame *out = td->out;
    const AVPixFmtDescriptor *desc = td->desc;
    const int slice_start = (in->height / 2 * jobnr) / nb_jobs;
    const int slice_end = (in->height / 2 * (jobnr+1)) / nb_jobs;

    for (int y = slice_start; y < slice_end; y++)
        for (int x = 0; x < out->width / 2; x++)
            tonemap(s, out, in, desc, x, y);

    return 0;
}

static int filter_frame(AVFilterLink *link, AVFrame *in)
{
    AVFilterContext *ctx = link->dst;
    DoviTonemapContext *s = ctx->priv;
    AVFilterLink *outlink = ctx->outputs[0];
    ThreadData td;
    AVFrame *out;
    AVFrameSideData *dovi_sd = av_frame_get_side_data(in, AV_FRAME_DATA_DOVI_METADATA);
    const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(link->format);
    const AVPixFmtDescriptor *odesc = av_pix_fmt_desc_get(outlink->format);
    const AVColorPrimariesDesc *in_primaries = av_csp_primaries_desc_from_id(AVCOL_PRI_BT2020);
    const AVColorPrimariesDesc *out_primaries = av_csp_primaries_desc_from_id(AVCOL_PRI_BT709);
    const AVLumaCoefficients *luma_dst;
    int ret, x, y;
    double rgb2xyz[3][3], xyz2rgb[3][3], rgb2rgb[3][3], rgb2yuv[3][3];

    if (!desc || !odesc) {
        av_frame_free(&in);
        return AVERROR_BUG;
    }

    out = ff_get_video_buffer(outlink, outlink->w, outlink->h);
    if (!out) {
        av_frame_free(&in);
        return AVERROR(ENOMEM);
    }

    ret = av_frame_copy_props(out, in);
    if (ret < 0) {
        av_frame_free(&in);
        av_frame_free(&out);
        return ret;
    }

    if (dovi_sd) {
        const AVDOVIMetadata *metadata = (AVDOVIMetadata *) dovi_sd->data;
        const AVDOVIRpuDataHeader *rpu = av_dovi_get_header(metadata);
        // only map dovi rpus that don't require an EL
        if (rpu->disable_residual_flag) {
            struct DoviMetadata *dovi = av_malloc(sizeof(*dovi));
            s->dovi = dovi;
            if (!s->dovi)
                goto fail;

            ff_map_dovi_metadata(s->dovi, metadata);
//            ctx->trc_in = AVCOL_TRC_SMPTE2084;
//            ctx->colorspace_in = AVCOL_SPC_UNSPECIFIED;
//            ctx->primaries_in = AVCOL_PRI_BT2020;
        }
    } else {
        // no dovi side data, just return the frame as-is removing all hdr metadata
        *out->data = *in->data;
        av_frame_free(&in);

        av_frame_remove_side_data(out, AV_FRAME_DATA_MASTERING_DISPLAY_METADATA);
        av_frame_remove_side_data(out, AV_FRAME_DATA_CONTENT_LIGHT_LEVEL);
        av_frame_remove_side_data(out, AV_FRAME_DATA_DOVI_RPU_BUFFER);
        av_frame_remove_side_data(out, AV_FRAME_DATA_DOVI_METADATA);

        return ff_filter_frame(outlink, out);
    }

    //TODO: init dovi matrices

    if (!s->rgb2rgb_matrix) { // rgb2rgb matrix
        int i = 0, j = 0, p = 0;
        ff_fill_rgb2xyz_table(&out_primaries->prim, &out_primaries->wp, rgb2xyz);
        ff_matrix_invert_3x3(rgb2xyz, xyz2rgb);
        ff_fill_rgb2xyz_table(&in_primaries->prim, &in_primaries->wp, rgb2xyz);
        ff_matrix_mul_3x3(rgb2rgb, rgb2xyz, xyz2rgb);
        s->rgb2rgb_matrix = av_calloc(3 * 3, sizeof(float));
        for (i = 0; i < 3; i++) {
            for (j = 0; j < 3; j++) {
                s->rgb2rgb_matrix[p] = (float)rgb2rgb[i][j];
                p++;
            }
        }
    }

    if (!s->yuv_matrix) {// yuv matrix
        int i = 0, j = 0, p = 0;
        out->color_primaries = AVCOL_PRI_BT709;
        out->colorspace = AVCOL_SPC_BT709;
        luma_dst = av_csp_luma_coeffs_from_avcsp(out->colorspace);
        if (!luma_dst) {
            av_log(s, AV_LOG_ERROR, "Unsupported output colorspace %d (%s)\n",
                   out->colorspace, av_color_space_name(out->colorspace));
            goto fail;
        }
        ff_fill_rgb2yuv_table(luma_dst, rgb2yuv);
        s->yuv_matrix = av_calloc(3 * 3, sizeof(float));
        for (i = 0; i < 3; i++) {
            for (j = 0; j < 3; j++) {
                s->yuv_matrix[p] = (float)rgb2yuv[i][j];
                p++;
            }
        }
    }

    if (!s->peak) {
        const AVDOVIMetadata *metadata = (AVDOVIMetadata *) dovi_sd->data;
        s->peak = ff_determine_dovi_signal_peak(metadata);
        av_log(s, AV_LOG_DEBUG, "Computed signal peak: %f\n", s->peak);
    }
    s->peak = 100.0f;

    td.out = out;
    td.in = in;
    td.desc = desc;
    ff_filter_execute(ctx, tonemap_slice, &td, NULL,
                      FFMIN(in->height / 2, ff_filter_get_nb_threads(ctx)));

    av_frame_free(&in);

    av_frame_remove_side_data(out, AV_FRAME_DATA_MASTERING_DISPLAY_METADATA);
    av_frame_remove_side_data(out, AV_FRAME_DATA_CONTENT_LIGHT_LEVEL);
    av_frame_remove_side_data(out, AV_FRAME_DATA_DOVI_RPU_BUFFER);
    av_frame_remove_side_data(out, AV_FRAME_DATA_DOVI_METADATA);

    return ff_filter_frame(outlink, out);

    fail:
    if (s->dovi)
        av_freep(&s->dovi);
    av_frame_free(&in);
    av_frame_free(&out);
    return AVERROR_BUG;
}

#define OFFSET(x) offsetof(DoviTonemapContext, x)
#define FLAGS (AV_OPT_FLAG_VIDEO_PARAM | AV_OPT_FLAG_FILTERING_PARAM)
static const AVOption tonemap_dovi_options[] = {
    { NULL }
};

AVFILTER_DEFINE_CLASS(tonemap_dovi);

static const AVFilterPad tonemap_dovi_inputs[] = {
    {
        .name         = "default",
        .type         = AVMEDIA_TYPE_VIDEO,
        .filter_frame = filter_frame,
    },
};

static const AVFilterPad tonemap_dovi_outputs[] = {
    {
        .name         = "default",
        .type         = AVMEDIA_TYPE_VIDEO,
    },
};

const AVFilter ff_vf_tonemap_dovi = {
    .name            = "tonemap_dovi",
    .description     = NULL_IF_CONFIG_SMALL("Conversion from dolby vision dynamic range to SDR."),
    .init            = init,
    .uninit          = uninit,
    .priv_size       = sizeof(DoviTonemapContext),
    .priv_class      = &tonemap_dovi_class,
    FILTER_INPUTS(tonemap_dovi_inputs),
    FILTER_OUTPUTS(tonemap_dovi_outputs),
    FILTER_PIXFMTS(AV_PIX_FMT_YUV420P10LE),
    .flags           = AVFILTER_FLAG_SLICE_THREADS,
};