/**************************************************************************/
/*  xr_grid_flatscreen_controller.h                                        */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/flatscreen_controller.gd.        */
/* Mouse + keyboard + gamepad fallback when OpenXR isn't available.        */
/* Attach as a child of XROrigin3D; drives camera + hand transforms.       */

#pragma once

#include "scene/3d/camera_3d.h"
#include "scene/3d/node_3d.h"
#include "scene/main/node.h"

class XRGridFlatscreenController : public Node {
	GDCLASS(XRGridFlatscreenController, Node);

	Camera3D *cam = nullptr;
	Node3D *hand_l = nullptr;
	Node3D *hand_r = nullptr;
	double yaw = 0.0;
	double pitch = 0.0;
	bool active = false;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridFlatscreenController() = default;

	static constexpr double MOVE_SPEED = 3.0;
	static constexpr double TURN_SPEED = 2.0;
	static constexpr double MOUSE_SENS = 0.002;

	bool is_active() const { return active; }
	double get_yaw() const { return yaw; }
	double get_pitch() const { return pitch; }
};
