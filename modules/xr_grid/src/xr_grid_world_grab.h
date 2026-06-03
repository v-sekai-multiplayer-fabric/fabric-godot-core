/**************************************************************************/
/*  xr_grid_world_grab.h                                                   */
/**************************************************************************/
/* Native port of xr-grid/addons/procedural_3d_grid/core/world_grab.gd.    */
/* Utility math for one-handed grab, two-handed pinch, and orbit gestures. */
/* Pure RefCounted with static-style methods (callable as instance or via  */
/* a singleton). Algorithm credit: celyk / V-Sekai.xr-grid.                */

#pragma once

#include "core/math/transform_3d.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"

class XRGridWorldGrab : public RefCounted {
	GDCLASS(XRGridWorldGrab, RefCounted);

protected:
	static void _bind_methods();

public:
	XRGridWorldGrab() = default;

	Transform3D get_grab_transform(const Transform3D &p_from, const Transform3D &p_to);
	Transform3D get_orbit_transform(const Vector3 &p_from_pivot,
			const Vector3 &p_from_b, const Vector3 &p_to_pivot,
			const Vector3 &p_to_b);
	Transform3D get_pinch_transform(const Vector3 &p_from_a, const Vector3 &p_from_b,
			const Vector3 &p_to_a, const Vector3 &p_to_b);
	Transform3D split_blend(const Transform3D &p_from, const Transform3D &p_to,
			real_t p_pos_weight, real_t p_rot_weight, real_t p_scale_weight,
			const Vector3 &p_from_pivot, const Vector3 &p_to_pivot);
};
