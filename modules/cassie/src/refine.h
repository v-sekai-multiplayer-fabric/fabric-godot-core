#pragma once
#include "cassie_remesh.h"

// Uniform remesh in-place. Pass the original DMWT verts/indices as the
// reference surface so new vertices are projected back after each smooth pass.
void refine_patch(PackedVector3Array &p_verts, PackedInt32Array &p_indices,
		float p_target_edge_length,
		const PackedVector3Array &p_ref_verts = PackedVector3Array(),
		const PackedInt32Array &p_ref_indices = PackedInt32Array());
