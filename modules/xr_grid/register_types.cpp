#include "register_types.h"

#include "core/object/class_db.h"

#include "src/xr_grid_base_procedural_grid_3d.h"
#include "src/xr_grid_bool_timer.h"
#include "src/xr_grid_capsule_persona.h"
#include "src/xr_grid_entity_packet.h"
#include "src/xr_grid_fabric_manager.h"
#include "src/xr_grid_fabric_transform_sync.h"
#include "src/xr_grid_flatscreen_controller.h"
#include "src/xr_grid_follow_test.h"
#include "src/xr_grid_gpu_trail_3d.h"
#include "src/xr_grid_hand.h"
#include "src/xr_grid_orientation_orb.h"
#include "src/xr_grid_procedural_grid_3d.h"
#include "src/xr_grid_remote_player.h"
#include "src/xr_grid_remote_player_manager.h"
#include "src/xr_grid_simple_sketch.h"
#include "src/xr_grid_sketch_tool.h"
#include "src/xr_grid_stroke_channel.h"
#include "src/xr_grid_strokes.h"
#include "src/xr_grid_swing_twist_codec.h"
#include "src/xr_grid_vsk_version.h"
#include "src/xr_grid_world_grab.h"
#include "src/xr_grid_xr_origin.h"
#include "src/xr_grid_xr_pinch.h"
#include "src/xr_grid_zone_scene_tree.h"
#include "src/xr_grid_zone_server.h"

void initialize_xr_grid_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<XRGridStrokeChannel>();
	ClassDB::register_class<XRGridBoolTimer>();
	ClassDB::register_class<XRGridSwingTwistCodec>();
	ClassDB::register_class<XRGridEntityPacket>();
	ClassDB::register_class<XRGridVskVersion>();
	ClassDB::register_class<XRGridFabricManager>();
	ClassDB::register_class<XRGridFabricTransformSync>();
	ClassDB::register_class<XRGridOrientationOrb>();
	ClassDB::register_class<XRGridRemotePlayer>();
	ClassDB::register_class<XRGridRemotePlayerManager>();
	ClassDB::register_class<XRGridZoneServer>();
	ClassDB::register_class<XRGridZoneSceneTree>();
	ClassDB::register_class<XRGridWorldGrab>();
	ClassDB::register_class<XRGridXROrigin>();
	ClassDB::register_class<XRGridHand>();
	ClassDB::register_class<XRGridXRPinch>();
	ClassDB::register_class<XRGridFlatscreenController>();
	ClassDB::register_class<XRGridSimpleSketch>();
	ClassDB::register_class<XRGridSketchTool>();
	ClassDB::register_class<XRGridStrokes>();
	ClassDB::register_class<XRGridFollowTest>();
	ClassDB::register_class<XRGridBaseProceduralGrid3D>();
	ClassDB::register_class<XRGridProceduralGrid3D>();
	ClassDB::register_class<XRGridGPUTrail3D>();
	ClassDB::register_class<XRGridCapsulePersona>();
}

void uninitialize_xr_grid_module(ModuleInitializationLevel p_level) {
}
