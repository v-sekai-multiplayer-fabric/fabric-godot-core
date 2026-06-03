#pragma once

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "scene/resources/curve.h"

// CassieConstraint is the base class for sketch constraints emitted by the
// Tier-2 intersection finder. Port of E:\cassie\Assets\Scripts\Data\
// Constraints\Constraint.cs.
//
// Each constraint stores the world-space position where it was detected
// plus a "new curve data" triple (position + tangent + offset) that gets
// populated by project_on once the candidate curve has been fit.
//
// Subclasses (Intersection, MirrorPlane) add their own metadata.
// SurfaceConstraint is a standalone Resource — it is NOT a Constraint
// subclass in Unity either, so the C++ port keeps that hierarchy.

class CassieConstraint : public RefCounted {
	GDCLASS(CassieConstraint, RefCounted);

protected:
	Vector3 position;
	Vector3 new_curve_position;
	Vector3 new_curve_tangent;
	real_t new_curve_offset = 0.0;

	static void _bind_methods();

public:
	CassieConstraint() = default;
	explicit CassieConstraint(const Vector3 &p_position) :
			position(p_position) {}

	void set_position(const Vector3 &p_pos) { position = p_pos; }
	Vector3 get_position() const { return position; }

	Vector3 get_new_curve_position() const { return new_curve_position; }
	Vector3 get_new_curve_tangent() const { return new_curve_tangent; }
	real_t get_new_curve_offset() const { return new_curve_offset; }

	// Projects this constraint onto p_curve, populating new_curve_*.
	// Uses Curve3D::get_closest_point/offset and tangent from the baked
	// rotation basis Z. Safe to call multiple times.
	void project_on(const Ref<Curve3D> &p_curve);

	// Projects onto a specific anchor of p_curve (analog of Unity's
	// ProjectOn(BezierCurve, anchorIdx)).
	void project_on_anchor(const Ref<Curve3D> &p_curve, int p_anchor_index);
};
