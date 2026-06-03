#pragma once

// Track 5 Phase B — Eigen-free constraint-block API. The block writes
// dense Hessian (A_c) and RHS (b_c) contributions to be summed into
// the augmented KKT system. CASSIE-scale dense ≤ 45 x 45; the cassie
// PCG path handles the solve.

#include "dense_matrix.h"

namespace cassie_solver {

// Abstract base for a "soft" KKT constraint block. Adds a positive
// semidefinite term to the fidelity-energy Hessian (A_grad += A_c) and a
// linear term to the right-hand side (b_top += b_c).
class SoftConstraintBlock {
public:
	virtual ~SoftConstraintBlock() = default;
	virtual void get_blocks(DenseMatrix &r_A, DenseVector &r_b) const = 0;
};

} // namespace cassie_solver
