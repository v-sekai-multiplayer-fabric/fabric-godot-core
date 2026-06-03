#pragma once

#include "cassie_constraint.h"

#include "../sketch/cassie_final_stroke.h"

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"

// CassieIntersectionConstraint represents a snap from a new stroke onto an
// existing FinalStroke at a specific point. Port of E:\cassie\Assets\
// Scripts\Data\Constraints\IntersectionConstraint.cs.

class CassieIntersectionConstraint : public CassieConstraint {
	GDCLASS(CassieIntersectionConstraint, CassieConstraint);

	Ref<CassieFinalStroke> intersected_stroke;
	Vector3 old_curve_position;
	Vector3 old_curve_tangent;
	real_t old_curve_offset = 0.0;
	bool is_at_node = false;

protected:
	static void _bind_methods();

public:
	CassieIntersectionConstraint() = default;

	void set_intersected_stroke(const Ref<CassieFinalStroke> &p_stroke) { intersected_stroke = p_stroke; }
	Ref<CassieFinalStroke> get_intersected_stroke() const { return intersected_stroke; }

	void set_old_curve_position(const Vector3 &p_pos) { old_curve_position = p_pos; }
	Vector3 get_old_curve_position() const { return old_curve_position; }

	void set_old_curve_tangent(const Vector3 &p_tan) { old_curve_tangent = p_tan; }
	Vector3 get_old_curve_tangent() const { return old_curve_tangent; }

	void set_old_curve_offset(real_t p_offset) { old_curve_offset = p_offset; }
	real_t get_old_curve_offset() const { return old_curve_offset; }

	void set_is_at_node(bool p_v) { is_at_node = p_v; }
	bool get_is_at_node() const { return is_at_node; }
};
