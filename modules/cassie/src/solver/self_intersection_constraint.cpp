#include "self_intersection_constraint.h"

namespace cassie_solver {

SelfIntersectionConstraint::SelfIntersectionConstraint(int p_anchor_idx_a, int p_anchor_idx_b,
		const Vector3 &p_AB0, int p_N) :
		anchor_idx_a(p_anchor_idx_a), anchor_idx_b(p_anchor_idx_b), AB0(p_AB0), N(p_N) {}

void SelfIntersectionConstraint::get_blocks(DenseMatrix &r_C, DenseVector &r_b) const {
	r_C.zero_resize(3, 3 * N);
	for (int i = 0; i < 3; ++i) {
		r_C(i, 9 * anchor_idx_a + i) = 1.0;
		r_C(i, 9 * anchor_idx_b + i) = -1.0;
	}
	r_b.zero_resize(3);
	r_b[0] = double(AB0.x);
	r_b[1] = double(AB0.y);
	r_b[2] = double(AB0.z);
}

} // namespace cassie_solver
