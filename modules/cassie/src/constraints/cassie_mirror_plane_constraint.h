#pragma once

#include "cassie_constraint.h"

#include "core/math/vector3.h"

// CassieMirrorPlaneConstraint marks the position where a stroke crosses
// the mirror plane. Port of E:\cassie\Assets\Scripts\Data\Constraints\
// MirrorPlaneConstraint.cs.

class CassieMirrorPlaneConstraint : public CassieConstraint {
	GDCLASS(CassieMirrorPlaneConstraint, CassieConstraint);

	Vector3 plane_normal;

protected:
	static void _bind_methods();

public:
	CassieMirrorPlaneConstraint() = default;

	void set_plane_normal(const Vector3 &p_normal) { plane_normal = p_normal; }
	Vector3 get_plane_normal() const { return plane_normal; }
};
