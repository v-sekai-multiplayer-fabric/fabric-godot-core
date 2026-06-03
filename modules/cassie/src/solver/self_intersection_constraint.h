#pragma once

#include "hard_constraint.h"

#include "core/math/vector3.h"

namespace cassie_solver {

// SelfIntersectionConstraint pins two anchors A and B to maintain their
// initial separation AB0. Port of E:\cassie\Assets\Scripts\Create\Sketch\
// Beautify\SelfIntersectionConstraint.cs.
//
// Note on indexing: Unity uses `3 * 3 * anchorIdx` which translates the
// anchor index into the flattened control-point address. Anchor k occupies
// control-point index 3*k; flattening to 3-dim coords gives offset 9*k.
// Despite looking like a bug at first glance, this matches the rest of the
// solver's convention (PositionConstraint uses cp-index times 3; here the
// argument is already in anchor-index space).
class SelfIntersectionConstraint : public HardConstraintBlock {
public:
	SelfIntersectionConstraint(int p_anchor_idx_a, int p_anchor_idx_b,
			const Vector3 &p_AB0, int p_N);

	void get_blocks(DenseMatrix &r_C, DenseVector &r_b) const override;
	int row_count() const override { return 3; }

private:
	int anchor_idx_a;
	int anchor_idx_b;
	Vector3 AB0;
	int N;
};

} // namespace cassie_solver
