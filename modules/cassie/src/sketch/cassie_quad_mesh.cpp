// CASSIE quad-mesh conversion (ENG-88 follow-up).
//
// Only compiled when the SCsub BUILD_QUAD_MESHING toggle is True. The
// CASSIE_QUAD_MESHING define guards both this file's contents and the
// call site in CassieSurfaceManager::_patch_from_tri_result.
//
// Per-CASSIE-3D-patch quadrangulation: each cycle yields one small tri
// patch (~100-200 verts post-DMWT). This function runs Geogram's frame
// field (4-symmetric direction field) + isotropic remesh on that
// single patch and emits a quad-dominant mesh. Cheap at this size and
// avoids the unified-mesh export-time conversion that wouldn't scale
// with CassieSurfaceManager's per-patch lifecycle.

#ifdef CASSIE_QUAD_MESHING

#include "core/math/vector3.h"
#include "core/variant/variant.h"

// TODO ENG-88-quad — implementation stub. The wiring is:
//   1. Build a GEO::Mesh from p_verts + p_faces (tri).
//   2. Run GEO::FrameField on it.
//   3. Run GEO::remesh_smooth (or PMP isotropic_remeshing) using the
//      field for direction guidance; pick edge length based on the
//      cassie SurfaceManager's target_edge_length.
//   4. Read the quad-dominant result back into p_verts + p_faces.
// Return false on any Geogram failure — caller keeps the tri mesh.
bool cassie_quadrangulate_patch(PackedVector3Array &p_verts,
		PackedInt32Array &p_faces) {
	(void)p_verts;
	(void)p_faces;
	return false;
}

#endif // CASSIE_QUAD_MESHING
