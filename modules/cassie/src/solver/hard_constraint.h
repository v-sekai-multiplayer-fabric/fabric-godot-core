#pragma once

// Track 5 Phase B — Eigen-free constraint-block API. Hard constraints
// are equality rows in the augmented Lagrangian system; the dense
// C matrix gets stacked into the larger KKT or ALM assembly.

#include "dense_matrix.h"

namespace cassie_solver {

// Abstract base for a "hard" KKT constraint block. Returns the matrix C_i
// (row_count rows × 3N cols typically) and the right-hand-side b_i
// added to the equality-constrained system.
class HardConstraintBlock {
public:
	virtual ~HardConstraintBlock() = default;
	virtual void get_blocks(DenseMatrix &r_C, DenseVector &r_b) const = 0;
	virtual int row_count() const = 0;
};

} // namespace cassie_solver
