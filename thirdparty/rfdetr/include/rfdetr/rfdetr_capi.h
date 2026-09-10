// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Public C ABI for rf-detr-cpp. Exists because rf-detr-cpp's internal
// surface is C++ classes with ggml_tensor* on the signatures — not
// something a Godot module (or any non-C++ consumer) can wrap without
// pulling ggml into its own translation units.
//
// Added per RFD 2242 as the precondition for
// entities-godot-sandbox/modules/rf_detr/.

#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  if defined(RFDETR_BUILD)
#    define RFDETR_API __declspec(dllexport)
#  else
#    define RFDETR_API __declspec(dllimport)
#  endif
#else
#  define RFDETR_API __attribute__((visibility("default")))
#endif

typedef enum rfdetr_status {
    RFDETR_OK = 0,
    RFDETR_ERR_INVALID_ARG = 1,
    RFDETR_ERR_LOAD_FAILED = 2,
    RFDETR_ERR_INFERENCE_FAILED = 3,
    RFDETR_ERR_OUT_OF_MEMORY = 4,
    RFDETR_ERR_INTERNAL = 5,
} rfdetr_status;

typedef struct rfdetr_model rfdetr_model;

typedef struct rfdetr_box {
    float x;
    float y;
    float width;
    float height;
    float score;
    int32_t class_id;
} rfdetr_box;

// Size-versioned option struct — future fields append; consumers set
// `size` to `sizeof(rfdetr_options)` and callers read as many bytes as
// their build declared. Mirrors motion-bricks-cpp / kimodo convention.
typedef struct rfdetr_options {
    size_t size;
    int32_t num_queries;
    float score_threshold;
} rfdetr_options;

RFDETR_API uint32_t rfdetr_abi_version(void);
RFDETR_API const char *rfdetr_status_string(rfdetr_status status);

RFDETR_API void rfdetr_options_init(rfdetr_options *options);

RFDETR_API rfdetr_status rfdetr_model_load(
    const char *checkpoint_path,
    const rfdetr_options *options,
    rfdetr_model **out_model);

RFDETR_API void rfdetr_model_free(rfdetr_model *model);

// `image_rgba_bytes` points at width*height*4 bytes in RGBA row-major
// order. `out_boxes` receives up to `out_boxes_capacity` boxes; the
// actual number written is placed in `*out_boxes_count`. No ggml_tensor*
// appears in this signature — that's the whole point of the ABI.
RFDETR_API rfdetr_status rfdetr_detect(
    rfdetr_model *model,
    const uint8_t *image_rgba_bytes,
    int32_t width,
    int32_t height,
    rfdetr_box *out_boxes,
    size_t out_boxes_capacity,
    size_t *out_boxes_count);

#ifdef __cplusplus
}  // extern "C"
#endif
