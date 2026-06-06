// Slang-emitted SAXPBY kernel + dispatch wrapper.
//
// Same pattern as spmv_dispatch.cpp — pull the namespaced .cpu.cpp
// into this TU via #include so the internal types (SaxpbyParams_0,
// GlobalParams_0, _main_0) are visible without re-declaration. The
// dispatch loop simulates a SIMT compute dispatch over the kernel's
// numthreads(256, 1, 1) workgroup shape.
//
// Source-of-truth: `Cloth.SlangCodegen.Saxpby` Lean module.

#include "../../../thirdparty/avbd/saxpby.cpu.cpp"

#include "saxpby_dispatch.h"

namespace cassie_slang_dispatch {

void saxpby(int p_n, float p_alpha, float p_beta,
		const float *p_x,
		const float *p_y,
		float *r_dst) {
	using namespace cassie_slang_saxpby;

	SaxpbyParams_0 params;
	params.n_0 = uint32_t(p_n);
	params.alpha_0 = p_alpha;
	params.beta_0 = p_beta;

	GlobalParams_0 g;
	g.params_0 = &params;
	g.x_0.data = const_cast<float *>(p_x);
	g.x_0.count = size_t(p_n);
	g.y_0.data = const_cast<float *>(p_y);
	g.y_0.count = size_t(p_n);
	g.dst_0.data = r_dst;
	g.dst_0.count = size_t(p_n);

	const int threads_per_group = 256;
	const int num_groups = (p_n + threads_per_group - 1) / threads_per_group;

	for (int gi = 0; gi < num_groups; ++gi) {
		for (int ti = 0; ti < threads_per_group; ++ti) {
			ComputeThreadVaryingInput tvi;
			tvi.groupID = uint3(uint32_t(gi), 0u, 0u);
			tvi.groupThreadID = uint3(uint32_t(ti), 0u, 0u);
			_main_0(&tvi, nullptr, &g);
		}
	}
}

} // namespace cassie_slang_dispatch
