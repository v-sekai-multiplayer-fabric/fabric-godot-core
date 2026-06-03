/**************************************************************************/
/*  xr_grid_orientation_orb.h                                              */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/fabric/orientation_orb.gd.       */
/*                                                                         */
/* 7-point orientation visualization: 1 origin sphere + 6 axis-endpoint    */
/* spheres (±X red, ±Y green, ±Z blue) + 3 axis line segments. Matches     */
/* the many_bone_ik effector heading representation.                       */

#pragma once

#include "core/templates/local_vector.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/node_3d.h"
#include "scene/resources/immediate_mesh.h"

class XRGridOrientationOrb : public Node3D {
	GDCLASS(XRGridOrientationOrb, Node3D);

	LocalVector<MeshInstance3D *> spheres;
	MeshInstance3D *lines = nullptr;
	Color player_color = Color(1, 1, 1);
	bool initialized = false;

	void _build();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridOrientationOrb() = default;

	static constexpr float AXIS_RADIUS = 0.08f;
	static constexpr float SPHERE_RADIUS = 0.015f;

	void setup(const Color &p_player_color);
	void update_from_basis(const Basis &p_basis);
};
