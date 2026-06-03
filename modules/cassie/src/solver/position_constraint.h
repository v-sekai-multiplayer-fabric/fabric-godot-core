#pragma once

#include "hard_constraint.h"

#include "core/math/vector3.h"

namespace cassie_solver {

// PositionConstraint pins a single control point to a target displacement.
// Port of E:\cassie\Assets\Scripts\Create\Sketch\Beautify\PositionConstraint.cs.
//
// One block is a 3 × 3N matrix with identity at columns [3*ctrl_pt_idx,
// 3*ctrl_pt_idx + 2] and b = the displacement vector.
class PositionConstraint : public HardConstraintBlock {
public:
	PositionConstraint(int p_ctrl_pt_idx, const Vector3 &p_displacement, int p_N);

	void get_blocks(DenseMatrix &r_C, DenseVector &r_b) const override;
	int row_count() const override { return 3; }

private:
	int ctrl_pt_idx;
	Vector3 displacement;
	int N;
};

} // namespace cassie_solver
