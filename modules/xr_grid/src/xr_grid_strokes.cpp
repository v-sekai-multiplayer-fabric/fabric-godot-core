/**************************************************************************/
/*  xr_grid_strokes.cpp                                                    */
/**************************************************************************/

#include "xr_grid_strokes.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

XRGridStrokes::XRGridStrokes() {
	simple_sketch.instantiate();
}

void XRGridStrokes::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			Ref<ArrayMesh> am = get_mesh();
			if (am.is_null()) {
				am.instantiate();
				set_mesh(am);
			}
			simple_sketch->set_target_mesh(am);
			if (!hand_left_path.is_empty()) {
				hand_left = Object::cast_to<XRController3D>(get_node_or_null(hand_left_path));
			}
			if (!hand_right_path.is_empty()) {
				hand_right = Object::cast_to<XRController3D>(get_node_or_null(hand_right_path));
			}
			set_process(true);
		} break;
		case NOTIFICATION_PROCESS: {
			if (hand_left == nullptr || hand_right == nullptr) {
				return;
			}
			const double max_size = 0.01;
			const double hl_pressed = hand_left->get_float("trigger") > 0.05 ? 1.0 : 0.0;
			const double hr_pressed = hand_right->get_float("trigger") > 0.05 ? 1.0 : 0.0;
			if (!Math::is_zero_approx(hl_pressed)) {
				const Vector3 from = to_local(prev_hand_left_transform.origin);
				const Vector3 to = to_local(hand_left->get_global_transform().origin);
				const bool just_pressed = Math::is_zero_approx(prev_hand_left_pressed);
				simple_sketch->add_line(from, to,
						prev_hand_left_pressed * max_size,
						hl_pressed * max_size,
						Color(1, 1, 1), Color(1, 1, 1),
						just_pressed);
			}
			if (!Math::is_zero_approx(hr_pressed)) {
				const Vector3 from = to_local(prev_hand_right_transform.origin);
				const Vector3 to = to_local(hand_right->get_global_transform().origin);
				const bool just_pressed = Math::is_zero_approx(prev_hand_right_pressed);
				simple_sketch->add_line(from, to,
						prev_hand_right_pressed * max_size,
						hr_pressed * max_size,
						Color(0, 0, 0), Color(0, 0, 0),
						just_pressed);
			}
			prev_hand_left_transform = hand_left->get_global_transform();
			prev_hand_right_transform = hand_right->get_global_transform();
			prev_hand_left_pressed = hl_pressed;
			prev_hand_right_pressed = hr_pressed;
		} break;
		default:
			break;
	}
}

void XRGridStrokes::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_hand_left_path", "p"),
			&XRGridStrokes::set_hand_left_path);
	ClassDB::bind_method(D_METHOD("get_hand_left_path"),
			&XRGridStrokes::get_hand_left_path);
	ClassDB::bind_method(D_METHOD("set_hand_right_path", "p"),
			&XRGridStrokes::set_hand_right_path);
	ClassDB::bind_method(D_METHOD("get_hand_right_path"),
			&XRGridStrokes::get_hand_right_path);

	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "hand_left_path"),
			"set_hand_left_path", "get_hand_left_path");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "hand_right_path"),
			"set_hand_right_path", "get_hand_right_path");
}
