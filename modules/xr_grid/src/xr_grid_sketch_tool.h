/**************************************************************************/
/*  xr_grid_sketch_tool.h                                                  */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/simple_sketcher/sketch_tool.gd.  */
/* Drives XRGridSimpleSketch from a Node3D's global transform.             */

#pragma once

#include "xr_grid_simple_sketch.h"

#include "scene/3d/node_3d.h"

class XRGridSketchTool : public Node3D {
	GDCLASS(XRGridSketchTool, Node3D);

	NodePath canvas_path;
	Node3D *canvas = nullptr;
	bool active = false;
	double pressure = 0.0;
	Color color = Color(0, 0, 0);
	Ref<XRGridSimpleSketch> simple_sketch;
	bool prev_active = false;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridSketchTool();

	void set_canvas_path(const NodePath &p_path) { canvas_path = p_path; }
	NodePath get_canvas_path() const { return canvas_path; }
	void set_active(bool p_v) { active = p_v; }
	bool is_active() const { return active; }
	void set_pressure(double p_v) { pressure = p_v; }
	double get_pressure() const { return pressure; }
	void set_color(const Color &p_v) { color = p_v; }
	Color get_color() const { return color; }
};
