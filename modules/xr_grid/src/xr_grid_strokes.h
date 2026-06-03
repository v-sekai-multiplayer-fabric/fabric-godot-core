/**************************************************************************/
/*  xr_grid_strokes.h                                                      */
/**************************************************************************/
/* Native port of xr-grid/addons/procedural_3d_grid/core/strokes.gd.       */
/* MeshInstance3D that writes dual-hand strokes into its own mesh.         */

#pragma once

#include "xr_grid_simple_sketch.h"

#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/xr/xr_nodes.h"

class XRGridStrokes : public MeshInstance3D {
	GDCLASS(XRGridStrokes, MeshInstance3D);

	NodePath hand_left_path;
	NodePath hand_right_path;
	XRController3D *hand_left = nullptr;
	XRController3D *hand_right = nullptr;
	Ref<XRGridSimpleSketch> simple_sketch;
	Transform3D prev_hand_left_transform;
	Transform3D prev_hand_right_transform;
	double prev_hand_left_pressed = 0.0;
	double prev_hand_right_pressed = 0.0;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridStrokes();

	void set_hand_left_path(const NodePath &p_path) { hand_left_path = p_path; }
	NodePath get_hand_left_path() const { return hand_left_path; }
	void set_hand_right_path(const NodePath &p_path) { hand_right_path = p_path; }
	NodePath get_hand_right_path() const { return hand_right_path; }
};
