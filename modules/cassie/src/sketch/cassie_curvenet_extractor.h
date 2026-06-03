#pragma once

#include "cassie_curvenet.h"
#include "cassie_surface_patch.h"

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

// Mesh-to-curvenet auto-extraction (Step 1.0 / ENG-42).
//
// Three passes:
//   1. Per-edge feature scoring (boundary = π, otherwise dihedral angle).
//   2. Adaptive thresholding: log-sweep K (top-K edges to keep), pick the K
//      whose resulting chain count is closest to p_target_curve_count. The
//      sweep avoids the dihedral-threshold cliff that drowns dense scans
//      in noise or starves sparse low-poly meshes.
//   3. Graph simplification: walk chains between vertices of valence ≠ 2,
//      RDP-reduce each chain, refit with cassie_fit_curve.
//
// Output is a Dictionary that CassieCurvenet::build_from_graph consumes
// directly:
//   { "curves": TypedArray<CassieFinalStroke>,
//     "nodes":  Array<Dictionary{ "id": int,
//                                 "position": Vector3,
//                                 "incident_curve_ids": PackedInt32Array }> }
//
// Every curve's start endpoint shows up in exactly one node's
// incident_curve_ids, same for its end endpoint — ENG-45's adjacency
// depends on this invariant (see ENG-57 lessons).
//
// References:
//   - Nguyen et al., "Shaping the Elements" (SIGGRAPH '23 Talks) — the
//     curvenet rig that Pose mode exposes.
//   - de Goes et al., "Character Articulation through Profile Curves"
//     (ACM TOG 41/4 art. 139, 2022) — the underlying curvenet topology.
class CassieCurvenetExtractor : public RefCounted {
	GDCLASS(CassieCurvenetExtractor, RefCounted);

protected:
	static void _bind_methods();

public:
	// Build the graph-data Dictionary directly. Static so callers don't have
	// to manage an extractor instance for a one-shot extraction.
	// p_curvature_weight (ENG-56) blends a per-vertex cotangent-Laplacian
	// magnitude into the edge score. Default 0 reproduces the original
	// dihedral-only behavior; positive values lift extraction quality on
	// smooth scanned input where natural feature lines are curvature
	// ridges rather than crease edges.
	static Dictionary extract_graph_data(const Ref<CassieSurfacePatch> &p_patch,
			int p_target_curve_count = 200,
			float p_rdp_error = 1e-3f,
			float p_fit_error = 1e-2f,
			float p_curvature_weight = 0.0f);

	// Convenience wrapper that extracts and populates a CassieCurvenet
	// in one call. Equivalent to:
	//   Ref<CassieCurvenet> cn; cn.instantiate();
	//   cn->build_from_graph(extract_graph_data(patch, ...));
	//   cn->set_bound_patch(patch); cn->update_rest_pose(patch);
	//   cn->compute_orientations();
	//   return cn;
	static Ref<CassieCurvenet> extract(const Ref<CassieSurfacePatch> &p_patch,
			int p_target_curve_count = 200,
			float p_rdp_error = 1e-3f,
			float p_fit_error = 1e-2f,
			float p_curvature_weight = 0.0f);
};
