#pragma once

#include "soft_constraint.h"

#include "core/math/vector3.h"
#include "core/templates/vector.h"

namespace cassie_solver {

// TangentConstraint is a soft penalty that aligns the inter-anchor tangent
// at index ctrl_pt_idx with a target direction t_target. Port of
// E:\cassie\Assets\Scripts\Create\Sketch\Beautify\TangentConstraint.cs.
//
// Uses the skew-symmetric cross-product matrix of t_target; the energy is
// proportional to | (P_idxB - P_idxA) × t_target |² scaled by 2/||T0||².
class TangentConstraint : public SoftConstraintBlock {
public:
	TangentConstraint(int p_ctrl_pt_idx, const Vector3 &p_t_target,
			const Vector<Vector3> &p_initial_control_points);

	void get_blocks(DenseMatrix &r_A, DenseVector &r_b) const override;

private:
	int idx_a = 0;
	int idx_b = 0;
	int N = 0;
	Vector3 T0;
	double t_cross[9] = { 0.0 };
};

} // namespace cassie_solver
