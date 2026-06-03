#pragma once

#include "core/io/resource.h"
#include "core/math/vector3.h"

// CassieSurfaceConstraint records that the user's stroke was drawing on a
// surface patch — a dual-phase constraint with an entry (start) position
// and an optional exit (end) position when the user left mid-stroke.
// Port of E:\cassie\Assets\Scripts\Data\Constraints\SurfaceConstraint.cs.
//
// SurfaceConstraint is NOT a Constraint subclass in Unity, so the C++ port
// keeps it as a standalone Resource.

class CassieSurfaceConstraint : public Resource {
	GDCLASS(CassieSurfaceConstraint, Resource);

	int patch_id = -1;
	Vector3 start_position;
	bool left_mid_stroke = false;
	Vector3 end_position;

protected:
	static void _bind_methods();

public:
	CassieSurfaceConstraint() = default;

	void set_patch_id(int p_id) { patch_id = p_id; }
	int get_patch_id() const { return patch_id; }

	void set_start_position(const Vector3 &p_pos) { start_position = p_pos; }
	Vector3 get_start_position() const { return start_position; }

	bool has_left_mid_stroke() const { return left_mid_stroke; }

	void set_end_position(const Vector3 &p_pos) { end_position = p_pos; }
	Vector3 get_end_position() const { return end_position; }

	// Marks the stroke as having left the surface and records the exit point.
	void leave(const Vector3 &p_position);
};
