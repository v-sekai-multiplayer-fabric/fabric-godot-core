/**************************************************************************/
/*  xr_grid_remote_player_manager.h                                        */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/fabric/remote_player_manager.gd. */
/*                                                                         */
/* Listens to XRGridFabricManager.entity_received and spawns / despawns    */
/* XRGridRemotePlayer children keyed by decoded peer_id. Times out remote  */
/* players after TIMEOUT_SEC seconds without an update.                    */

#pragma once

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "scene/main/node.h"

class XRGridRemotePlayer;

class XRGridRemotePlayerManager : public Node {
	GDCLASS(XRGridRemotePlayerManager, Node);

	HashMap<int64_t, XRGridRemotePlayer *> players;
	HashMap<int64_t, double> last_seen;
	NodePath fabric_manager_path;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridRemotePlayerManager() = default;

	static constexpr double TIMEOUT_SEC = 10.0;

	void set_fabric_manager_path(const NodePath &p_path) { fabric_manager_path = p_path; }
	NodePath get_fabric_manager_path() const { return fabric_manager_path; }

	int get_remote_player_count() const { return int(players.size()); }

	// Signal target — also publicly callable.
	void on_entity_received(const PackedByteArray &p_packet);
};
