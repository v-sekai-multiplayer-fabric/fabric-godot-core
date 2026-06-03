#pragma once

#include "polygon_triangulation.h"

#include "scene/resources/mesh.h"
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/array.h"
#include "core/variant/variant.h"

class PolygonTriangulationGodot : public RefCounted {
	GDCLASS(PolygonTriangulationGodot, RefCounted);

private:
	Ref<PolygonTriangulation> triangulator;
	mutable PackedVector3Array cached_vertices;
	mutable PackedInt32Array cached_indices;
	mutable PackedVector3Array cached_normals;
	mutable bool has_cached_result = false;

protected:
	static void _bind_methods();

public:
	static Ref<PolygonTriangulationGodot> create(const PackedVector3Array &p_points, const PackedVector3Array &p_normals = PackedVector3Array());
	static Ref<PolygonTriangulationGodot> create_planar(const PackedVector3Array &p_points, const PackedVector3Array &p_degenerate_points);

	void set_cost_weights(float p_triangle, float p_edge, float p_bi_triangle, float p_triangle_boundary, float p_worst_dihedral);
	void set_optimization_rounds(int p_rounds);
	void set_point_limit(int p_limit);
	void enable_dot_output(bool p_enable);

	bool preprocess();
	bool triangulate();
	void clear_cache();

	PackedVector3Array get_vertices() const;
	PackedInt32Array get_indices() const;
	PackedVector3Array get_normals() const;
	Ref<ArrayMesh> get_mesh(bool p_smooth = false, int p_subdivisions = 0, int p_laplacian_iterations = 0) const;

	int get_triangle_count() const;
	int get_vertex_count() const;
	Dictionary get_statistics() const;
	float get_optimal_cost() const;

	PolygonTriangulationGodot();
	~PolygonTriangulationGodot();
};
