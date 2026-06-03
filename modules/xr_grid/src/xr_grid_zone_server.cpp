/**************************************************************************/
/*  xr_grid_zone_server.cpp                                                */
/**************************************************************************/

#include "xr_grid_zone_server.h"

#include "core/object/class_db.h"

void XRGridZoneServer::start(const Ref<MultiplayerPeer> &p_server_peer) {
	ERR_FAIL_COND_MSG(p_server_peer.is_null(),
			"XRGridZoneServer::start — peer is null.");
	server_peer = p_server_peer;
	running = true;
	set_process(true);
}

void XRGridZoneServer::stop() {
	running = false;
	set_process(false);
	server_peer.unref();
}

void XRGridZoneServer::_notification(int p_what) {
	if (p_what != NOTIFICATION_PROCESS) {
		return;
	}
	if (!running || server_peer.is_null()) {
		return;
	}
	server_peer->poll();
	while (server_peer->get_available_packet_count() > 0) {
		const uint8_t *data = nullptr;
		int len = 0;
		if (server_peer->get_packet(&data, len) != OK || len <= 0) {
			break;
		}
		if (len == 100) {
			server_peer->set_target_peer(0);
			server_peer->set_transfer_mode(MultiplayerPeer::TRANSFER_MODE_UNRELIABLE);
			server_peer->put_packet(data, len);
			++relay_count;
		}
	}
}

void XRGridZoneServer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start", "server_peer"),
			&XRGridZoneServer::start);
	ClassDB::bind_method(D_METHOD("stop"), &XRGridZoneServer::stop);
	ClassDB::bind_method(D_METHOD("is_running"), &XRGridZoneServer::is_running);
	ClassDB::bind_method(D_METHOD("get_relay_count"),
			&XRGridZoneServer::get_relay_count);
}
