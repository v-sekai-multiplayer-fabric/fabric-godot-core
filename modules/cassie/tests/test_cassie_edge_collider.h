/**************************************************************************/
/*  test_cassie_edge_collider.h                                            */
/**************************************************************************/
/* Tests for CassieEdgeCollider (ENG-55 / Track 4 step 4.3).               */

#pragma once

#include "../src/sketch/cassie_edge_collider.h"
#include "../src/sketch/cassie_surface_patch.h"

#include "core/math/vector3.h"
#include "scene/resources/curve.h"
#include "scene/resources/mesh.h"
#include "tests/test_macros.h"

namespace TestCassieEdgeCollider {

static Ref<ArrayMesh> _build_triangle_mesh(const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c) {
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	PackedVector3Array verts;
	verts.push_back(p_a);
	verts.push_back(p_b);
	verts.push_back(p_c);
	PackedInt32Array idx;
	idx.push_back(0);
	idx.push_back(1);
	idx.push_back(2);
	arrays[Mesh::ARRAY_VERTEX] = verts;
	arrays[Mesh::ARRAY_INDEX] = idx;
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
}

TEST_CASE("[Cassie][EdgeCollider] segment near a mesh edge surfaces a penetration") {
	// Triangle on the XZ plane; mesh edge 0-1 runs from (-1,0,-1) to (1,0,-1).
	// The stroke runs parallel above that edge at y=0.05, well within
	// proximity_threshold = 0.2.
	Ref<CassieSurfacePatch> patch;
	patch.instantiate();
	patch->set_mesh(_build_triangle_mesh(
			Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(0, 0, 1)));

	Ref<Curve3D> stroke;
	stroke.instantiate();
	stroke->add_point(Vector3(real_t(-0.5), real_t(0.05), -1), Vector3(), Vector3());
	stroke->add_point(Vector3(real_t(0.5), real_t(0.05), -1), Vector3(), Vector3());

	Ref<CassieEdgeCollider> collider;
	collider.instantiate();
	collider->set_patch(patch);
	collider->set_proximity_threshold(real_t(0.2));
	collider->set_samples_per_segment(8);

	Array hits = collider->find_penetrations(stroke);
	REQUIRE_MESSAGE(hits.size() > 0,
			vformat("expected ≥ 1 penetration record, got %d", int(hits.size())));
	// Every penetrating sample sits at y=0.05 directly above an edge point
	// at y=0; displacement = stroke - mesh = (0, +, 0). Push points up (+Y).
	bool any_outward = false;
	for (int i = 0; i < hits.size(); ++i) {
		const Dictionary d = hits[i];
		const Vector3 disp = d["displacement"];
		if (disp.y > real_t(0.01)) {
			any_outward = true;
			break;
		}
	}
	CHECK(any_outward);
}

TEST_CASE("[Cassie][EdgeCollider] segment far above the patch reports no penetration") {
	Ref<CassieSurfacePatch> patch;
	patch.instantiate();
	patch->set_mesh(_build_triangle_mesh(
			Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(0, 0, 1)));

	// Stroke parallel to the patch at y = 5, far above threshold = 0.1.
	Ref<Curve3D> stroke;
	stroke.instantiate();
	stroke->add_point(Vector3(-1, 5, 0), Vector3(), Vector3());
	stroke->add_point(Vector3(1, 5, 0), Vector3(), Vector3());

	Ref<CassieEdgeCollider> collider;
	collider.instantiate();
	collider->set_patch(patch);
	collider->set_proximity_threshold(real_t(0.1));

	Array hits = collider->find_penetrations(stroke);
	CHECK_MESSAGE(hits.size() == 0,
			vformat("expected no hits, got %d", int(hits.size())));
}

TEST_CASE("[Cassie][EdgeCollider] null patch + null curve return empty") {
	Ref<CassieEdgeCollider> collider;
	collider.instantiate();
	Array empty1 = collider->find_penetrations(Ref<Curve3D>());
	CHECK_EQ(empty1.size(), 0);

	Ref<CassieSurfacePatch> patch;
	patch.instantiate();
	patch->set_mesh(_build_triangle_mesh(
			Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(0, 0, 1)));
	collider->set_patch(patch);
	Array empty2 = collider->find_penetrations(Ref<Curve3D>());
	CHECK_EQ(empty2.size(), 0);
}

} // namespace TestCassieEdgeCollider
