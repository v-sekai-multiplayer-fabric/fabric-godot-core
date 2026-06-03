/**************************************************************************/
/*  xr_grid_vsk_version.h                                                  */
/**************************************************************************/
/* Native port of xr-grid/addons/vsk_version/vsk_version.gd.               */
/* Returns the build label string the editor UI displays. Without build    */
/* injection the default "DEVELOPER_BUILD\nBuild Date" is returned; the    */
/* setters let a build-time codegen step overwrite the values without      */
/* re-shipping the engine.                                                  */

#pragma once

#include "core/object/ref_counted.h"
#include "core/string/ustring.h"

class XRGridVskVersion : public RefCounted {
	GDCLASS(XRGridVskVersion, RefCounted);

	String build_label = "DEVELOPER_BUILD";
	String build_date_str = "Build Date";
	int64_t build_unix_time = -1;

protected:
	static void _bind_methods();

public:
	XRGridVskVersion() = default;

	void set_build_label(const String &p_label) { build_label = p_label; }
	String get_build_label_raw() const { return build_label; }

	void set_build_date_str(const String &p_date) { build_date_str = p_date; }
	String get_build_date_str() const { return build_date_str; }

	void set_build_unix_time(int64_t p_t) { build_unix_time = p_t; }
	int64_t get_build_unix_time() const { return build_unix_time; }

	// Concatenated "<build_date_str>\n<build_label>" — matches the
	// upstream get_build_label() return shape.
	String get_build_label() const;
};
