#include "style.hpp"

#include "handles.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string_view>

#if defined(MOTIONBRICKS_HAVE_GGML)
#include <ggml.h>
#include <gguf.h>
#endif

namespace motionbricks::detail {
namespace {
#if defined(MOTIONBRICKS_HAVE_GGML)

constexpr std::string_view revision = "a0732b642c0333077e127a2f56ab0014c196bca4";
struct gguf_deleter { void operator()(gguf_context * value) const { gguf_free(value); } };
struct ggml_deleter { void operator()(ggml_context * value) const { ggml_free(value); } };

bool string_value(const gguf_context * context, const char * key,
                  std::string_view expected, std::string & reason) {
    const auto index = gguf_find_key(context, key);
    if (index < 0 || gguf_get_kv_type(context, index) != GGUF_TYPE_STRING ||
        std::string_view(gguf_get_val_str(context, index)) != expected) {
        reason = std::string("invalid style metadata: ") + key;
        return false;
    }
    return true;
}

bool shape(const gguf_context * context, const char * name, ggml_type type,
           std::initializer_list<std::int64_t> expected, std::string & reason) {
    const auto index = gguf_find_tensor(context, name);
    if (index < 0 || gguf_get_tensor_type(context, index) != type) {
        reason = std::string("missing or incorrectly typed style tensor: ") + name;
        return false;
    }
    const auto * dimensions = gguf_get_tensor_ne(context, index);
    std::size_t axis = 0;
    for (const auto value : expected) if (dimensions[axis++] != value) {
        reason = std::string("incorrect style tensor shape: ") + name;
        return false;
    }
    for (; axis < 4U; ++axis) if (dimensions[axis] != 1) {
        reason = std::string("incorrect style tensor rank: ") + name;
        return false;
    }
    return true;
}

template<class T>
void copy_tensor(ggml_context * context, const char * name, std::size_t count,
                 std::vector<T> & output) {
    const auto * tensor = ggml_get_tensor(context, name);
    const auto * values = static_cast<const T *>(tensor->data);
    output.assign(values, values + count);
}

#endif
} // namespace

mb_status load_style_file(const std::filesystem::path & path,
                          mb_style & output, std::string & reason) {
#if !defined(MOTIONBRICKS_HAVE_GGML)
    (void)path; (void)output;
    reason = "this build has no GGML support";
    return MB_BACKEND_UNAVAILABLE;
#else
    if (!std::filesystem::is_regular_file(path)) {
        reason = "style file does not exist: " + path.string();
        return MB_IO_ERROR;
    }
    ggml_context * raw = nullptr;
    std::unique_ptr<gguf_context, gguf_deleter> metadata(
        gguf_init_from_file(path.string().c_str(), {false, &raw}));
    std::unique_ptr<ggml_context, ggml_deleter> tensors(raw);
    if (!metadata || !tensors || gguf_get_version(metadata.get()) != 3U) {
        reason = "could not parse style GGUF: " + path.string();
        return MB_INVALID_FORMAT;
    }
    if (!string_value(metadata.get(), "general.architecture", "motionbricks", reason) ||
        !string_value(metadata.get(), "motionbricks.component", "style", reason) ||
        !string_value(metadata.get(), "motionbricks.skeleton", "g1skel34", reason) ||
        !string_value(metadata.get(), "motionbricks.upstream_revision", revision, reason))
        return MB_INCOMPATIBLE_MODEL;
    const auto source_key = gguf_find_key(metadata.get(), "motionbricks.source_sha256");
    if (source_key < 0 || gguf_get_kv_type(metadata.get(), source_key) != GGUF_TYPE_STRING) {
        reason = "style source identity is missing";
        return MB_INVALID_FORMAT;
    }
    const std::string_view source_hash = gguf_get_val_str(metadata.get(), source_key);
    if (source_hash.size() != 64U ||
        !std::all_of(source_hash.begin(), source_hash.end(), [](char value) {
            return (value >= '0' && value <= '9') || (value >= 'a' && value <= 'f');
        })) {
        reason = "style source identity is not a lowercase SHA-256";
        return MB_INVALID_FORMAT;
    }
    const auto name_key = gguf_find_key(metadata.get(), "motionbricks.style_name");
    const auto speed_key = gguf_find_key(metadata.get(), "motionbricks.style_speed");
    const auto frames_key = gguf_find_key(metadata.get(), "motionbricks.style_frames");
    if (name_key < 0 || gguf_get_kv_type(metadata.get(), name_key) != GGUF_TYPE_STRING ||
        speed_key < 0 || gguf_get_kv_type(metadata.get(), speed_key) != GGUF_TYPE_FLOAT32 ||
        frames_key < 0 || gguf_get_kv_type(metadata.get(), frames_key) != GGUF_TYPE_UINT32) {
        reason = "style metadata is incomplete";
        return MB_INVALID_FORMAT;
    }
    mb_style temporary;
    temporary.name = gguf_get_val_str(metadata.get(), name_key);
    temporary.speed = gguf_get_val_f32(metadata.get(), speed_key);
    temporary.frames = gguf_get_val_u32(metadata.get(), frames_key);
    if (temporary.name.empty() || temporary.frames < 4U || temporary.frames > 100000U ||
        !std::isfinite(temporary.speed) || temporary.speed < 0.0F ||
        gguf_get_n_tensors(metadata.get()) != 5) {
        reason = "invalid style metadata values";
        return MB_INVALID_FORMAT;
    }
    const auto frames = static_cast<std::int64_t>(temporary.frames);
    if (!shape(metadata.get(), "global_joint_positions", GGML_TYPE_F32, {3,34,frames}, reason) ||
        !shape(metadata.get(), "global_joint_rotations", GGML_TYPE_F32, {9,34,frames}, reason) ||
        !shape(metadata.get(), "global_root_positions", GGML_TYPE_F32, {3,frames}, reason) ||
        !shape(metadata.get(), "global_headings", GGML_TYPE_F32, {frames}, reason) ||
        !shape(metadata.get(), "allowed_tokens", GGML_TYPE_I32, {11}, reason))
        return MB_INVALID_FORMAT;
    copy_tensor(tensors.get(), "global_joint_positions", temporary.frames * 34U * 3U,
                temporary.global_joint_positions);
    copy_tensor(tensors.get(), "global_joint_rotations", temporary.frames * 34U * 9U,
                temporary.global_joint_rotations);
    copy_tensor(tensors.get(), "global_root_positions", temporary.frames * 3U,
                temporary.global_root_positions);
    copy_tensor(tensors.get(), "global_headings", temporary.frames, temporary.global_headings);
    std::vector<std::int32_t> allowed;
    copy_tensor(tensors.get(), "allowed_tokens", 11U, allowed);
    for (std::size_t index = 0; index < allowed.size(); ++index) {
        if (allowed[index] != 0 && allowed[index] != 1) {
            reason = "style allowed-duration mask is not binary";
            return MB_INVALID_FORMAT;
        }
        temporary.allowed_tokens[index] = static_cast<std::uint8_t>(allowed[index]);
    }
    const auto finite = [](const std::vector<float> & values) {
        return std::all_of(values.begin(), values.end(), [](float value) { return std::isfinite(value); });
    };
    if (!finite(temporary.global_joint_positions) || !finite(temporary.global_joint_rotations) ||
        !finite(temporary.global_root_positions) || !finite(temporary.global_headings)) {
        reason = "style contains non-finite values";
        return MB_INVALID_FORMAT;
    }
    output = std::move(temporary);
    return MB_OK;
#endif
}

} // namespace motionbricks::detail
