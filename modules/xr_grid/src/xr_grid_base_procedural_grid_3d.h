/**************************************************************************/
/*  xr_grid_base_procedural_grid_3d.h                                      */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/base_procedural_grid_3d.gd.      */
/* MultiMeshInstance3D that emits an N×N×N grid of stylized point markers. */

#pragma once

#include "scene/3d/multimesh_instance_3d.h"

class XRGridBaseProceduralGrid3D : public MultiMeshInstance3D {
	GDCLASS(XRGridBaseProceduralGrid3D, MultiMeshInstance3D);

	int points_per_dimension = 6;
	int n_vertex_circle = 32;
	double fade_zone = 0.5;
	double far_fade = 1.0;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridBaseProceduralGrid3D() = default;

	void set_points_per_dimension(int p_v);
	int get_points_per_dimension() const { return points_per_dimension; }
	void set_n_vertex_circle(int p_v) { n_vertex_circle = p_v; }
	int get_n_vertex_circle() const { return n_vertex_circle; }
	void set_fade_zone(double p_v) { fade_zone = p_v; }
	double get_fade_zone() const { return fade_zone; }
	void set_far_fade(double p_v) { far_fade = p_v; }
	double get_far_fade() const { return far_fade; }

	void set_points_per_dimension_from_fade();
	void regenerate_mesh();
};
