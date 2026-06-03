#include "cassie_intersection_constraint.h"

#include "core/object/class_db.h"

void CassieIntersectionConstraint::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_intersected_stroke", "stroke"),
			&CassieIntersectionConstraint::set_intersected_stroke);
	ClassDB::bind_method(D_METHOD("get_intersected_stroke"),
			&CassieIntersectionConstraint::get_intersected_stroke);
	ClassDB::bind_method(D_METHOD("set_old_curve_position", "position"),
			&CassieIntersectionConstraint::set_old_curve_position);
	ClassDB::bind_method(D_METHOD("get_old_curve_position"),
			&CassieIntersectionConstraint::get_old_curve_position);
	ClassDB::bind_method(D_METHOD("set_old_curve_tangent", "tangent"),
			&CassieIntersectionConstraint::set_old_curve_tangent);
	ClassDB::bind_method(D_METHOD("get_old_curve_tangent"),
			&CassieIntersectionConstraint::get_old_curve_tangent);
	ClassDB::bind_method(D_METHOD("set_old_curve_offset", "offset"),
			&CassieIntersectionConstraint::set_old_curve_offset);
	ClassDB::bind_method(D_METHOD("get_old_curve_offset"),
			&CassieIntersectionConstraint::get_old_curve_offset);
	ClassDB::bind_method(D_METHOD("set_is_at_node", "value"),
			&CassieIntersectionConstraint::set_is_at_node);
	ClassDB::bind_method(D_METHOD("get_is_at_node"),
			&CassieIntersectionConstraint::get_is_at_node);
}
