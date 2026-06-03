#include "cassie_curvenet_knot.h"

#include "core/object/class_db.h"

void CassieCurvenetKnot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_graph_node_id", "id"), &CassieCurvenetKnot::set_graph_node_id);
	ClassDB::bind_method(D_METHOD("get_graph_node_id"), &CassieCurvenetKnot::get_graph_node_id);
	ClassDB::bind_method(D_METHOD("set_projection_pose_transform", "transform"),
			&CassieCurvenetKnot::set_projection_pose_transform);
	ClassDB::bind_method(D_METHOD("get_projection_pose_transform"),
			&CassieCurvenetKnot::get_projection_pose_transform);
	ClassDB::bind_method(D_METHOD("set_rest_pose_transform", "transform"),
			&CassieCurvenetKnot::set_rest_pose_transform);
	ClassDB::bind_method(D_METHOD("get_rest_pose_transform"),
			&CassieCurvenetKnot::get_rest_pose_transform);
	ClassDB::bind_method(D_METHOD("set_is_intersection", "value"),
			&CassieCurvenetKnot::set_is_intersection);
	ClassDB::bind_method(D_METHOD("get_is_intersection"),
			&CassieCurvenetKnot::get_is_intersection);
	ClassDB::bind_method(D_METHOD("set_projection_pose_tangents", "tangents"),
			&CassieCurvenetKnot::set_projection_pose_tangents);
	ClassDB::bind_method(D_METHOD("get_projection_pose_tangents"),
			&CassieCurvenetKnot::get_projection_pose_tangents);
	ClassDB::bind_method(D_METHOD("set_rest_pose_tangents", "tangents"),
			&CassieCurvenetKnot::set_rest_pose_tangents);
	ClassDB::bind_method(D_METHOD("get_rest_pose_tangents"),
			&CassieCurvenetKnot::get_rest_pose_tangents);
	ClassDB::bind_method(D_METHOD("set_exposes_translate", "value"),
			&CassieCurvenetKnot::set_exposes_translate);
	ClassDB::bind_method(D_METHOD("get_exposes_translate"),
			&CassieCurvenetKnot::get_exposes_translate);
	ClassDB::bind_method(D_METHOD("set_exposes_rotate", "value"),
			&CassieCurvenetKnot::set_exposes_rotate);
	ClassDB::bind_method(D_METHOD("get_exposes_rotate"),
			&CassieCurvenetKnot::get_exposes_rotate);
	ClassDB::bind_method(D_METHOD("set_exposes_scale", "value"),
			&CassieCurvenetKnot::set_exposes_scale);
	ClassDB::bind_method(D_METHOD("get_exposes_scale"),
			&CassieCurvenetKnot::get_exposes_scale);
	ClassDB::bind_method(D_METHOD("set_needs_setup", "value"),
			&CassieCurvenetKnot::set_needs_setup);
	ClassDB::bind_method(D_METHOD("get_needs_setup"),
			&CassieCurvenetKnot::get_needs_setup);
	ClassDB::bind_method(D_METHOD("solve_world_transform"),
			&CassieCurvenetKnot::solve_world_transform);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "graph_node_id"),
			"set_graph_node_id", "get_graph_node_id");
	ADD_PROPERTY(PropertyInfo(Variant::TRANSFORM3D, "projection_pose_transform"),
			"set_projection_pose_transform", "get_projection_pose_transform");
	ADD_PROPERTY(PropertyInfo(Variant::TRANSFORM3D, "rest_pose_transform"),
			"set_rest_pose_transform", "get_rest_pose_transform");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_intersection"),
			"set_is_intersection", "get_is_intersection");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "exposes_translate"),
			"set_exposes_translate", "get_exposes_translate");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "exposes_rotate"),
			"set_exposes_rotate", "get_exposes_rotate");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "exposes_scale"),
			"set_exposes_scale", "get_exposes_scale");
}
