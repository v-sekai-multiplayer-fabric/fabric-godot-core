#pragma once

// Public C++ entry point to the Slang-emitted De Casteljau cubic split
// kernel. Same pattern as saxpby_dispatch.h — implementation in
// curve_casteljau_dispatch.cpp `#include`s the slangc -target cpp output
// directly.
//
// Splits the cubic Bezier (a, b, c, d) at parameter u ∈ [0, 1]. After
// the split: la == a, rd == d, ld == ra is the cut point on the curve.
// All inputs and outputs are float3 (precision loss vs the prior fp64
// hand implementation is acceptable at editing-time scale).
//
// Source-of-truth: `CassieAvbd.CurveCasteljau` Lean module.

namespace cassie_slang_dispatch {

void curve_casteljau(
		const float p_a[3], const float p_b[3],
		const float p_c[3], const float p_d[3],
		float p_u,
		float r_la[3], float r_lb[3], float r_lc[3], float r_ld[3],
		float r_ra[3], float r_rb[3], float r_rc[3], float r_rd[3]);

} // namespace cassie_slang_dispatch
