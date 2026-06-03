#pragma once

#include "soft_constraint.h"

#include "core/math/vector3.h"
#include "core/templates/vector.h"
#include "core/variant/callable.h"

namespace cassie_solver {

// OnSurfaceEnergy — ENG-54 (Track 4 step 4.2). Soft penalty that pulls
// every control point p_i toward its projection q_i onto a target
// surface S. The Gauss-Newton linearization freezes q_i during one
// solver call (the patch is locally planar, so curvature terms drop):
//
//   E = w · Σ_i |p_i - q_i|²
//   gradient_i = 2 w (p_i - q_i)
//   Hessian_i  ≈ 2 w I_3
//
// Block contributions to the augmented KKT system:
//   A_c at (3i, 3i) .. (3i+2, 3i+2) = 2 w I_3
//   b_c at (3i .. 3i+2)             = 2 w q_i
//
// At the optimum the augmented gradient `A_grad x - b_top` vanishes, so
// `2 w x_i = 2 w q_i` ⇒ `x_i = q_i`. Combined with the fidelity energy
// the result is the Gauss-Newton compromise between staying close to
// the input curve and snapping to the patch.
//
// Per Phase 1 exploration: this composes with PlanarityConstraint
// rather than fighting it the way the post-solve projection at
// cassie_beautifier.cpp:294-316 currently does.
class OnSurfaceEnergy : public SoftConstraintBlock {
public:
	// p_project_callback is the CassieSketchContext::project_on_patch_callback
	// already threaded through CassieBeautifier; it returns the Dictionary
	// CassieSurfacePatch::project produces ("on_surface", "projected", ...).
	OnSurfaceEnergy(const Vector<Vector3> &p_initial_control_points,
			const Callable &p_project_callback,
			double p_weight);

	void get_blocks(DenseMatrix &r_A, DenseVector &r_b) const override;

	// Number of control points where the projection callback reported
	// on_surface = true — i.e. the energy actually has a target there.
	int get_active_count() const { return active_count; }

private:
	int N = 0;
	double w = 0.0;
	Vector<Vector3> initial_cp; // p0_i — needed for the displacement form of b
	Vector<Vector3> targets; // q_i = project(p0_i)
	Vector<bool> active;
	int active_count = 0;
};

} // namespace cassie_solver
