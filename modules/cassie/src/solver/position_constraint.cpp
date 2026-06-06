#include "position_constraint.h"

namespace cassie_solver {

PositionConstraint::PositionConstraint(int p_ctrl_pt_idx, const Vector3 &p_displacement, int p_N) :
		ctrl_pt_idx(p_ctrl_pt_idx), displacement(p_displacement), N(p_N) {}

void PositionConstraint::get_blocks(DenseMatrix &r_C, DenseVector &r_b) const {
	r_C.zero_resize(3, 3 * N);
	for (int i = 0; i < 3; ++i) {
		r_C(i, 3 * ctrl_pt_idx + i) = 1.0;
	}
	r_b.zero_resize(3);
	r_b[0] = double(displacement.x);
	r_b[1] = double(displacement.y);
	r_b[2] = double(displacement.z);
}

} // namespace cassie_solver
