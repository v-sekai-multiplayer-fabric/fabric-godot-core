#include "cassie_constraint.h"

#include "core/object/class_db.h"

void CassieConstraint::project_on(const Ref<Curve3D> &p_curve) {
	ERR_FAIL_COND(p_curve.is_null());
	new_curve_position = p_curve->get_closest_point(position);
	new_curve_offset = p_curve->get_closest_offset(position);
	if (p_curve->get_baked_length() > 0.0) {
		const Transform3D xform = p_curve->sample_baked_with_rotation(new_curve_offset, true, true);
		new_curve_tangent = -xform.basis.get_column(Vector3::AXIS_Z);
	} else {
		new_curve_tangent = Vector3();
	}
}

void CassieConstraint::project_on_anchor(const Ref<Curve3D> &p_curve, int p_anchor_index) {
	ERR_FAIL_COND(p_curve.is_null());
	const int n = p_curve->get_point_count();
	ERR_FAIL_INDEX(p_anchor_index, n);
	new_curve_position = p_curve->get_point_position(p_anchor_index);

	// Anchor offset: walk through baked segments. Use closest-offset on the
	// anchor's position as an approximation (Curve3D bakes uniformly, so
	// querying by position is accurate to baked granularity).
	new_curve_offset = p_curve->get_closest_offset(new_curve_position);

	// Tangent at the anchor: prefer the out-handle direction when available
	// (matches Unity's BezierCurve.GetTangent for anchorIdx < N).
	Vector3 tangent;
	if (p_anchor_index < n - 1) {
		tangent = p_curve->get_point_out(p_anchor_index);
	} else if (p_anchor_index > 0) {
		tangent = -p_curve->get_point_in(p_anchor_index);
	}
	if (tangent.length_squared() > 0.0) {
		new_curve_tangent = tangent.normalized();
	} else if (p_curve->get_baked_length() > 0.0) {
		const Transform3D xform = p_curve->sample_baked_with_rotation(new_curve_offset, true, true);
		new_curve_tangent = -xform.basis.get_column(Vector3::AXIS_Z);
	} else {
		new_curve_tangent = Vector3();
	}
}

void CassieConstraint::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_position", "position"), &CassieConstraint::set_position);
	ClassDB::bind_method(D_METHOD("get_position"), &CassieConstraint::get_position);
	ClassDB::bind_method(D_METHOD("get_new_curve_position"), &CassieConstraint::get_new_curve_position);
	ClassDB::bind_method(D_METHOD("get_new_curve_tangent"), &CassieConstraint::get_new_curve_tangent);
	ClassDB::bind_method(D_METHOD("get_new_curve_offset"), &CassieConstraint::get_new_curve_offset);
	ClassDB::bind_method(D_METHOD("project_on", "curve"), &CassieConstraint::project_on);
	ClassDB::bind_method(D_METHOD("project_on_anchor", "curve", "anchor_index"),
			&CassieConstraint::project_on_anchor);

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "position"), "set_position", "get_position");
}
