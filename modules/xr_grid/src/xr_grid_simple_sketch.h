/**************************************************************************/
/*  xr_grid_simple_sketch.h                                                */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/simple_sketcher/simple_sketch.gd.*/
/* Generates a ribbon trail mesh from a sequence of stroke_add calls,      */
/* updating a target ArrayMesh in place.                                   */

#pragma once

#include "core/object/ref_counted.h"
#include "scene/resources/mesh.h"

class XRGridSimpleSketch : public RefCounted {
	GDCLASS(XRGridSimpleSketch, RefCounted);

	Ref<ArrayMesh> target_mesh;
	bool is_beginning = false;
	Vector3 prev_point;
	double prev_size = 0.0;
	Color prev_color;
	Vector3 prev_tangent;

protected:
	static void _bind_methods();

public:
	XRGridSimpleSketch() = default;

	void set_target_mesh(const Ref<ArrayMesh> &p_mesh) { target_mesh = p_mesh; }
	Ref<ArrayMesh> get_target_mesh() const { return target_mesh; }

	void stroke_begin();
	void stroke_add(const Vector3 &p_point, double p_size, const Color &p_color);
	void stroke_end();

	void add_line(const Vector3 &p_from, const Vector3 &p_to,
			double p_from_size, double p_to_size,
			const Color &p_from_color, const Color &p_to_color,
			bool p_begin_stroke);
};
