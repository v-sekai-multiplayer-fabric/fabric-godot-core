#pragma once

#include <cstdint>

// Public C++ entry point to the Slang-emitted Ramer-Douglas-Peucker
// polyline simplifier. Same pattern as curve_casteljau_dispatch.h —
// raw-pointer signature so the slang-cpp-prelude.h types don't leak
// into the same TU as Godot's PackedInt32Array (the two collide on
// the `Vector` template name).
//
// Bug-for-bug compatible with the prior C++ rdp_recursive — same
// "split == 0 means none found" sentinel.
//
// Source-of-truth: `CassieAvbd.CurveRdp` Lean module.

namespace cassie_slang_dispatch {

// Fills r_out_keep with 1 for kept indices, 0 for dropped. r_out_keep
// must point to at least p_in_count uint32_t entries. Returns the
// number of kept indices (= sum of the bitmask). Caller iterates
// r_out_keep[0..p_in_count) and collects the 1-marked indices.
uint32_t curve_rdp_reduce(const float *p_in_points_xyz,
		uint32_t p_in_count, float p_error,
		uint32_t *r_out_keep);

} // namespace cassie_slang_dispatch
