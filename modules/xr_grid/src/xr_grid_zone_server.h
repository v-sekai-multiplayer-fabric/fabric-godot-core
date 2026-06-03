/**************************************************************************/
/*  xr_grid_zone_server.h                                                  */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/fabric/zone_server.gd.           */
/*                                                                         */
/* Minimal QUIC/MultiplayerPeer relay: receives 100-byte entity packets    */
/* from clients and rebroadcasts to the other peers. The upstream version  */
/* was an SceneTree subclass that ran via `--script`; this port is a Node  */
/* you add to your headless server scene and start with `start(peer)`. The */
/* engine fork has no WebTransportPeer yet — pass any MultiplayerPeer.     */

#pragma once

#include "core/object/ref_counted.h"
#include "scene/main/multiplayer_peer.h"
#include "scene/main/node.h"

class XRGridZoneServer : public Node {
	GDCLASS(XRGridZoneServer, Node);

	Ref<MultiplayerPeer> server_peer;
	bool running = false;
	int64_t relay_count = 0;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridZoneServer() = default;

	void start(const Ref<MultiplayerPeer> &p_server_peer);
	void stop();
	bool is_running() const { return running; }
	int64_t get_relay_count() const { return relay_count; }
};
