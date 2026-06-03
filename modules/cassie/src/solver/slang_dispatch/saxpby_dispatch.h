#pragma once

// Public C++ entry point to the Slang-emitted SAXPBY kernel. Same
// pattern as spmv_dispatch.h — implementation in saxpby_dispatch.cpp
// `#include`s the slangc -target cpp output directly.
//
// dst[i] = alpha * x[i] + beta * y[i]  for i in [0, n).
//
// All buffers float32. Length n. Aliasing dst with x or y is permitted
// by the kernel semantics (the fma evaluates each lane independently).
//
// Source-of-truth: `Cloth.SlangCodegen.Saxpby` Lean module.

#include <cstdint>

namespace cassie_slang_dispatch {

void saxpby(int p_n, float p_alpha, float p_beta,
		const float *p_x,
		const float *p_y,
		float *r_dst);

} // namespace cassie_slang_dispatch
