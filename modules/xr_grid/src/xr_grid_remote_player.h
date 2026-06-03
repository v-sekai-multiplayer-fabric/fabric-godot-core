/**************************************************************************/
/*  xr_grid_remote_player.h                                                */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/fabric/remote_player.gd.         */
/*                                                                         */
/* One Node3D per remote peer with three sub-Node3Ds (head, hand_left,     */
/* hand_right), each carrying an XRGridOrientationOrb visualizer and an    */
/* XRGridFabricTransformSync in remote mode. apply_packet routes by        */
/* sub_index.                                                              */

#pragma once

#include "core/templates/local_vector.h"
#include "scene/3d/node_3d.h"

class XRGridFabricTransformSync;
class XRGridOrientationOrb;

class XRGridRemotePlayer : public Node3D {
	GDCLASS(XRGridRemotePlayer, Node3D);

	int64_t remote_player_id = 0;
	LocalVector<XRGridFabricTransformSync *> syncs;
	LocalVector<XRGridOrientationOrb *> orbs;
	bool built = false;

	void _build();

	static Color _color_from_id(int64_t p_pid);

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridRemotePlayer() = default;

	void set_remote_player_id(int64_t p_v) { remote_player_id = p_v; }
	int64_t get_remote_player_id() const { return remote_player_id; }

	void apply_packet(const Dictionary &p_decoded);
};
