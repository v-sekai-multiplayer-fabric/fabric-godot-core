/**************************************************************************/
/*  xr_grid_vsk_version.cpp                                                */
/**************************************************************************/

#include "xr_grid_vsk_version.h"

#include "core/object/class_db.h"

String XRGridVskVersion::get_build_label() const {
	return build_date_str + "\n" + build_label;
}

void XRGridVskVersion::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_build_label", "label"),
			&XRGridVskVersion::set_build_label);
	ClassDB::bind_method(D_METHOD("get_build_label_raw"),
			&XRGridVskVersion::get_build_label_raw);
	ClassDB::bind_method(D_METHOD("set_build_date_str", "date"),
			&XRGridVskVersion::set_build_date_str);
	ClassDB::bind_method(D_METHOD("get_build_date_str"),
			&XRGridVskVersion::get_build_date_str);
	ClassDB::bind_method(D_METHOD("set_build_unix_time", "t"),
			&XRGridVskVersion::set_build_unix_time);
	ClassDB::bind_method(D_METHOD("get_build_unix_time"),
			&XRGridVskVersion::get_build_unix_time);
	ClassDB::bind_method(D_METHOD("get_build_label"),
			&XRGridVskVersion::get_build_label);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "build_label"),
			"set_build_label", "get_build_label_raw");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "build_date_str"),
			"set_build_date_str", "get_build_date_str");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "build_unix_time"),
			"set_build_unix_time", "get_build_unix_time");
}
