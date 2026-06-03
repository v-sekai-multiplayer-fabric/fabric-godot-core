/**************************************************************************/
/*  xr_grid_hand.h                                                         */
/**************************************************************************/
/* Native port of xr-grid/addons/procedural_3d_grid/core/hand.gd.          */
/* Subclasses XRController3D; reads trigger to drive an associated sketch  */
/* tool, with debug save/load on a/b buttons.                              */

#pragma once

#include "scene/3d/xr/xr_nodes.h"

class XRGridHand : public XRController3D {
	GDCLASS(XRGridHand, XRController3D);

	NodePath sketch_tool_path;
	String save_path = "user://test_save.mesh";
	double max_pressure_size = 0.01;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridHand() = default;

	void set_sketch_tool_path(const NodePath &p_path) { sketch_tool_path = p_path; }
	NodePath get_sketch_tool_path() const { return sketch_tool_path; }
	void set_save_path(const String &p_p) { save_path = p_p; }
	String get_save_path() const { return save_path; }
	void set_max_pressure_size(double p_v) { max_pressure_size = p_v; }
	double get_max_pressure_size() const { return max_pressure_size; }
};
