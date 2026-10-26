#ifndef ADE_PAPER_FIELD_KERNELS_H
#define ADE_PAPER_FIELD_KERNELS_H

#include <stdint.h>

/* RGBA, premultiplied last. Three box passes, same radius split as the 0.4.6 field. */
void ade_box_blur_rgba(uint8_t *pixels, uint8_t *tmp, int w, int h, int radius);

/* SceneInk grain. Row 0 is the top. viewW/viewH are the canvas points; w/h are the buffer. */
void ade_scene_grain(
  uint8_t *pixels, int w, int h, double viewW, double viewH, double time, double energy,
  double red, double green, double blue, int night);

/* Accent-surface lattice only. The moving gradient stays in SwiftUI. */
void ade_accent_grain(
  uint8_t *pixels, int w, int h, double viewW, double viewH, double time, int night);

#endif
