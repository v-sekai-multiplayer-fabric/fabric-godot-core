/**************************************************************************/
/*  xr_grid_xr_origin.h                                                    */
/**************************************************************************/
/* Native port of xr-grid/addons/procedural_3d_grid/core/xr_origin.gd.     */
/* Node3D that initializes OpenXR + the active viewport's `use_xr` and     */
/* optionally calls connect_to_zone on a discovered XRGridFabricManager.   */

#pragma once

#include "scene/3d/node_3d.h"
#include "servers/xr/xr_interface.h"

class XRGridXROrigin : public Node3D {
	GDCLASS(XRGridXROrigin, Node3D);

	Ref<XRInterface> interface;
	bool vr_supported = false;
	String fabric_address = "127.0.0.1";
	int fabric_port = 9000;
	NodePath fabric_manager_path;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	XRGridXROrigin() = default;

	void set_fabric_address(const String &p_address) { fabric_address = p_address; }
	String get_fabric_address() const { return fabric_address; }
	void set_fabric_port(int p_port) { fabric_port = p_port; }
	int get_fabric_port() const { return fabric_port; }
	void set_fabric_manager_path(const NodePath &p_path) { fabric_manager_path = p_path; }
	NodePath get_fabric_manager_path() const { return fabric_manager_path; }

	bool is_vr_supported() const { return vr_supported; }
};
