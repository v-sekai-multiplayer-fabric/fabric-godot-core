/**************************************************************************/
/*  xr_grid_follow_test.h                                                  */
/**************************************************************************/
/* Native port of xr-grid/addons/procedural_3d_grid/core/follow_test.gd.   */
/* Top-level Node3D that smoothly follows its parent's global transform    */
/* via XRGridWorldGrab::split_blend.                                       */

#pragma once

#include "xr_grid_world_grab.h"

#include "scene/3d/node_3d.h"

class XRGridFollowTest : public Node3D {
	GDCLASS(XRGridFollowTest, Node3D);

	Ref<XRGridWorldGrab> world_grab;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridFollowTest();
};
