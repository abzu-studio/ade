#include "PaperFieldKernels.h"

#include <math.h>
#include <string.h>

static const int kBayer8[64] = {
  0, 48, 12, 60, 3, 51, 15, 63, 32, 16, 44, 28, 35, 19, 47, 31, 8, 56, 4, 52, 11, 59, 7, 55, 40, 24,
  36, 20, 43, 27, 39, 23, 2, 50, 14, 62, 1, 49, 13, 61, 34, 18, 46, 30, 33, 17, 45, 29, 10, 58, 6,
  54, 9, 57, 5, 53, 42, 26, 38, 22, 41, 25, 37, 21,
};

static const int kBayer4[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};

/* Edge pixels use a shorter window, matching the previous prefix-sum blur. */
static void blur_horizontal(const uint8_t *src, uint8_t *dst, int w, int h, int radius) {
  for (int y = 0; y < h; y++) {
    const uint8_t *row = src + (size_t)y * (size_t)w * 4;
    uint8_t *out = dst + (size_t)y * (size_t)w * 4;
    int sum0 = 0, sum1 = 0, sum2 = 0, sum3 = 0;
    int lead = 0;
    int trail = 0;
    for (int x = 0; x < w; x++) {
      int add = x + radius;
      if (add >= w) add = w - 1;
      while (lead <= add) {
        const uint8_t *p = row + lead * 4;
        sum0 += p[0];
        sum1 += p[1];
        sum2 += p[2];
        sum3 += p[3];
        lead++;
      }
      int drop = x - radius;
      while (trail < drop) {
        const uint8_t *p = row + trail * 4;
        sum0 -= p[0];
        sum1 -= p[1];
        sum2 -= p[2];
        sum3 -= p[3];
        trail++;
      }
      int count = lead - trail;
      uint8_t *o = out + x * 4;
      o[0] = (uint8_t)(sum0 / count);
      o[1] = (uint8_t)(sum1 / count);
      o[2] = (uint8_t)(sum2 / count);
      o[3] = (uint8_t)(sum3 / count);
    }
  }
}

static void blur_vertical(const uint8_t *src, uint8_t *dst, int w, int h, int radius) {
  for (int x = 0; x < w; x++) {
    int sum0 = 0, sum1 = 0, sum2 = 0, sum3 = 0;
    int lead = 0;
    int trail = 0;
    for (int y = 0; y < h; y++) {
      int add = y + radius;
      if (add >= h) add = h - 1;
      while (lead <= add) {
        const uint8_t *p = src + ((size_t)lead * (size_t)w + (size_t)x) * 4;
        sum0 += p[0];
        sum1 += p[1];
        sum2 += p[2];
        sum3 += p[3];
        lead++;
      }
      int drop = y - radius;
      while (trail < drop) {
        const uint8_t *p = src + ((size_t)trail * (size_t)w + (size_t)x) * 4;
        sum0 -= p[0];
        sum1 -= p[1];
        sum2 -= p[2];
        sum3 -= p[3];
        trail++;
      }
      int count = lead - trail;
      uint8_t *o = dst + ((size_t)y * (size_t)w + (size_t)x) * 4;
      o[0] = (uint8_t)(sum0 / count);
      o[1] = (uint8_t)(sum1 / count);
      o[2] = (uint8_t)(sum2 / count);
      o[3] = (uint8_t)(sum3 / count);
    }
  }
}

void ade_box_blur_rgba(uint8_t *pixels, uint8_t *tmp, int w, int h, int radius) {
  if (!pixels || !tmp || w < 1 || h < 1) return;
  int pass = radius / 3;
  if (pass < 1) pass = 1;
  for (int i = 0; i < 3; i++) {
    blur_horizontal(pixels, tmp, w, h, pass);
    blur_vertical(tmp, pixels, w, h, pass);
  }
}

static int clamp_byte(int value) {
  if (value < 0) return 0;
  if (value > 255) return 255;
  return value;
}

static void stamp(
  uint8_t *pixels, int w, int h, double cx, double cy, double side, int r, int g, int b, int a
) {
  if (side <= 0 || a <= 0) return;
  double half = side * 0.5;
  int x0 = (int)floor(cx - half);
  int y0 = (int)floor(cy - half);
  int x1 = (int)ceil(cx + half);
  int y1 = (int)ceil(cy + half);
  if (x0 < 0) x0 = 0;
  if (y0 < 0) y0 = 0;
  if (x1 > w) x1 = w;
  if (y1 > h) y1 = h;
  int inv = 255 - a;
  for (int y = y0; y < y1; y++) {
    uint8_t *row = pixels + ((size_t)y * (size_t)w) * 4;
    for (int x = x0; x < x1; x++) {
      uint8_t *px = row + x * 4;
      px[0] = (uint8_t)clamp_byte(r + (int)px[0] * inv / 255);
      px[1] = (uint8_t)clamp_byte(g + (int)px[1] * inv / 255);
      px[2] = (uint8_t)clamp_byte(b + (int)px[2] * inv / 255);
      px[3] = (uint8_t)clamp_byte(a + (int)px[3] * inv / 255);
    }
  }
}

void ade_scene_grain(
  uint8_t *pixels, int w, int h, double viewW, double viewH, double time, double energy, double red,
  double green, double blue, int night
) {
  if (!pixels || w < 2 || h < 2 || viewW < 1 || viewH < 1) return;
  memset(pixels, 0, (size_t)w * (size_t)h * 4);
  double phase = time * 6.283185307179586;
  double spacing = sqrt(viewW * viewH / 42000.0);
  if (spacing < 4.0) spacing = 4.0;
  double scaleX = (double)w / viewW;
  double scaleY = (double)h / viewH;
  double alpha = night ? 0.46 : 0.60;
  int a = clamp_byte((int)(alpha * 255.0 + 0.5));
  int cr = clamp_byte((int)(red * alpha * 255.0 + 0.5));
  int cg = clamp_byte((int)(green * alpha * 255.0 + 0.5));
  int cb = clamp_byte((int)(blue * alpha * 255.0 + 0.5));
  int cols = (int)(viewW / spacing);
  int rows = (int)(viewH / spacing);
  double drift = 0.09 * sin(phase / 10.0);
  for (int column = 0; column <= cols; column++) {
    double x = ((double)column + 0.5) * spacing;
    double u = (x / viewW + 0.08) / 1.16;
    double swell =
      0.065 * sin(u * 6.283185307179586 - phase / 12.0) + 0.035 * sin(u * 9.42477796076938 + phase / 20.0);
    double crest = 0.62 + energy * (swell + drift);
    int first = (int)((crest - 0.18) * viewH / spacing) - 1;
    if (first < 0) first = 0;
    for (int row = first; row <= rows; row++) {
      double y = ((double)row + 0.5) * spacing;
      double depth = y / viewH - crest;
      double rise = (depth + 0.18) / 0.46;
      if (rise < 0) rise = 0;
      if (rise > 1) rise = 1;
      double density = rise * rise * (3.0 - 2.0 * rise) * 0.82 * energy;
      double threshold = ((double)kBayer8[(row & 7) * 8 + (column & 7)] + 0.5) / 64.0;
      double coverage = (density - threshold) * 7.0 + 0.5;
      if (coverage < 0) coverage = 0;
      if (coverage > 1) coverage = 1;
      coverage *= density * 12.0 < 1.0 ? density * 12.0 : 1.0;
      if (coverage <= 0.005) continue;
      double side = spacing * 0.56 * sqrt(coverage);
      stamp(pixels, w, h, x * scaleX, y * scaleY, side * scaleX, cr, cg, cb, a);
    }
  }
}

void ade_accent_grain(
  uint8_t *pixels, int w, int h, double viewW, double viewH, double time, int night
) {
  if (!pixels || w < 2 || h < 2 || viewW < 1 || viewH < 1) return;
  memset(pixels, 0, (size_t)w * (size_t)h * 4);
  double phase = time * 6.283185307179586 / 12.0;
  double spacing = sqrt(viewW * viewH / 5000.0);
  if (spacing < 2.5) spacing = 2.5;
  double scaleX = (double)w / viewW;
  double scaleY = (double)h / viewH;
  double alpha = night ? 0.26 : 0.16;
  int channel = night ? 255 : 0;
  int a = clamp_byte((int)(alpha * 255.0 + 0.5));
  int cr = channel ? a : 0;
  int cols = (int)(viewW / spacing);
  int rows = (int)(viewH / spacing);
  for (int column = 0; column <= cols; column++) {
    double x = ((double)column + 0.5) * spacing;
    double wave = 0.5 + 0.28 * sin(x / viewW * 6.283185307179586 - phase);
    for (int row = 0; row <= rows; row++) {
      double y = ((double)row + 0.5) * spacing;
      double density = wave + 0.22 * (y / viewH - 0.5);
      if (density < 0.05) density = 0.05;
      if (density > 0.9) density = 0.9;
      double threshold = ((double)kBayer4[(row & 3) * 4 + (column & 3)] + 0.5) / 16.0;
      double coverage = (density - threshold) * 5.0 + 0.5;
      if (coverage < 0) coverage = 0;
      if (coverage > 1) coverage = 1;
      if (coverage <= 0.005) continue;
      double side = spacing * 0.58 * sqrt(coverage);
      stamp(pixels, w, h, x * scaleX, y * scaleY, side * scaleX, cr, cr, cr, a);
    }
  }
}
