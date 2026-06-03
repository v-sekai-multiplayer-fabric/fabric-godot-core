/**************************************************************************/
/*  xr_grid_remote_player_manager.cpp                                      */
/**************************************************************************/

#include "xr_grid_remote_player_manager.h"

#include "xr_grid_entity_packet.h"
#include "xr_grid_fabric_manager.h"
#include "xr_grid_remote_player.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/os/os.h"

void XRGridRemotePlayerManager::on_entity_received(const PackedByteArray &p_packet) {
	const Dictionary decoded = XRGridEntityPacket::decode(p_packet);
	if (decoded.is_empty()) {
		return;
	}
	const int64_t gid = decoded.get("global_id", 0);
	if (gid < XRGridEntityPacket::PLAYER_ENTITY_BASE) {
		return;
	}
	const int64_t offset = gid - XRGridEntityPacket::PLAYER_ENTITY_BASE;
	const int64_t remote_pid = offset / 3;

	// Skip self-echoes.
	Node *mgr_node = fabric_manager_path.is_empty()
			? get_node_or_null(NodePath("/root/FabricManager"))
			: get_node_or_null(fabric_manager_path);
	XRGridFabricManager *mgr = mgr_node ? Object::cast_to<XRGridFabricManager>(mgr_node) : nullptr;
	if (mgr) {
		const int64_t local_safe =
				mgr->get_local_player_id() % XRGridEntityPacket::MAX_PLAYER_ID;
		if (remote_pid == local_safe) {
			return;
		}
	}

	const double now = double(OS::get_singleton()->get_ticks_msec()) / 1000.0;
	last_seen[remote_pid] = now;

	if (!players.has(remote_pid)) {
		XRGridRemotePlayer *rp = memnew(XRGridRemotePlayer);
		rp->set_remote_player_id(remote_pid);
		rp->set_name(vformat("RemotePlayer_%d", remote_pid));
		add_child(rp);
		players[remote_pid] = rp;
	}
	players[remote_pid]->apply_packet(decoded);
}

void XRGridRemotePlayerManager::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			Node *mgr_node = fabric_manager_path.is_empty()
					? get_node_or_null(NodePath("/root/FabricManager"))
					: get_node_or_null(fabric_manager_path);
			if (mgr_node) {
				mgr_node->connect("entity_received",
						callable_mp(this, &XRGridRemotePlayerManager::on_entity_received));
			}
			set_process(true);
		} break;
		case NOTIFICATION_PROCESS: {
			const double now = double(OS::get_singleton()->get_ticks_msec()) / 1000.0;
			LocalVector<int64_t> expired;
			for (const KeyValue<int64_t, double> &kv : last_seen) {
				if (now - kv.value > TIMEOUT_SEC) {
					expired.push_back(kv.key);
				}
			}
			for (uint32_t i = 0; i < expired.size(); ++i) {
				const int64_t pid = expired[i];
				HashMap<int64_t, XRGridRemotePlayer *>::Iterator it = players.find(pid);
				if (it) {
					it->value->queue_free();
					players.erase(pid);
				}
				last_seen.erase(pid);
			}
		} break;
		default:
			break;
	}
}

void XRGridRemotePlayerManager::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_fabric_manager_path", "p"),
			&XRGridRemotePlayerManager::set_fabric_manager_path);
	ClassDB::bind_method(D_METHOD("get_fabric_manager_path"),
			&XRGridRemotePlayerManager::get_fabric_manager_path);
	ClassDB::bind_method(D_METHOD("on_entity_received", "packet"),
			&XRGridRemotePlayerManager::on_entity_received);
	ClassDB::bind_method(D_METHOD("get_remote_player_count"),
			&XRGridRemotePlayerManager::get_remote_player_count);

	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "fabric_manager_path"),
			"set_fabric_manager_path", "get_fabric_manager_path");
}
