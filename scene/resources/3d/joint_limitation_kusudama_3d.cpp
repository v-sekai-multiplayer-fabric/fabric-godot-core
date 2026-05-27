/**************************************************************************/
/*  joint_limitation_kusudama_3d.cpp                                      */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "joint_limitation_kusudama_3d.h"

#include "core/object/class_db.h"

#ifdef TOOLS_ENABLED
#include "scene/resources/3d/kusudama_gizmo_shader.h"
#include "scene/resources/surface_tool.h"
#endif

void JointLimitationKusudama3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cones", "cones"), &JointLimitationKusudama3D::set_cones);
	ClassDB::bind_method(D_METHOD("get_cones"), &JointLimitationKusudama3D::get_cones);

	ClassDB::bind_method(D_METHOD("set_cone_count", "count"), &JointLimitationKusudama3D::set_cone_count);
	ClassDB::bind_method(D_METHOD("get_cone_count"), &JointLimitationKusudama3D::get_cone_count);
	ClassDB::bind_method(D_METHOD("set_cone_center", "index", "center"), &JointLimitationKusudama3D::set_cone_center);
	ClassDB::bind_method(D_METHOD("get_cone_center", "index"), &JointLimitationKusudama3D::get_cone_center);
	ClassDB::bind_method(D_METHOD("set_cone_radius", "index", "radius"), &JointLimitationKusudama3D::set_cone_radius);
	ClassDB::bind_method(D_METHOD("get_cone_radius", "index"), &JointLimitationKusudama3D::get_cone_radius);

	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "cones", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_cones", "get_cones");
}

void JointLimitationKusudama3D::set_cones(const Vector<Vector4> &p_cones) {
	cones.clear();
	int n = MIN((int)p_cones.size(), MAX_KUSUDAMA_CONES);
	for (int i = 0; i < n; i++) {
		cones.push_back(p_cones[i]);
	}
	_invalidate_normalized_cache();
	_invalidate_polygon_cache();
	emit_changed();
}

Vector<Vector4> JointLimitationKusudama3D::get_cones() const {
	Vector<Vector4> r;
	r.resize(cones.size());
	for (uint32_t i = 0; i < cones.size(); i++) {
		r.write[i] = cones[i];
	}
	return r;
}

void JointLimitationKusudama3D::set_cone_count(int p_count) {
	if (p_count < 0) {
		p_count = 0;
	}
	if (p_count > MAX_KUSUDAMA_CONES) {
		p_count = MAX_KUSUDAMA_CONES;
	}
	uint32_t old_size = cones.size();
	if (old_size == (uint32_t)p_count) {
		return;
	}
	cones.resize(p_count);
	for (uint32_t i = old_size; i < cones.size(); i++) {
		cones[i] = Vector4(0, 1, 0, Math::PI * 0.25);
	}
	_invalidate_normalized_cache();
	_invalidate_polygon_cache();
	notify_property_list_changed();
	emit_changed();
}

int JointLimitationKusudama3D::get_cone_count() const {
	return cones.size();
}

void JointLimitationKusudama3D::set_cone_center(int p_index, const Vector3 &p_center) {
	ERR_FAIL_INDEX(p_index, (int)cones.size());
	Vector4 &cone = cones[p_index];
	cone.x = p_center.x;
	cone.y = p_center.y;
	cone.z = p_center.z;
	_invalidate_normalized_cache();
	_invalidate_polygon_cache();
	emit_changed();
}

Vector3 JointLimitationKusudama3D::get_cone_center(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, (int)cones.size(), Vector3::UP);
	const Vector4 &cone_data = cones[p_index];
	return Vector3(cone_data.x, cone_data.y, cone_data.z);
}

void JointLimitationKusudama3D::_invalidate_normalized_cache() const {
	_normalized_cone_centers_cache.clear();
}

void JointLimitationKusudama3D::_invalidate_polygon_cache() const {
	_polygon_dirty = true;
}

Vector3 JointLimitationKusudama3D::_get_cone_center_normalized(int p_index) const {
	if (_normalized_cone_centers_cache.size() != cones.size()) {
		_normalized_cone_centers_cache.resize(cones.size());
		for (uint32_t i = 0; i < cones.size(); i++) {
			Vector3 raw(cones[i].x, cones[i].y, cones[i].z);
			if (raw.is_zero_approx()) {
				_normalized_cone_centers_cache[i] = Vector3::UP;
			} else {
				_normalized_cone_centers_cache[i] = raw.normalized();
			}
		}
	}
	ERR_FAIL_INDEX_V(p_index, (int)_normalized_cone_centers_cache.size(), Vector3::UP);
	return _normalized_cone_centers_cache[p_index];
}

void JointLimitationKusudama3D::set_cone_radius(int p_index, real_t p_radius) {
	ERR_FAIL_INDEX(p_index, (int)cones.size());
	cones[p_index].w = p_radius;
	_invalidate_polygon_cache();
	emit_changed();
}

real_t JointLimitationKusudama3D::get_cone_radius(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, (int)cones.size(), 0.0);
	return cones[p_index].w;
}

bool JointLimitationKusudama3D::_set(const StringName &p_name, const Variant &p_value) {
	String prop_name = p_name;
	if (prop_name == "cone_count") {
		set_cone_count(p_value);
		return true;
	}
	if (prop_name.begins_with("cones/")) {
		int index = prop_name.get_slicec('/', 1).to_int();
		String what = prop_name.get_slicec('/', 2);
		if (what == "center") {
			set_cone_center(index, p_value);
			return true;
		}
		if (what == "radius") {
			set_cone_radius(index, p_value);
			return true;
		}
	}
	return false;
}

bool JointLimitationKusudama3D::_get(const StringName &p_name, Variant &r_ret) const {
	String prop_name = p_name;
	if (prop_name == "cone_count") {
		r_ret = get_cone_count();
		return true;
	}
	if (prop_name.begins_with("cones/")) {
		int index = prop_name.get_slicec('/', 1).to_int();
		String what = prop_name.get_slicec('/', 2);
		if (what == "center") {
			r_ret = get_cone_center(index);
			return true;
		}
		if (what == "radius") {
			r_ret = get_cone_radius(index);
			return true;
		}
	}
	return false;
}

void JointLimitationKusudama3D::_get_property_list(List<PropertyInfo> *p_list) const {
	p_list->push_back(PropertyInfo(Variant::INT, PNAME("cone_count"), PROPERTY_HINT_RANGE, "0,30,1", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_ARRAY, "Cones," + String(PNAME("cones")) + "/"));
	for (int i = 0; i < get_cone_count(); i++) {
		const String prefix = vformat("%s/%d/", PNAME("cones"), i);
		p_list->push_back(PropertyInfo(Variant::VECTOR3, prefix + PNAME("center"), PROPERTY_HINT_NONE, ""));
		p_list->push_back(PropertyInfo(Variant::FLOAT, prefix + PNAME("radius"), PROPERTY_HINT_RANGE, "1,180,0.1,radians_as_degrees"));
	}
}


void JointLimitationKusudama3D::_compute_hull_order() const {
	uint32_t n = cones.size();
	_hull_order.resize(n);
	for (uint32_t i = 0; i < n; i++) {
		_hull_order[i] = i;
	}
	if (n <= 2) {
		return;
	}
	// Sort by angle around a reference axis derived from the first two cones.
	// This avoids centroid computation (which degenerates with equidistant cones).
	Vector3 ref = _get_cone_center_normalized(0).cross(_get_cone_center_normalized(1));
	if (ref.is_zero_approx()) {
		ref = _get_cone_center_normalized(0).get_any_perpendicular();
	}
	ref.normalize();
	Vector3 u = ref.get_any_perpendicular().normalized();
	Vector3 v = ref.cross(u).normalized();

	LocalVector<real_t> angles;
	angles.resize(n);
	for (uint32_t i = 0; i < n; i++) {
		Vector3 c = _get_cone_center_normalized(i);
		angles[i] = Math::atan2(c.dot(v), c.dot(u));
	}
	for (uint32_t i = 1; i < n; i++) {
		uint32_t key_idx = _hull_order[i];
		real_t key_angle = angles[key_idx];
		int j = (int)i - 1;
		while (j >= 0 && angles[_hull_order[j]] > key_angle) {
			_hull_order[j + 1] = _hull_order[j];
			j--;
		}
		_hull_order[j + 1] = key_idx;
	}
}

void JointLimitationKusudama3D::_rebuild_polygon_cache() const {
	if (!_polygon_dirty) {
		return;
	}
	_polygon_dirty = false;
	_polygon_vertices.clear();
	_polygon_normals.clear();
	_tangent_centers_1.clear();
	_tangent_centers_2.clear();
	_tangent_radii.clear();

	uint32_t n = cones.size();
	if (n < 2) {
		return;
	}

	_compute_hull_order();

	// Compute tangent circles for each adjacent pair in hull order (closed loop).
	_tangent_centers_1.resize(n);
	_tangent_centers_2.resize(n);
	_tangent_radii.resize(n);
	for (uint32_t i = 0; i < n; i++) {
		uint32_t idx_a = _hull_order[i];
		uint32_t idx_b = _hull_order[(i + 1) % n];
		compute_tangent_circles(
				_get_cone_center_normalized(idx_a), cones[idx_a].w,
				_get_cone_center_normalized(idx_b), cones[idx_b].w,
				_tangent_centers_1[i], _tangent_centers_2[i], _tangent_radii[i]);
	}

	// Polygon vertices = cone centers in hull order.
	_polygon_vertices.resize(n);
	for (uint32_t i = 0; i < n; i++) {
		_polygon_vertices[i] = _get_cone_center_normalized(_hull_order[i]);
	}

	// Edge normals.
	_polygon_normals.resize(n);
	for (uint32_t i = 0; i < n; i++) {
		Vector3 edge_normal = _polygon_vertices[i].cross(_polygon_vertices[(i + 1) % n]);
		if (edge_normal.is_zero_approx()) {
			edge_normal = _polygon_vertices[i].get_any_perpendicular();
		}
		_polygon_normals[i] = edge_normal.normalized();
	}

	// Orientation check via winding sum: the sum of cross products gives the
	// polygon's area-normal.  If it points opposite to the sum of vertices
	// (the "outward" direction), normals face the wrong way — flip them.
	Vector3 winding_sum;
	Vector3 vertex_sum;
	for (uint32_t i = 0; i < n; i++) {
		winding_sum += _polygon_vertices[i].cross(_polygon_vertices[(i + 1) % n]);
		vertex_sum += _polygon_vertices[i];
	}
	if (winding_sum.dot(vertex_sum) < 0) {
		for (uint32_t i = 0; i < n; i++) {
			_polygon_normals[i] = -_polygon_normals[i];
		}
	}
}

bool JointLimitationKusudama3D::_is_in_tangent_path(const Vector3 &p_point, uint32_t p_pair_index) const {
	uint32_t n = _hull_order.size();
	uint32_t idx_a = _hull_order[p_pair_index];
	uint32_t idx_b = _hull_order[(p_pair_index + 1) % n];
	Vector3 center1 = _get_cone_center_normalized(idx_a);
	Vector3 center2 = _get_cone_center_normalized(idx_b);
	Vector3 tan1 = _tangent_centers_1[p_pair_index];
	Vector3 tan2 = _tangent_centers_2[p_pair_index];
	real_t tan_radius_cos = Math::cos(_tangent_radii[p_pair_index]);

	// Inside a tangent circle = forbidden.
	if (p_point.dot(tan1) > tan_radius_cos) {
		return false;
	}
	if (p_point.dot(tan2) > tan_radius_cos) {
		return false;
	}

	// Check which side of the arc (center1 × center2) we're on, then verify
	// the point is inside the tangent triangle on that side.
	Vector3 arc_normal = center1.cross(center2);
	real_t side = p_point.dot(arc_normal);

	if (side < 0.0) {
		return p_point.dot(center1.cross(tan1)) > 0 && p_point.dot(tan1.cross(center2)) > 0;
	} else {
		return p_point.dot(tan2.cross(center1)) > 0 && p_point.dot(center2.cross(tan2)) > 0;
	}
}

bool JointLimitationKusudama3D::_polygon_contains(const Vector3 &p_point) const {
	uint32_t m = _polygon_normals.size();
	for (uint32_t i = 0; i < m; i++) {
		if (p_point.dot(_polygon_normals[i]) < 0) {
			return false;
		}
	}
	return true;
}

Vector3 JointLimitationKusudama3D::_polygon_project(const Vector3 &p_point) const {
	real_t best_dot = -2.0f;
	Vector3 best = p_point;
	uint32_t n = _polygon_vertices.size();

	// Project onto each polygon edge (great circle arc between consecutive vertices).
	for (uint32_t i = 0; i < n; i++) {
		Vector3 v0 = _polygon_vertices[i];
		Vector3 v1 = _polygon_vertices[(i + 1) % n];
		Vector3 arc_normal = v0.cross(v1);
		if (arc_normal.is_zero_approx()) {
			continue;
		}
		arc_normal.normalize();

		Vector3 proj = (p_point - arc_normal * p_point.dot(arc_normal));
		if (proj.is_zero_approx()) {
			continue;
		}
		proj.normalize();

		Vector3 edge_dir = v0.cross(v1);
		real_t d0 = v0.cross(proj).dot(edge_dir);
		real_t d1 = proj.cross(v1).dot(edge_dir);

		Vector3 candidate;
		if (d0 >= 0 && d1 >= 0) {
			candidate = proj;
		} else {
			real_t dot0 = p_point.dot(v0);
			real_t dot1 = p_point.dot(v1);
			candidate = (dot0 >= dot1) ? v0 : v1;
		}

		real_t d = p_point.dot(candidate);
		if (d > best_dot) {
			best_dot = d;
			best = candidate;
		}
	}

	return best;
}

Vector3 JointLimitationKusudama3D::_solve(const Vector3 &p_direction) const {
	Vector3 p = p_direction.normalized();
	uint32_t n = cones.size();
	if (n == 0) {
		return p;
	}

	// Fast accept: point inside any cone.
	for (uint32_t i = 0; i < n; i++) {
		if (is_point_in_cone(p, _get_cone_center_normalized(i), cones[i].w)) {
			return p;
		}
	}

	if (n == 1) {
		Vector3 c = _get_cone_center_normalized(0);
		real_t r = cones[0].w;
		Vector3 ortho = (p - p.project(c)).normalized();
		if (!ortho.is_finite()) {
			ortho = (Math::abs(c.z) < 0.9f) ? c.cross(Vector3(0, 0, 1)).normalized() : c.cross(Vector3(1, 0, 0)).normalized();
		}
		return c * Math::cos(r) + ortho * Math::sin(r);
	}

	// Multiple cones: rebuild cache, then check tangent paths (closed loop).
	_rebuild_polygon_cache();

	for (uint32_t i = 0; i < n; i++) {
		if (_is_in_tangent_path(p, i)) {
			return p;
		}
	}

	// Also accept if inside the convex polygon (covers small gaps between
	// tangent paths that arise from the polygon being slightly larger than the
	// union of tangent triangles).
	if (_polygon_contains(p)) {
		return p;
	}

	// Outside all allowed regions — project to nearest boundary (flicker-free).
	return _polygon_project(p);
}

// Helper functions for kusudama solving

#ifdef TOOLS_ENABLED

int JointLimitationKusudama3D::get_cone_sequence_for_shader(PackedVector4Array &r_cone_sequence) const {
	r_cone_sequence.clear();
	uint32_t n = cones.size();
	if (n == 0) {
		return 0;
	}
	// Rebuild polygon cache to get hull order.
	_rebuild_polygon_cache();
	uint32_t hull_n = _hull_order.size();
	if (hull_n == 0) {
		hull_n = n;
	}
	// Layout: cone0, tangent0_1, tangent0_2, cone1, tangent1_1, tangent1_2, ..., tangentN_1, tangentN_2, cone0 (wrap)
	// Use hull order for closed loop.
	for (uint32_t i = 0; i < hull_n; i++) {
		uint32_t idx = (hull_n > 0 && _hull_order.size() == hull_n) ? _hull_order[i] : i;
		Vector3 center_i = _get_cone_center_normalized(idx);
		real_t radius_i = cones[idx].w;
		if (i == 0) {
			r_cone_sequence.push_back(Vector4(center_i.x, center_i.y, center_i.z, radius_i));
		}
		uint32_t idx_next = (hull_n > 0 && _hull_order.size() == hull_n) ? _hull_order[(i + 1) % hull_n] : (i + 1) % n;
		Vector3 center_next = _get_cone_center_normalized(idx_next);
		real_t radius_next = cones[idx_next].w;
		Vector3 tan1, tan2;
		real_t trad;
		compute_tangent_circles(center_i, radius_i, center_next, radius_next, tan1, tan2, trad);
		r_cone_sequence.push_back(Vector4(tan1.x, tan1.y, tan1.z, trad));
		r_cone_sequence.push_back(Vector4(tan2.x, tan2.y, tan2.z, trad));
		r_cone_sequence.push_back(Vector4(center_next.x, center_next.y, center_next.z, radius_next));
	}
	return n;
}

void JointLimitationKusudama3D::get_kusudama_fill_mesh_and_material(const Transform3D &p_transform, float p_bone_length, const Color &p_color, int p_bone_index, Transform3D &r_mesh_to_skeleton_rest, Ref<ArrayMesh> &r_mesh, Ref<Material> &r_material) const {
	r_mesh.unref();
	r_material.unref();
	PackedVector4Array cone_sequence;
	int cone_count = get_cone_sequence_for_shader(cone_sequence);
	if (cone_count <= 0) {
		return;
	}
	real_t sphere_r = p_bone_length * (real_t)0.25;
	const int rings = 16;
	const int radial_segments = 16;
	Vector<Vector3> points;
	Vector<Vector3> normals;
	Vector<int> indices;
	int thisrow = 0;
	int prevrow = 0;
	int point = 0;
	for (int j = 0; j <= (rings + 1); j++) {
		float v = (float)j / (float)(rings + 1);
		float w = Math::sin(Math::PI * v);
		float y = Math::cos(Math::PI * v);
		for (int i = 0; i <= radial_segments; i++) {
			float u = (float)i / (float)radial_segments;
			float x = Math::sin(u * Math::TAU);
			float z = Math::cos(u * Math::TAU);
			Vector3 p = Vector3(x * w, y, z * w);
			points.push_back(p.normalized());
			normals.push_back(p.normalized());
			point++;
			if (i > 0 && j > 0) {
				indices.push_back(prevrow + i - 1);
				indices.push_back(prevrow + i);
				indices.push_back(thisrow + i - 1);
				indices.push_back(prevrow + i);
				indices.push_back(thisrow + i);
				indices.push_back(thisrow + i - 1);
			}
		}
		prevrow = thisrow;
		thisrow = point;
	}
	if (indices.is_empty()) {
		return;
	}
	const bool use_skin = (p_bone_index >= 0);
	Ref<SurfaceTool> st;
	st.instantiate();
	st->begin(Mesh::PRIMITIVE_TRIANGLES);
	st->set_custom_format(0, SurfaceTool::CUSTOM_RGBA_HALF);
	if (use_skin) {
		PackedInt32Array bones;
		PackedFloat32Array weights;
		bones.resize(Mesh::ARRAY_WEIGHTS_SIZE);
		weights.resize(Mesh::ARRAY_WEIGHTS_SIZE);
		for (int k = 0; k < Mesh::ARRAY_WEIGHTS_SIZE; k++) {
			bones.write[k] = (k == 0) ? p_bone_index : 0;
			weights.write[k] = (k == 0) ? 1.0f : 0.0f;
		}
		st->set_bones(bones);
		st->set_weights(weights);
	}
	for (int idx = 0; idx < points.size(); idx++) {
		Vector3 n = normals[idx];
		Vector3 pos = points[idx];
		if (use_skin) {
			// Vertices must be in skeleton global rest space for Godot's skin (bind = inverse bone rest).
			pos = p_transform.xform(pos * sphere_r);
			n = p_transform.basis.xform(n).normalized();
		}
		Color c;
		c.r = n.x;
		c.g = n.y;
		c.b = n.z;
		c.a = 0.0f;
		st->set_custom(0, c);
		st->set_normal(n);
		st->add_vertex(pos);
	}
	for (int idx : indices) {
		st->add_index(idx);
	}
	r_mesh = st->commit();

	Ref<Shader> sh;
	sh.instantiate();
	sh->set_code(KUSUDAMA_GIZMO_SHADER);
	Ref<ShaderMaterial> mat;
	mat.instantiate();
	mat->set_shader(sh);
	Color boundary_color;
	boundary_color.set_ok_hsl(
			p_color.get_ok_hsl_h(),
			p_color.get_ok_hsl_s(),
			CLAMP((float)p_color.get_ok_hsl_l() - 0.25f, 0.0f, 1.0f),
			p_color.a);

	mat->set_shader_parameter("cone_count", cone_count);
	mat->set_shader_parameter("cone_sequence", cone_sequence);
	mat->set_shader_parameter("kusudama_color", p_color);
	mat->set_shader_parameter("boundary_outline_color", boundary_color);
	r_material = mat;

	if (use_skin) {
		r_mesh_to_skeleton_rest = Transform3D();
	} else {
		r_mesh_to_skeleton_rest = p_transform;
		r_mesh_to_skeleton_rest.basis.scale(Vector3(sphere_r, sphere_r, sphere_r));
	}
}

void JointLimitationKusudama3D::append_extra_gizmo_meshes(const Transform3D &p_transform, float p_bone_length, const Color &p_color, Vector<ExtraMeshEntry> &r_extra_meshes, int p_bone_index) const {
	ExtraMeshEntry e;
	get_kusudama_fill_mesh_and_material(p_transform, p_bone_length, p_color, p_bone_index, e.transform, e.mesh, e.material);
	if (e.mesh.is_valid()) {
		r_extra_meshes.push_back(e);
	}
}
#endif // TOOLS_ENABLED

// Helper function implementations
bool JointLimitationKusudama3D::is_point_in_cone(const Vector3 &p_point, const Vector3 &p_cone_center, real_t p_cone_radius) const {
	if (p_point.is_zero_approx()) {
		return false;
	}
	return p_point.normalized().angle_to(p_cone_center) <= p_cone_radius;
}

void JointLimitationKusudama3D::extend_ray(Vector3 &r_start, Vector3 &r_end, real_t p_amount) const {
	Vector3 mid_point = r_start.lerp(r_end, (real_t)0.5);
	r_start += mid_point.direction_to(r_start) * p_amount;
	r_end += mid_point.direction_to(r_end) * p_amount;
}

int JointLimitationKusudama3D::ray_sphere_intersection_full(const Vector3 &p_ray_start, const Vector3 &p_ray_end, const Vector3 &p_sphere_center, real_t p_radius, Vector3 *r_intersection1, Vector3 *r_intersection2) const {
	Vector3 ray_start_rel = p_ray_start - p_sphere_center;
	Vector3 ray_end_rel = p_ray_end - p_sphere_center;
	Vector3 ray_dir_normalized = ray_start_rel.direction_to(ray_end_rel);
	Vector3 ray_to_center = -ray_start_rel;
	real_t ray_dot_center = ray_dir_normalized.dot(ray_to_center);
	real_t radius_squared = p_radius * p_radius;
	real_t center_dist_squared = ray_to_center.length_squared();
	real_t ray_dot_squared = ray_dot_center * ray_dot_center;
	real_t discriminant = radius_squared - center_dist_squared + ray_dot_squared;

	if (discriminant < 0.0) {
		return 0; // No intersection
	}

	real_t sqrt_discriminant = Math::sqrt(discriminant);
	real_t t1 = ray_dot_center - sqrt_discriminant;
	real_t t2 = ray_dot_center + sqrt_discriminant;

	if (r_intersection1) {
		*r_intersection1 = p_ray_start + ray_dir_normalized * t1;
	}
	if (r_intersection2) {
		*r_intersection2 = p_ray_start + ray_dir_normalized * t2;
	}

	return discriminant > 0.0 ? 2 : 1; // Two intersections or one (tangent)
}

void JointLimitationKusudama3D::compute_tangent_circles(const Vector3 &p_center1, real_t p_radius1, const Vector3 &p_center2, real_t p_radius2, Vector3 &r_tangent1, Vector3 &r_tangent2, real_t &r_tangent_radius) const {
	Vector3 center1 = p_center1.normalized();
	Vector3 center2 = p_center2.normalized();

	// Compute tangent circle radius
	r_tangent_radius = (Math::PI - (p_radius1 + p_radius2)) / 2.0;

	// Find arc normal (axis perpendicular to both cone centers)
	Vector3 arc_normal = center1.cross(center2);
	real_t arc_normal_len = arc_normal.length();

	if (Math::is_zero_approx(arc_normal_len)) {
		// Cones are parallel or opposite - handle specially
		arc_normal = center1.get_any_perpendicular();
		if (arc_normal.is_zero_approx()) {
			arc_normal = Vector3::UP;
		}
		arc_normal.normalize();

		// For opposite cones, tangent circles are at 90 degrees from the cone centers
		Vector3 perp1 = center1.get_any_perpendicular().normalized();

		// Rotate around center1 by the tangent radius to get tangent centers
		Quaternion rot1 = Quaternion(center1, r_tangent_radius);
		Quaternion rot2 = Quaternion(center1, -r_tangent_radius);
		r_tangent1 = rot1.xform(perp1).normalized();
		r_tangent2 = rot2.xform(perp1).normalized();
		return;
	}
	arc_normal.normalize();

	// Use plane intersection method
	real_t boundary_plus_tangent_radius_a = p_radius1 + r_tangent_radius;
	real_t boundary_plus_tangent_radius_b = p_radius2 + r_tangent_radius;

	// The axis of this cone, scaled to minimize its distance to the tangent contact points
	Vector3 scaled_axis_a = center1 * Math::cos(boundary_plus_tangent_radius_a);
	// A point on the plane running through the tangent contact points
	Vector3 safe_arc_normal = arc_normal;
	if (Math::is_zero_approx(safe_arc_normal.length_squared())) {
		safe_arc_normal = Vector3::UP;
	}
	Quaternion temp_var = Quaternion(safe_arc_normal.normalized(), boundary_plus_tangent_radius_a);
	Vector3 plane_dir1_a = temp_var.xform(center1);
	// Another point on the same plane
	Vector3 safe_center1 = center1;
	if (Math::is_zero_approx(safe_center1.length_squared())) {
		safe_center1 = Vector3::BACK;
	}
	Quaternion temp_var2 = Quaternion(safe_center1.normalized(), Math::PI / 2);
	Vector3 plane_dir2_a = temp_var2.xform(plane_dir1_a);

	Vector3 scaled_axis_b = center2 * Math::cos(boundary_plus_tangent_radius_b);
	// A point on the plane running through the tangent contact points
	Quaternion temp_var3 = Quaternion(safe_arc_normal.normalized(), boundary_plus_tangent_radius_b);
	Vector3 plane_dir1_b = temp_var3.xform(center2);
	// Another point on the same plane
	Vector3 safe_center2 = center2;
	if (Math::is_zero_approx(safe_center2.length_squared())) {
		safe_center2 = Vector3::BACK;
	}
	Quaternion temp_var4 = Quaternion(safe_center2.normalized(), Math::PI / 2);
	Vector3 plane_dir2_b = temp_var4.xform(plane_dir1_b);

	// Ray from scaled center of next cone to half way point between the circumference of this cone and the next cone
	Vector3 ray1_b_start = plane_dir1_b;
	Vector3 ray1_b_end = scaled_axis_b;
	Vector3 ray2_b_start = plane_dir1_b;
	Vector3 ray2_b_end = plane_dir2_b;

	extend_ray(ray1_b_start, ray1_b_end, 99.0);
	extend_ray(ray2_b_start, ray2_b_end, 99.0);

	Plane plane_ta(scaled_axis_a, plane_dir1_a, plane_dir2_a);
	Vector3 intersection1;
	Vector3 intersection2;
	if (!plane_ta.intersects_ray(ray1_b_start, ray1_b_start.direction_to(ray1_b_end), &intersection1)) {
		intersection1 = Vector3(NAN, NAN, NAN);
	}
	if (!plane_ta.intersects_ray(ray2_b_start, ray2_b_start.direction_to(ray2_b_end), &intersection2)) {
		intersection2 = Vector3(NAN, NAN, NAN);
	}

	Vector3 intersection_ray_start = intersection1;
	Vector3 intersection_ray_end = intersection2;
	extend_ray(intersection_ray_start, intersection_ray_end, 99.0);

	Vector3 sphere_intersect1;
	Vector3 sphere_intersect2;
	ray_sphere_intersection_full(intersection_ray_start, intersection_ray_end, Vector3(), 1.0, &sphere_intersect1, &sphere_intersect2);

	r_tangent1 = sphere_intersect1.normalized();
	r_tangent2 = sphere_intersect2.normalized();

	// Handle degenerate tangent centers (NaN or zero)
	if (!r_tangent1.is_finite() || Math::is_zero_approx(r_tangent1.length_squared())) {
		r_tangent1 = center1.get_any_perpendicular();
		if (Math::is_zero_approx(r_tangent1.length_squared())) {
			r_tangent1 = Vector3::UP;
		}
		r_tangent1.normalize();
	}
	if (!r_tangent2.is_finite() || Math::is_zero_approx(r_tangent2.length_squared())) {
		Vector3 orthogonal_base = r_tangent1.is_finite() ? r_tangent1 : center1;
		r_tangent2 = orthogonal_base.get_any_perpendicular();
		if (Math::is_zero_approx(r_tangent2.length_squared())) {
			r_tangent2 = Vector3::RIGHT;
		}
		r_tangent2.normalize();
	}
}
