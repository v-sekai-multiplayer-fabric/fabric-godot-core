#pragma once

#include "soft_constraint.h"

#include "core/math/plane.h"
#include "core/math/vector3.h"
#include "core/templates/vector.h"

namespace cassie_solver {

// PlanarityConstraint is a soft penalty that drives the curve toward a
// given plane. Port of E:\cassie\Assets\Scripts\Create\Sketch\Beautify\
// PlanarityConstraint.cs.
//
// Sums  Σᵢ (1/||T0ᵢ||²) * (normal · (P_{i+1} - Pᵢ))²  with a factor
// 2/(N-1) so the energy scales with control-point count.
class PlanarityConstraint : public SoftConstraintBlock {
public:
	PlanarityConstraint(const Vector3 &p_normal, const Vector<Vector3> &p_initial_control_points);

	void get_blocks(DenseMatrix &r_A, DenseVector &r_b) const override;

private:
	int N = 0;
	double normal[3] = { 0.0, 0.0, 0.0 };
	Vector<double> tangent_norms2;
	Vector<Vector3> T0;
};

// Best-fit plane through a point set via the 3 × 3 covariance + smallest
// eigenvector. Returns the plane normal as the smallest-eigenvalue
// eigenvector and the centroid as a point on the plane; the average
// signed distance of input points to the plane is returned in
// r_avg_distance.
Plane cassie_fit_plane(const Vector<Vector3> &p_points, double &r_avg_distance);

} // namespace cassie_solver
