/**************************************************************************/
/*  xr_grid_zone_scene_tree.h                                              */
/**************************************************************************/
/* SceneTree-derived headless relay for the xr-grid fabric zone server.    */
/* Mirrors upstream xr-grid's zone_server.gd (which `extends SceneTree`)   */
/* so you can boot a relay process via:                                    */
/*                                                                         */
/*   godot --headless --main-loop XRGridZoneSceneTree                      */
/*         [--zone-port=9000]                                              */
/*                                                                         */
/* Resolves WebTransportPeer + Crypto dynamically via ClassDB so this      */
/* module never takes a hard build-link dep on modules/http3 — if you      */
/* boot without http3 in the build the SceneTree prints a clear error and  */
/* exits at the first frame.                                                */

#pragma once

#include "scene/main/multiplayer_peer.h"
#include "scene/main/scene_tree.h"

class XRGridZoneSceneTree : public SceneTree {
	GDCLASS(XRGridZoneSceneTree, SceneTree);

	Ref<MultiplayerPeer> server_peer;
	int zone_port = 9000;
	bool started = false;
	bool aborted = false;
	int64_t relay_count = 0;

	void _parse_cmdline();
	bool _try_start_server();

protected:
	static void _bind_methods();

public:
	XRGridZoneSceneTree() = default;

	// SceneTree overrides — these run the main loop directly when this
	// class is selected as the main loop on engine boot.
	virtual void initialize() override;
	virtual bool process(double p_time) override;
	virtual void finalize() override;

	int get_zone_port() const { return zone_port; }
	int64_t get_relay_count() const { return relay_count; }
	bool is_running() const { return started && !aborted; }
};
