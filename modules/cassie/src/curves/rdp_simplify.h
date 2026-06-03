#pragma once

#include "core/math/vector3.h"
#include "core/variant/variant.h"

// Ramer-Douglas-Peucker polyline simplification.
// Port of E:\cassie\Assets\Scripts\Curves\RamerDouglasPeucker.cs.
//
// Workflow: callers typically call remove_duplicates() first, then rdp_reduce()
// on the result. The fitter (cassie_curve_fit.cpp) is the primary consumer.

// Removes consecutive duplicate points. If no duplicates are present, returns
// p_pts unchanged (no allocation). Non-consecutive equal points are preserved.
PackedVector3Array cassie_rdp_remove_duplicates(const PackedVector3Array &p_pts);

// Reduces a polyline by removing points whose perpendicular distance to the
// straight line between two surviving neighbours is below p_error.
// Returns the kept indices into p_pts (caller can subscript p_pts by the result).
// Indices are returned in ascending order. Endpoints are always kept.
PackedInt32Array cassie_rdp_reduce(const PackedVector3Array &p_pts, float p_error);
