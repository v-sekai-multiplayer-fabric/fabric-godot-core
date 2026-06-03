/**************************************************************************/
/*  xr_grid_capsule_persona.h                                              */
/**************************************************************************/
/* Capsule-mesh avatar replacement for the upstream Sophia GLB persona.    */
/* Drop in place of any sophia.glb reference in main.tscn — gives a       */
/* lightweight self-renderable presence for the local user that matches    */
/* the height range Sophia was authored at (~1.7 m).                       */

#pragma once

#include "scene/3d/mesh_instance_3d.h"

class XRGridCapsulePersona : public MeshInstance3D {
	GDCLASS(XRGridCapsulePersona, MeshInstance3D);

	double height = 1.7;
	double radius = 0.18;
	Color body_color = Color(0.6, 0.7, 0.85);

	void _rebuild();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridCapsulePersona() = default;

	void set_height(double p_v);
	double get_height() const { return height; }
	void set_radius(double p_v);
	double get_radius() const { return radius; }
	void set_body_color(const Color &p_c);
	Color get_body_color() const { return body_color; }
};
