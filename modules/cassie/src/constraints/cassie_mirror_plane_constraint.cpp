#include "cassie_mirror_plane_constraint.h"

#include "core/object/class_db.h"

void CassieMirrorPlaneConstraint::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_plane_normal", "normal"),
			&CassieMirrorPlaneConstraint::set_plane_normal);
	ClassDB::bind_method(D_METHOD("get_plane_normal"),
			&CassieMirrorPlaneConstraint::get_plane_normal);

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "plane_normal"),
			"set_plane_normal", "get_plane_normal");
}
