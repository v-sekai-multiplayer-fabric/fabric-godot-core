#pragma once

#include <cstdint>

// Public C++ entry point to the Slang-emitted Newton-Raphson
// reparameterize kernel. Raw-pointer signature for the same TU-isolation
// reasons as curve_rdp_dispatch.h.
//
// Given a cubic Bezier (p_a, p_b, p_c, p_d) and N (point, u_in) pairs,
// writes refined u values into r_u_out. Bug-for-bug compatible with
// the prior C++ reparameterize.
//
// Source-of-truth: `CassieAvbd.CurveNewton` Lean module.

namespace cassie_slang_dispatch {

void curve_newton_reparameterize(
		const float p_a[3], const float p_b[3],
		const float p_c[3], const float p_d[3],
		uint32_t p_count,
		const float *p_in_points_xyz,  // 3 · count floats
		const float *p_in_u,           // count floats
		float *r_u_out);               // count floats

} // namespace cassie_slang_dispatch
