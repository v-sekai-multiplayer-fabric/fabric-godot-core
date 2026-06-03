/**************************************************************************/
/*  xr_grid_fabric_manager.h                                               */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/fabric/fabric_manager.gd.        */
/*                                                                         */
/* Owns the MultiplayerPeer used by xr-grid's session networking, polls    */
/* it per frame, and emits `entity_received` with each 100-byte packet.    */
/* Upstream uses WebTransportPeer specifically; this port takes the base   */
/* `MultiplayerPeer` class so the same code works against ENet, the future */
/* WebTransport peer, or any other transport. The caller supplies the      */
/* peer via `set_peer` (or `connect_to_zone` for upstream-style API        */
/* compatibility — it errors out today since WebTransportPeer isn't in    */
/* the engine fork yet).                                                    */

#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"
#include "scene/main/multiplayer_peer.h"
#include "scene/main/node.h"

class XRGridFabricManager : public Node {
	GDCLASS(XRGridFabricManager, Node);

public:
	enum State {
		STATE_DISCONNECTED = 0,
		STATE_CONNECTING = 1,
		STATE_CONNECTED = 2,
	};

private:
	State state = STATE_DISCONNECTED;
	int64_t local_player_id = 0;
	int frame_counter = 0;
	int hlc_counter = 0;
	Ref<MultiplayerPeer> peer;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridFabricManager() = default;

	// Engine-agnostic peer attachment. Pass any MultiplayerPeer
	// (ENetMultiplayerPeer, future WebTransportPeer, etc.).
	void set_peer(const Ref<MultiplayerPeer> &p_peer);
	Ref<MultiplayerPeer> get_peer() const { return peer; }

	// Upstream-compatible entry. Currently errors out because the engine
	// fork has no WebTransportPeer class. Kept so existing call sites
	// surface a clear error instead of silently disconnecting.
	Error connect_to_zone(const String &p_address, int p_port);

	void send_entity(const PackedByteArray &p_packet);

	State get_state() const { return state; }
	int64_t get_local_player_id() const { return local_player_id; }
	int get_frame_counter() const { return frame_counter; }
	int get_hlc_counter() const { return hlc_counter; }

	// FabricTransformSync calls this after stamping a packet.
	void increment_hlc_counter() { ++hlc_counter; }
};

VARIANT_ENUM_CAST(XRGridFabricManager::State);
