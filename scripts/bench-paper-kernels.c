/* Time the C kernels Adê 0.4.7 draws instead of SwiftUI paths.
   gcc -O3 -std=c11 -o /tmp/bench-paper-kernels scripts/bench-paper-kernels.c \
     macos/Ade/PaperFieldKernels.c -lm
*/
#define _POSIX_C_SOURCE 200809L
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "../macos/Ade/PaperFieldKernels.h"

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static void write_pgm(const char *path, const uint8_t *rgba, int w, int h) {
  FILE *f = fopen(path, "wb");
  if (!f) return;
  fprintf(f, "P5\n%d %d\n255\n", w, h);
  for (int i = 0; i < w * h; i++) fputc(rgba[i * 4 + 3], f);
  fclose(f);
}

static int fit_width(double viewW, double viewH, int cap) {
  double longest = viewW > viewH ? viewW : viewH;
  double fit = longest > cap ? (double)cap / longest : 1.0;
  int w = (int)(viewW * fit + 0.5);
  return w < 2 ? 2 : w;
}

static int fit_height(double viewW, double viewH, int cap) {
  double longest = viewW > viewH ? viewW : viewH;
  double fit = longest > cap ? (double)cap / longest : 1.0;
  int h = (int)(viewH * fit + 0.5);
  return h < 2 ? 2 : h;
}

int main(void) {
  const double viewW = 1244, viewH = 684;
  int caps[] = {420, 960, 1244};
  printf("=== scene grain, events workspace %.0fx%.0f pt ===\n", viewW, viewH);
  for (int i = 0; i < 3; i++) {
    int w = fit_width(viewW, viewH, caps[i]);
    int h = fit_height(viewW, viewH, caps[i]);
    uint8_t *buf = calloc((size_t)w * h * 4, 1);
    double t0 = now_ms();
    int n = 20;
    for (int frame = 0; frame < n; frame++) {
      ade_scene_grain(buf, w, h, viewW, viewH, 3.7 + frame * (1.0 / 30.0), 1.0, 0.45, 0.38, 0.30, 0);
    }
    printf("cap %4d  buffer %4dx%-4d  %6.3f ms\n", caps[i], w, h, (now_ms() - t0) / n);
    if (caps[i] == 960) {
      ade_scene_grain(buf, w, h, viewW, viewH, 0, 1.0, 0.45, 0.38, 0.30, 0);
      write_pgm("/tmp/ade-profile/grain-t0.pgm", buf, w, h);
      uint8_t *later = malloc((size_t)w * h * 4);
      ade_scene_grain(later, w, h, viewW, viewH, 2.0, 1.0, 0.45, 0.38, 0.30, 0);
      write_pgm("/tmp/ade-profile/grain-t2.pgm", later, w, h);
      int changed = 0;
      for (int p = 0; p < w * h; p++) if (buf[p * 4 + 3] != later[p * 4 + 3]) changed++;
      printf("  pixels changed over 2s: %d / %d\n", changed, w * h);
      free(later);
    }
    free(buf);
  }

  printf("\n=== crest blur, long edge 420 ===\n");
  int bw = fit_width(viewW, viewH, 420);
  int bh = fit_height(viewW, viewH, 420);
  uint8_t *pixels = calloc((size_t)bw * bh * 4, 1);
  uint8_t *tmp = calloc((size_t)bw * bh * 4, 1);
  for (int i = 0; i < bw * bh; i++) pixels[i * 4 + 3] = (uint8_t)(i * 17);
  int radius = (int)(fmin(54.0, fmax(24.0, viewH * 0.055)) * ((double)bh / viewH) + 0.5);
  if (radius < 1) radius = 1;
  double t0 = now_ms();
  int n = 40;
  for (int i = 0; i < n; i++) ade_box_blur_rgba(pixels, tmp, bw, bh, radius);
  printf("buffer %dx%d radius %d  one blur %6.3f ms  four blurs %6.3f ms\n", bw, bh, radius,
         (now_ms() - t0) / n, (now_ms() - t0) / n * 4);
  free(pixels);
  free(tmp);

  printf("\n=== accent lattice ===\n");
  const struct { const char *name; double w, h; } accents[] = {
    {"nav tab", 170, 30}, {"primary button", 148, 36}, {"attendance block", 240, 168},
  };
  for (int s = 0; s < 3; s++) {
    int w = (int)(accents[s].w * 2);
    int h = (int)(accents[s].h * 2);
    uint8_t *buf = calloc((size_t)w * h * 4, 1);
    t0 = now_ms();
    n = 60;
    for (int i = 0; i < n; i++) ade_accent_grain(buf, w, h, accents[s].w, accents[s].h, 3.7, 0);
    printf("%-18s %dx%d @2x  %6.3f ms\n", accents[s].name, w, h, (now_ms() - t0) / n);
    free(buf);
  }
  return 0;
}
