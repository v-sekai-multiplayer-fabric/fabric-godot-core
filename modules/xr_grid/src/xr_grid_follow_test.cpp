/**************************************************************************/
/*  xr_grid_follow_test.cpp                                                */
/**************************************************************************/

#include "xr_grid_follow_test.h"

#include "core/object/class_db.h"

XRGridFollowTest::XRGridFollowTest() {
	world_grab.instantiate();
}

void XRGridFollowTest::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY:
			set_as_top_level(true);
			set_process(true);
			break;
		case NOTIFICATION_PROCESS: {
			Node3D *parent = Object::cast_to<Node3D>(get_parent());
			if (parent == nullptr) {
				return;
			}
			const Transform3D blended = world_grab->split_blend(
					parent->get_global_transform(),
					get_global_transform(),
					0.6, 0.99, 0.8,
					parent->get_global_transform().origin,
					Vector3());
			set_global_transform(blended);
		} break;
		default:
			break;
	}
}

void XRGridFollowTest::_bind_methods() {
}
