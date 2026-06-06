#include "cassie_surface_constraint.h"

#include "core/object/class_db.h"

void CassieSurfaceConstraint::leave(const Vector3 &p_position) {
	left_mid_stroke = true;
	end_position = p_position;
}

void CassieSurfaceConstraint::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_patch_id", "id"), &CassieSurfaceConstraint::set_patch_id);
	ClassDB::bind_method(D_METHOD("get_patch_id"), &CassieSurfaceConstraint::get_patch_id);
	ClassDB::bind_method(D_METHOD("set_start_position", "position"),
			&CassieSurfaceConstraint::set_start_position);
	ClassDB::bind_method(D_METHOD("get_start_position"), &CassieSurfaceConstraint::get_start_position);
	ClassDB::bind_method(D_METHOD("has_left_mid_stroke"),
			&CassieSurfaceConstraint::has_left_mid_stroke);
	ClassDB::bind_method(D_METHOD("set_end_position", "position"),
			&CassieSurfaceConstraint::set_end_position);
	ClassDB::bind_method(D_METHOD("get_end_position"), &CassieSurfaceConstraint::get_end_position);
	ClassDB::bind_method(D_METHOD("leave", "position"), &CassieSurfaceConstraint::leave);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "patch_id"), "set_patch_id", "get_patch_id");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "start_position"),
			"set_start_position", "get_start_position");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "end_position"),
			"set_end_position", "get_end_position");
}
