// Slang-emitted Newton reparameterize + dispatch wrapper.
//
// Source-of-truth: `CassieAvbd.CurveNewton` Lean module.

#include "../../../thirdparty/avbd/curve_newton.cpu.cpp"

#include "curve_newton_dispatch.h"

namespace cassie_slang_dispatch {

void curve_newton_reparameterize(
		const float p_a[3], const float p_b[3],
		const float p_c[3], const float p_d[3],
		uint32_t p_count,
		const float *p_in_points_xyz,
		const float *p_in_u,
		float *r_u_out) {
	using namespace cassie_slang_curve_newton;

	if (p_count == 0 || p_in_points_xyz == nullptr || p_in_u == nullptr ||
			r_u_out == nullptr) {
		return;
	}

	// Pack input points into the Slang float3 layout.
	Vector<float, 3> *in_packed = new Vector<float, 3>[p_count];
	for (uint32_t i = 0; i < p_count; ++i) {
		in_packed[i] = Vector<float, 3>(
				p_in_points_xyz[i * 3 + 0],
				p_in_points_xyz[i * 3 + 1],
				p_in_points_xyz[i * 3 + 2]);
	}

	NewtonParams_0 params;
	params.a_0 = Vector<float, 3>(p_a[0], p_a[1], p_a[2]);
	params.b_0 = Vector<float, 3>(p_b[0], p_b[1], p_b[2]);
	params.c_0 = Vector<float, 3>(p_c[0], p_c[1], p_c[2]);
	params.d_0 = Vector<float, 3>(p_d[0], p_d[1], p_d[2]);
	params.count_0 = p_count;

	GlobalParams_0 g;
	g.params_0 = &params;
	g.in_points_0.data = in_packed;
	g.in_points_0.count = p_count;
	g.in_u_0.data = const_cast<float *>(p_in_u);
	g.in_u_0.count = p_count;
	g.out_u_0.data = r_u_out;
	g.out_u_0.count = p_count;

	ComputeThreadVaryingInput tvi;
	tvi.groupID = uint3(0u, 0u, 0u);
	tvi.groupThreadID = uint3(0u, 0u, 0u);
	_main_0(&tvi, nullptr, &g);

	delete[] in_packed;
}

} // namespace cassie_slang_dispatch
