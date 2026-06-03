/**************************************************************************/
/*  xr_grid_remote_player.cpp                                              */
/**************************************************************************/

#include "xr_grid_remote_player.h"

#include "xr_grid_fabric_transform_sync.h"
#include "xr_grid_orientation_orb.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

Color XRGridRemotePlayer::_color_from_id(int64_t p_pid) {
	const double hue = Math::fmod(double(p_pid) * 0.618033988749895, 1.0);
	return Color::from_ok_hsl(real_t(hue), 0.8f, 0.7f);
}

void XRGridRemotePlayer::_build() {
	if (built) {
		return;
	}
	built = true;
	const Color color = _color_from_id(remote_player_id);
	static const char *part_names[3] = { "head", "hand_left", "hand_right" };
	for (int i = 0; i < 3; ++i) {
		Node3D *part = memnew(Node3D);
		part->set_name(part_names[i]);
		add_child(part);

		XRGridOrientationOrb *orb = memnew(XRGridOrientationOrb);
		orb->setup(i > 0 ? color : color.darkened(0.3f));
		part->add_child(orb);
		orbs.push_back(orb);

		XRGridFabricTransformSync *sync = memnew(XRGridFabricTransformSync);
		sync->set_is_local(false);
		sync->set_sub_index(i);
		sync->set_entity_class(1);
		part->add_child(sync);
		syncs.push_back(sync);
	}
}

void XRGridRemotePlayer::apply_packet(const Dictionary &p_decoded) {
	const int si = int(p_decoded.get("sub_index", 0));
	if (si < 0 || si >= int(syncs.size())) {
		return;
	}
	syncs[si]->apply_remote(p_decoded);
	const Quaternion rot = p_decoded.get("rotation", Quaternion());
	orbs[si]->update_from_basis(Basis(rot));
}

void XRGridRemotePlayer::_notification(int p_what) {
	if (p_what == NOTIFICATION_READY && !built) {
		_build();
	}
}

void XRGridRemotePlayer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_remote_player_id", "v"),
			&XRGridRemotePlayer::set_remote_player_id);
	ClassDB::bind_method(D_METHOD("get_remote_player_id"),
			&XRGridRemotePlayer::get_remote_player_id);
	ClassDB::bind_method(D_METHOD("apply_packet", "decoded"),
			&XRGridRemotePlayer::apply_packet);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "remote_player_id"),
			"set_remote_player_id", "get_remote_player_id");
}
