#include "xr_grid_stroke_channel.h"

#include "core/object/class_db.h"

Error XRGridStrokeChannel::send_stroke(const PackedByteArray &p_packet) {
	ERR_FAIL_COND_V_MSG(peer.is_null(), ERR_UNAVAILABLE,
			"XRGridStrokeChannel: no peer configured.");
	if (peer->get_connection_status() != MultiplayerPeer::CONNECTION_CONNECTED) {
		return ERR_UNAVAILABLE;
	}
	if (p_packet.size() == 0) {
		return ERR_INVALID_DATA;
	}

	peer->set_target_peer(0); // broadcast
	peer->set_transfer_channel(stroke_channel);
	peer->set_transfer_mode(MultiplayerPeer::TRANSFER_MODE_RELIABLE);

	const Error err = peer->put_packet(p_packet.ptr(), p_packet.size());
	if (err == OK) {
		++reliable_send_count;
	}
	return err;
}

void XRGridStrokeChannel::poll() {
	if (peer.is_null()) {
		return;
	}
	peer->poll();
	while (peer->get_available_packet_count() > 0) {
		const uint8_t *data = nullptr;
		int len = 0;
		if (peer->get_packet(&data, len) != OK || len <= 0) {
			break;
		}
		PackedByteArray packet;
		packet.resize(len);
		memcpy(packet.ptrw(), data, len);

		if (len >= 4) {
			const uint32_t magic =
					uint32_t(uint8_t(packet[0])) |
					(uint32_t(uint8_t(packet[1])) << 8) |
					(uint32_t(uint8_t(packet[2])) << 16) |
					(uint32_t(uint8_t(packet[3])) << 24);
			if (magic == MAGIC) {
				++reliable_receive_count;
				emit_signal("stroke_packet_received", packet);
				continue;
			}
		}
		emit_signal("entity_packet_received", packet);
	}
}

void XRGridStrokeChannel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_peer", "peer"),
			&XRGridStrokeChannel::set_peer);
	ClassDB::bind_method(D_METHOD("get_peer"),
			&XRGridStrokeChannel::get_peer);
	ClassDB::bind_method(D_METHOD("set_stroke_channel", "channel"),
			&XRGridStrokeChannel::set_stroke_channel);
	ClassDB::bind_method(D_METHOD("get_stroke_channel"),
			&XRGridStrokeChannel::get_stroke_channel);
	ClassDB::bind_method(D_METHOD("get_reliable_send_count"),
			&XRGridStrokeChannel::get_reliable_send_count);
	ClassDB::bind_method(D_METHOD("get_reliable_receive_count"),
			&XRGridStrokeChannel::get_reliable_receive_count);
	ClassDB::bind_method(D_METHOD("send_stroke", "packet"),
			&XRGridStrokeChannel::send_stroke);
	ClassDB::bind_method(D_METHOD("poll"),
			&XRGridStrokeChannel::poll);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "peer",
						  PROPERTY_HINT_RESOURCE_TYPE, "MultiplayerPeer"),
			"set_peer", "get_peer");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "stroke_channel"),
			"set_stroke_channel", "get_stroke_channel");

	ADD_SIGNAL(MethodInfo("stroke_packet_received",
			PropertyInfo(Variant::PACKED_BYTE_ARRAY, "packet")));
	ADD_SIGNAL(MethodInfo("entity_packet_received",
			PropertyInfo(Variant::PACKED_BYTE_ARRAY, "packet")));
}
