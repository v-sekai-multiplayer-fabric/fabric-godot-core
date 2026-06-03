#include "cassie_final_stroke.h"

#include "../constraints/cassie_intersection_constraint.h"
#include "../constraints/cassie_intersection_finder.h"

#include "core/object/class_db.h"

void CassieFinalStroke::set_curve(const Ref<Curve3D> &p_curve, bool p_closed_loop) {
	curve = p_curve;
	closed_loop = p_closed_loop;
}

Ref<CassieIntersectionConstraint> CassieFinalStroke::get_constraint(
		const Vector3 &p_position,
		real_t p_snap_to_existing_node_threshold) const {
	Ref<CassieIntersectionConstraint> result;
	result.instantiate();
	ERR_FAIL_COND_V_MSG(curve.is_null(), result,
			"CassieFinalStroke::get_constraint called on a stroke without a curve.");

	const Vector3 on_curve_pos = curve->get_closest_point(p_position);
	const real_t on_curve_offset = curve->get_closest_offset(p_position);

	result->set_position(on_curve_pos);
	result->set_intersected_stroke(Ref<CassieFinalStroke>(this));
	result->set_old_curve_position(on_curve_pos);
	result->set_old_curve_offset(on_curve_offset);

	Vector3 old_tangent;
	if (curve->get_baked_length() > 0.0) {
		const Transform3D xform = curve->sample_baked_with_rotation(on_curve_offset, true, true);
		old_tangent = -xform.basis.get_column(Vector3::AXIS_Z);
	}
	result->set_old_curve_tangent(old_tangent);

	// Snap-to-anchor proxy for Tier 4's graph-node snap.
	bool is_at_node = false;
	const int point_count = curve->get_point_count();
	if (point_count > 2) {
		for (int i = 1; i < point_count - 1; ++i) {
			const Vector3 anchor_pos = curve->get_point_position(i);
			if (anchor_pos.distance_to(on_curve_pos) < p_snap_to_existing_node_threshold) {
				is_at_node = true;
				result->set_old_curve_position(anchor_pos);
				result->set_position(anchor_pos);
				result->set_old_curve_offset(curve->get_closest_offset(anchor_pos));
				break;
			}
		}
	}
	result->set_is_at_node(is_at_node);
	return result;
}

Vector3 CassieFinalStroke::closest_point(const Vector3 &p_position) const {
	ERR_FAIL_COND_V(curve.is_null(), Vector3());
	return curve->get_closest_point(p_position);
}

TypedArray<CassieFinalStroke> CassieFinalStroke::split_at_constraints(
		const Ref<CassieFinalStroke> &p_stroke,
		const TypedArray<CassieIntersectionConstraint> &p_constraints,
		real_t p_snap_threshold) {
	return cassie_split_stroke_at_constraints(p_stroke, p_constraints, p_snap_threshold);
}

void CassieFinalStroke::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_id", "id"), &CassieFinalStroke::set_id);
	ClassDB::bind_method(D_METHOD("get_id"), &CassieFinalStroke::get_id);
	ClassDB::bind_method(D_METHOD("set_curve", "curve", "closed_loop"),
			&CassieFinalStroke::set_curve, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_curve"), &CassieFinalStroke::get_curve);
	ClassDB::bind_method(D_METHOD("is_closed_loop"), &CassieFinalStroke::is_closed_loop);
	ClassDB::bind_method(D_METHOD("set_input_samples", "samples"),
			&CassieFinalStroke::set_input_samples);
	ClassDB::bind_method(D_METHOD("get_input_samples"), &CassieFinalStroke::get_input_samples);
	ClassDB::bind_method(D_METHOD("get_constraint", "position", "snap_to_existing_node_threshold"),
			&CassieFinalStroke::get_constraint);
	ClassDB::bind_method(D_METHOD("closest_point", "position"),
			&CassieFinalStroke::closest_point);
	ClassDB::bind_static_method("CassieFinalStroke",
			D_METHOD("split_at_constraints", "stroke", "constraints", "snap_threshold"),
			&CassieFinalStroke::split_at_constraints);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "id"), "set_id", "get_id");
}
