/**************************************************************************/
/*  xr_grid_procedural_grid_3d.h                                           */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/procedural_grid_3d.gd.           */
/* Drives the two child grid layers' colors + scales as the camera         */
/* approaches/recedes via a log2 of the parent transform's x-basis length. */

#pragma once

#include "scene/3d/node_3d.h"
#include "scene/resources/gradient_texture.h"

class XRGridProceduralGrid3D : public Node3D {
	GDCLASS(XRGridProceduralGrid3D, Node3D);

	Ref<GradientTexture1D> level_color;
	double distance_between_points = 0.5;
	NodePath focus_node_path;
	NodePath grid1_path = NodePath("BaseProceduralGrid3D");
	NodePath grid2_path = NodePath("BaseProceduralGrid3D/BaseProceduralGrid3D2");

	Node3D *grid1 = nullptr;
	Node3D *grid2 = nullptr;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridProceduralGrid3D() = default;

	void set_level_color(const Ref<GradientTexture1D> &p_t) { level_color = p_t; }
	Ref<GradientTexture1D> get_level_color() const { return level_color; }
	void set_distance_between_points(double p_v) { distance_between_points = p_v; }
	double get_distance_between_points() const { return distance_between_points; }
	void set_focus_node_path(const NodePath &p_path) { focus_node_path = p_path; }
	NodePath get_focus_node_path() const { return focus_node_path; }
	void set_grid1_path(const NodePath &p_path) { grid1_path = p_path; }
	NodePath get_grid1_path() const { return grid1_path; }
	void set_grid2_path(const NodePath &p_path) { grid2_path = p_path; }
	NodePath get_grid2_path() const { return grid2_path; }
};
