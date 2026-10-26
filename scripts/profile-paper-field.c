/* Profile the Adê 0.4.5 paper-field kernels.
   gcc -O3 -std=c11 -o /tmp/profile-paper-field scripts/profile-paper-field.c -lm
   Mirrors SceneInk and PaperSurfaceReflection: Bayer grain, crest geometry,
   and the four full-window blurs. Not part of the app. */
#define _POSIX_C_SOURCE 200809L
#define _GNU_SOURCE
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const int kBayer8[] = {
  0, 48, 12, 60, 3, 51, 15, 63,
  32, 16, 44, 28, 35, 19, 47, 31,
  8, 56, 4, 52, 11, 59, 7, 55,
  40, 24, 36, 20, 43, 27, 39, 23,
  2, 50, 14, 62, 1, 49, 13, 61,
  34, 18, 46, 30, 33, 17, 45, 29,
  10, 58, 6, 54, 9, 57, 5, 53,
  42, 26, 38, 22, 41, 25, 37, 21
};
static const int kBayer4[] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

typedef struct { float x, y, w, h; } Rect;

static int scene_grain(double width, double height, double time, int calm, Rect *rects, int cap) {
  double phase = time * 2.0 * M_PI;
  double energy = calm ? 0.75 : 1.0;
  double spacing = fmax(4.0, sqrt(width * height / 42000.0));
  int cols = (int)(width / spacing);
  int rows = (int)(height / spacing);
  double drift = 0.09 * sin(phase / 10.0);
  int count = 0;
  for (int column = 0; column <= cols; column++) {
    double x = ((double)column + 0.5) * spacing;
    double u = (x / width + 0.08) / 1.16;
    double swell = 0.065 * sin(u * M_PI * 2.0 - phase / 12.0)
      + 0.035 * sin(u * M_PI * 3.0 + phase / 20.0);
    double crest = 0.62 + energy * (swell + drift);
    int first = (int)((crest - 0.18) * height / spacing) - 1;
    if (first < 0) first = 0;
    for (int row = first; row <= rows; row++) {
      double y = ((double)row + 0.5) * spacing;
      double depth = y / height - crest;
      double rise = depth + 0.18;
      if (rise < 0) rise = 0;
      rise /= 0.46;
      if (rise > 1) rise = 1;
      double density = rise * rise * (3.0 - 2.0 * rise) * 0.82 * energy;
      int idx = ((row & 7) * 8) + (column & 7);
      double threshold = ((double)kBayer8[idx] + 0.5) / 64.0;
      double coverage = (density - threshold) * 7.0 + 0.5;
      if (coverage < 0) coverage = 0;
      if (coverage > 1) coverage = 1;
      coverage *= fmin(1.0, density * 12.0);
      if (coverage <= 0.005) continue;
      double side = spacing * 0.56 * sqrt(coverage);
      if (count < cap) {
        rects[count].x = (float)(x - side / 2);
        rects[count].y = (float)(y - side / 2);
        rects[count].w = (float)side;
        rects[count].h = (float)side;
      }
      count++;
    }
  }
  return count;
}

static int accent_grain(double width, double height, double time, int night, Rect *rects, int cap) {
  (void)night;
  double phase = time * 2.0 * M_PI / 12.0;
  double spacing = fmax(2.5, sqrt(width * height / 5000.0));
  int cols = (int)(width / spacing);
  int rows = (int)(height / spacing);
  int count = 0;
  for (int column = 0; column <= cols; column++) {
    double x = ((double)column + 0.5) * spacing;
    double wave = 0.5 + 0.28 * sin(x / width * M_PI * 2.0 - phase);
    for (int row = 0; row <= rows; row++) {
      double y = ((double)row + 0.5) * spacing;
      double density = wave + 0.22 * (y / height - 0.5);
      if (density < 0.05) density = 0.05;
      if (density > 0.9) density = 0.9;
      int idx = ((row & 3) * 4) + (column & 3);
      double threshold = ((double)kBayer4[idx] + 0.5) / 16.0;
      double coverage = (density - threshold) * 5.0 + 0.5;
      if (coverage < 0) coverage = 0;
      if (coverage > 1) coverage = 1;
      if (coverage <= 0.005) continue;
      double side = spacing * 0.58 * sqrt(coverage);
      if (count < cap) {
        rects[count].x = (float)(x - side / 2);
        rects[count].y = (float)(y - side / 2);
        rects[count].w = (float)side;
        rects[count].h = (float)side;
      }
      count++;
    }
  }
  return count;
}

/* Prefix-sum box blur, 3 passes ≈ a wide Gaussian. One channel. */
static void box_blur(float *src, float *tmp, int w, int h, int radius) {
  if (radius < 1) radius = 1;
  int span = radius * 2 + 1;
  for (int y = 0; y < h; y++) {
    float *row = src + (size_t)y * w;
    float *out = tmp + (size_t)y * w;
    float acc = 0;
    for (int i = 0; i < span && i < w; i++) acc += row[i];
    for (int x = 0; x < w; x++) {
      out[x] = acc / (float)span;
      int add = x + radius + 1;
      int sub = x - radius;
      if (add < w) acc += row[add];
      else acc += row[w - 1];
      if (sub >= 0) acc -= row[sub];
      else acc -= row[0];
    }
  }
  for (int x = 0; x < w; x++) {
    float acc = 0;
    for (int i = 0; i < span && i < h; i++) acc += tmp[(size_t)i * w + x];
    for (int y = 0; y < h; y++) {
      src[(size_t)y * w + x] = acc / (float)span;
      int add = y + radius + 1;
      int sub = y - radius;
      if (add < h) acc += tmp[(size_t)add * w + x];
      else acc += tmp[(size_t)(h - 1) * w + x];
      if (sub >= 0) acc -= tmp[(size_t)sub * w + x];
      else acc -= tmp[x];
    }
  }
}

static void gaussianish(float *buf, float *tmp, int w, int h, int radius) {
  int r = radius / 3;
  if (r < 1) r = 1;
  box_blur(buf, tmp, w, h, r);
  box_blur(buf, tmp, w, h, r);
  box_blur(buf, tmp, w, h, r);
}

static void stamp(uint8_t *alpha, int w, int h, const Rect *rects, int count, double scale) {
  memset(alpha, 0, (size_t)w * h);
  for (int i = 0; i < count; i++) {
    double x0 = rects[i].x * scale;
    double y0 = rects[i].y * scale;
    double x1 = (rects[i].x + rects[i].w) * scale;
    double y1 = (rects[i].y + rects[i].h) * scale;
    int ix0 = (int)floor(x0);
    int iy0 = (int)floor(y0);
    int ix1 = (int)ceil(x1);
    int iy1 = (int)ceil(y1);
    if (ix0 < 0) ix0 = 0;
    if (iy0 < 0) iy0 = 0;
    if (ix1 > w) ix1 = w;
    if (iy1 > h) iy1 = h;
    for (int y = iy0; y < iy1; y++) {
      double cy0 = y < y0 ? 0 : (y + 1 > y1 ? y1 - y : 1);
      if (y < y0) cy0 = y0 - y > 1 ? 0 : 1 - (y0 - y);
      double coverY = 1.0;
      if (y < y0) coverY = 0;
      else if (y + 1 > y1) coverY = y1 - y;
      if (coverY < 0) coverY = 0;
      if (coverY > 1) coverY = 1;
      (void)cy0;
      uint8_t *row = alpha + (size_t)y * w;
      for (int x = ix0; x < ix1; x++) {
        double coverX = 1.0;
        if (x < x0) coverX = 0;
        else if (x + 1 > x1) coverX = x1 - x;
        if (coverX < 0) coverX = 0;
        if (coverX > 1) coverX = 1;
        int v = (int)(coverX * coverY * 255.0 + 0.5);
        if (v > row[x]) row[x] = (uint8_t)v;
      }
    }
  }
}

static void write_ppm(const char *path, const uint8_t *alpha, int w, int h) {
  FILE *f = fopen(path, "wb");
  if (!f) return;
  fprintf(f, "P5\n%d %d\n255\n", w, h);
  fwrite(alpha, 1, (size_t)w * h, f);
  fclose(f);
}

/* Low-res crest field. Two filled crests + two soft bands, then one blur. */
static void raster_waves(float *buf, int w, int h, double time, int calm) {
  memset(buf, 0, sizeof(float) * (size_t)w * h);
  double phase = time * 2.0 * M_PI;
  double energy = calm ? 0.75 : 1.0;
  for (int current = 0; current < 2; current++) {
    double offset = current * M_PI;
    double drift = 0.09 * sin(phase / 10.0 + offset);
    for (int x = 0; x < w; x++) {
      double u = ((double)x / (w - 1)) * 1.16 - 0.08;
      double swell = 0.065 * sin(u * M_PI * 2.0 - phase / 12.0 + offset)
        + 0.035 * sin(u * M_PI * 3.0 + phase / 20.0 + offset);
      double crest = 0.62 + current * 0.20 + energy * (swell + drift);
      int y0 = (int)((crest - 0.02) * (h - 1));
      if (y0 < 0) y0 = 0;
      if (y0 > h) y0 = h;
      float fill = current == 0 ? 0.55f : 0.40f;
      for (int y = y0; y < h; y++) buf[(size_t)y * w + x] += fill;
      int band = (int)(0.10 * h);
      int yb0 = (int)(crest * (h - 1)) - band / 2;
      for (int y = yb0; y < yb0 + band; y++) {
        if (y < 0 || y >= h) continue;
        buf[(size_t)y * w + x] += 0.85f;
      }
    }
  }
}

int main(void) {
  const double times[] = {0.0, 3.7, 12.0, 40.0};
  const struct { const char *name; double w, h; int calm; } scenes[] = {
    {"workspace 1280x720", 1244, 684, 0},
    {"macbook 1512x982", 1476, 946, 0},
    {"external 1920x1080", 1884, 1044, 0},
  };
  Rect *rects = calloc(400000, sizeof(Rect));
  printf("=== baseline grain (SceneInk formula) ===\n");
  for (int s = 0; s < 3; s++) {
    int peak = 0;
    double t0 = now_ms();
    int nrun = 30;
    for (int i = 0; i < nrun; i++) {
      int n = scene_grain(scenes[s].w, scenes[s].h, times[i % 4], scenes[s].calm, rects, 400000);
      if (n > peak) peak = n;
    }
    double ms = (now_ms() - t0) / nrun;
    double spacing = fmax(4.0, sqrt(scenes[s].w * scenes[s].h / 42000.0));
    printf("%-22s spacing %.2f  rects %6d  emit %6.2f ms\n", scenes[s].name, spacing, peak, ms);
  }

  printf("\n=== baseline accent dither ===\n");
  const struct { const char *name; double w, h; } accents[] = {
    {"nav tab", 170, 30},
    {"primary button", 148, 36},
    {"attendance %", 240, 168},
  };
  for (int s = 0; s < 3; s++) {
    int peak = 0;
    double t0 = now_ms();
    int nrun = 60;
    for (int i = 0; i < nrun; i++) {
      int n = accent_grain(accents[s].w, accents[s].h, times[i % 4], 0, rects, 400000);
      if (n > peak) peak = n;
    }
    double ms = (now_ms() - t0) / nrun;
    printf("%-22s rects %6d  emit %6.3f ms\n", accents[s].name, peak, ms);
  }

  /* Representative workspace frame at retina 2x. */
  const double W = 1244, H = 684;
  int n = scene_grain(W, H, 3.7, 0, rects, 400000);
  printf("\n=== one events-screen frame, %d background rects ===\n", n);
  int scales[] = {1, 2};
  for (int si = 0; si < 2; si++) {
    int scale = scales[si];
    int w = (int)(W * scale);
    int h = (int)(H * scale);
    uint8_t *alpha = malloc((size_t)w * h);
    double t0 = now_ms();
    int nrun = scale == 1 ? 8 : 4;
    for (int i = 0; i < nrun; i++) stamp(alpha, w, h, rects, n, scale);
    double stamp_ms = (now_ms() - t0) / nrun;

    int radius = (int)(fmin(54.0, fmax(24.0, H * 0.055)) * scale);
    float *buf = malloc(sizeof(float) * (size_t)w * h);
    float *tmp = malloc(sizeof(float) * (size_t)w * h);
    for (int i = 0; i < w * h; i++) buf[i] = (i % 17) * 0.01f;
    t0 = now_ms();
    int bruns = 2;
    for (int i = 0; i < bruns; i++) gaussianish(buf, tmp, w, h, radius);
    double blur_ms = (now_ms() - t0) / bruns;
    printf("scale %dx  backing %dx%d  grain-stamp %6.2f ms  one blur r=%d %6.2f ms  four blurs %6.2f ms\n",
           scale, w, h, stamp_ms, radius, blur_ms, blur_ms * 4);
    if (scale == 1) write_ppm("/tmp/ade-profile/grain-baseline.pgm", alpha, w, h);
    free(alpha); free(buf); free(tmp);
  }

  /* Optimized waves: long side ~240, one blur. */
  printf("\n=== optimized wave field ===\n");
  for (int longside = 160; longside <= 480; longside += 160) {
    double aspect = W / H;
    int bw = longside;
    int bh = (int)(longside / aspect);
    float *buf = calloc((size_t)bw * bh, sizeof(float));
    float *tmp = calloc((size_t)bw * bh, sizeof(float));
    uint8_t *img = malloc((size_t)bw * bh);
    double t0 = now_ms();
    int nrun = 40;
    int radius = (int)(fmin(54.0, fmax(24.0, H * 0.055)) * ((double)bh / H));
    if (radius < 2) radius = 2;
    for (int i = 0; i < nrun; i++) {
      raster_waves(buf, bw, bh, 3.7 + i * 0.01, 0);
      gaussianish(buf, tmp, bw, bh, radius);
    }
    double ms = (now_ms() - t0) / nrun;
    float peak = 0;
    for (int i = 0; i < bw * bh; i++) {
      if (buf[i] > peak) peak = buf[i];
      int v = (int)(fminf(buf[i], 2.5f) / 2.5f * 255);
      img[i] = (uint8_t)v;
    }
    printf("wave %4dx%-4d blur r=%2d  %6.3f ms  peak %.2f\n", bw, bh, radius, ms, peak);
    if (longside == 320) write_ppm("/tmp/ade-profile/waves-optimized.pgm", img, bw, bh);
    free(buf); free(tmp); free(img);
  }

  /* Optimized accent stamp */
  printf("\n=== optimized accent stamp ===\n");
  for (int s = 0; s < 3; s++) {
    int an = accent_grain(accents[s].w, accents[s].h, 3.7, 0, rects, 400000);
    int scale = 2;
    int w = (int)(accents[s].w * scale);
    int h = (int)(accents[s].h * scale);
    uint8_t *alpha = malloc((size_t)w * h);
    double t0 = now_ms();
    int nrun = 80;
    for (int i = 0; i < nrun; i++) stamp(alpha, w, h, rects, an, scale);
    printf("%-22s rects %5d  stamp@2x %6.3f ms\n", accents[s].name, an, (now_ms() - t0) / nrun);
    free(alpha);
  }

  /* Steady-state events screen: what 0.4.5 schedules every frame. */
  int bg = scene_grain(W, H, 3.7, 0, rects, 400000);
  int nav = accent_grain(170, 30, 3.7, 0, rects, 400000);
  int button = accent_grain(148, 36, 3.7, 0, rects, 400000);
  int sidebar_grads = 2, crumb_grads = 2, rail_absent = 0;
  printf("\n=== 30 fps budget, events list, 1244x684 pt ===\n");
  printf("TimelineViews: background, sidebar glass, breadcrumb glass, selected tab, primary button = 5\n");
  printf("Canvas rects/frame: background %d + tab %d + button %d = %d\n", bg, nav, button, bg + nav + button);
  printf("SwiftUI blur layers/frame: 4 full-window (2 crest fills + 2 crest strokes)\n");
  printf("Live materials over the animating field: sidebar + breadcrumb (ultraThinMaterial)\n");
  printf("Glass gradient canvases (no dither): %d\n", sidebar_grads + crumb_grads + rail_absent);
  (void)rail_absent;
  free(rects);
  return 0;
}
