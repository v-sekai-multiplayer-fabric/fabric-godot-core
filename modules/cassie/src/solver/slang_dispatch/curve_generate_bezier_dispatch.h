#pragma once

#include <cstdint>

// Public C++ entry point to the Slang-emitted Schneider Bezier
// generator. Raw-pointer signature (same TU-isolation reason as the
// other curve_*_dispatch).
//
// Given p_count points + p_count u parameters (chord-length normalized
// to [0, 1]) and two endpoint tangents, writes the four control points
// of the LSQ-fit cubic Bezier to r_out_ctrl_xyz (12 floats: P0, P1, P2, P3).
// Falls back to (segment_length / 3)-tangent control points when the
// 2×2 normal equations are singular or yield a non-positive α.
//
// Source-of-truth: `CassieAvbd.CurveGenerateBezier` Lean module.

namespace cassie_slang_dispatch {

void curve_generate_bezier(
		const float p_tangent_a[3], const float p_tangent_b[3],
		uint32_t p_count,
		const float *p_in_points_xyz,  // 3 · count floats
		const float *p_in_u,           // count floats
		float r_out_ctrl_xyz[12]);     // 4 float3 control points

} // namespace cassie_slang_dispatch
