// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// C ABI implementation stub for rf-detr-cpp. The real bodies wrap the
// internal C++ decoder (src/decoder.h) and preprocessor into a
// ggml_tensor-free surface a Godot module can call. This initial
// commit lands the ABI shape and status vocabulary; each entry point
// returns RFDETR_ERR_INTERNAL until the paired implementation PR ships.

#include "rfdetr/rfdetr_capi.h"

#include <cstring>

#define RFDETR_ABI_VERSION 1u

struct rfdetr_model {
    // Opaque; real fields land with the implementation PR.
    void *impl = nullptr;
};

extern "C" {

uint32_t rfdetr_abi_version(void) {
    return RFDETR_ABI_VERSION;
}

const char *rfdetr_status_string(rfdetr_status status) {
    switch (status) {
        case RFDETR_OK: return "ok";
        case RFDETR_ERR_INVALID_ARG: return "invalid argument";
        case RFDETR_ERR_LOAD_FAILED: return "checkpoint load failed";
        case RFDETR_ERR_INFERENCE_FAILED: return "inference failed";
        case RFDETR_ERR_OUT_OF_MEMORY: return "out of memory";
        case RFDETR_ERR_INTERNAL: return "internal error";
    }
    return "unknown";
}

void rfdetr_options_init(rfdetr_options *options) {
    if (!options) {
        return;
    }
    std::memset(options, 0, sizeof(*options));
    options->size = sizeof(*options);
    options->num_queries = 300;
    options->score_threshold = 0.5f;
}

rfdetr_status rfdetr_model_load(
    const char *checkpoint_path,
    const rfdetr_options *options,
    rfdetr_model **out_model) {
    if (!checkpoint_path || !out_model) {
        return RFDETR_ERR_INVALID_ARG;
    }
    if (options && options->size < sizeof(rfdetr_options)) {
        // Older caller than this build declares. Still valid — the
        // extra fields default to the values rfdetr_options_init sets.
    }
    // Real load lands with the implementation PR.
    return RFDETR_ERR_INTERNAL;
}

void rfdetr_model_free(rfdetr_model *model) {
    if (!model) {
        return;
    }
    delete model;
}

rfdetr_status rfdetr_detect(
    rfdetr_model *model,
    const uint8_t *image_rgba_bytes,
    int32_t width,
    int32_t height,
    rfdetr_box *out_boxes,
    size_t out_boxes_capacity,
    size_t *out_boxes_count) {
    if (!model || !image_rgba_bytes || !out_boxes_count) {
        return RFDETR_ERR_INVALID_ARG;
    }
    if (width <= 0 || height <= 0) {
        return RFDETR_ERR_INVALID_ARG;
    }
    if (out_boxes_capacity > 0 && !out_boxes) {
        return RFDETR_ERR_INVALID_ARG;
    }
    *out_boxes_count = 0;
    // Real detection lands with the implementation PR.
    return RFDETR_ERR_INTERNAL;
}

}  // extern "C"
