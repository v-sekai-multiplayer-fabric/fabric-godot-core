#pragma once

#include "core/io/resource.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"
#include "scene/resources/curve.h"

// CassieFinalStroke holds a beautified, immutable stroke that has been
// committed to the sketch graph. Port of E:\cassie\Assets\Scripts\Data\
// Strokes\FinalStroke.cs.
//
// Tier 2 scope: minimal data + simple geometric queries that do NOT require
// graph state (no Graph, INode, ISegment). Graph-integrated methods
// (AddIntersection*, MendSegments, SaveInputSamples, GetGraphData,
// GetControlPointsForSegment, segment LinkedList traversal) are deferred to
// Tier 4 where the GDScript-side sketch_graph.gd holds graph state.
//
// Until Tier 4, calls to graph-dependent methods error out with
// ERR_FAIL_V_MSG so misuse is loud rather than silent.

class CassieIntersectionConstraint;

class CassieFinalStroke : public Resource {
	GDCLASS(CassieFinalStroke, Resource);

	int id = -1;
	Ref<Curve3D> curve;
	PackedVector3Array input_samples;
	bool closed_loop = false;

protected:
	static void _bind_methods();

public:
	CassieFinalStroke() = default;

	void set_id(int p_id) { id = p_id; }
	int get_id() const { return id; }

	void set_curve(const Ref<Curve3D> &p_curve, bool p_closed_loop = false);
	Ref<Curve3D> get_curve() const { return curve; }
	bool is_closed_loop() const { return closed_loop; }

	void set_input_samples(const PackedVector3Array &p_samples) { input_samples = p_samples; }
	PackedVector3Array get_input_samples() const { return input_samples; }

	// Computes the constraint produced by another point intersecting this
	// stroke's curve. Snaps to the curve's nearest anchor when within
	// p_snap_to_existing_node_threshold (Tier 4 will swap to graph nodes
	// once the graph is wired). is_at_node is set true only when the snap
	// landed on a non-endpoint anchor.
	Ref<CassieIntersectionConstraint> get_constraint(
			const Vector3 &p_position,
			real_t p_snap_to_existing_node_threshold) const;

	// Returns the closest point on this stroke's curve to p_position.
	Vector3 closest_point(const Vector3 &p_position) const;

	// GDScript-bound static wrapper for cassie_split_stroke_at_constraints.
	// Implementation forwards to the free function in cassie_intersection_finder.
	static TypedArray<CassieFinalStroke> split_at_constraints(
			const Ref<CassieFinalStroke> &p_stroke,
			const TypedArray<CassieIntersectionConstraint> &p_constraints,
			real_t p_snap_threshold);
};
