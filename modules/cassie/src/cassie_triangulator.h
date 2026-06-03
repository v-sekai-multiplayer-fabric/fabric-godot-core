#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/array.h"
#include "core/variant/variant.h"
#include "core/variant/array.h"

// Single-call multipolygon triangulator + refinement, mirroring the
// `Triangulate(double*, int, float, double**, int**, int*, int*)` flat C
// ABI from E:\cassie-triangulation\src\Triangulation.cpp, but exposed
// through godot-cpp instead of `extern "C"`.
//
// Pipeline:
//   1. Serialize concurrent callers (Geogram has process-global RNG state).
//   2. Reset the Point3 perturb RNG for call-to-call determinism.
//   3. nB == 3 fast path: skip DMWT, refine the input triangle directly.
//   4. Otherwise: MingCurve edge protection -> DMWT -> cassie_remesh.
//
// Returns a Dictionary with keys:
//   - "success":  bool
//   - "vertices": PackedVector3Array
//   - "faces":    PackedInt32Array (length 3 * num_triangles)
class CassieTriangulator : public RefCounted {
    GDCLASS(CassieTriangulator, RefCounted);

protected:
    static void _bind_methods();

public:
    static Dictionary triangulate(const PackedVector3Array &p_boundary, float p_target_edge_length);

    CassieTriangulator() = default;
    ~CassieTriangulator() = default;
};
