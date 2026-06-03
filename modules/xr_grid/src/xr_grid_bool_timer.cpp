/**************************************************************************/
/*  xr_grid_bool_timer.cpp                                                 */
/**************************************************************************/

#include "xr_grid_bool_timer.h"

#include "core/object/class_db.h"
#include "core/os/os.h"

void XRGridBoolTimer::set_true(double p_time_seconds) {
	const uint64_t now = OS::get_singleton()->get_ticks_msec();
	const uint64_t candidate = now + uint64_t(p_time_seconds * 1000.0);
	if (candidate > reset_time_ms) {
		reset_time_ms = candidate;
	}
}

void XRGridBoolTimer::overwrite(double p_time_seconds) {
	const uint64_t now = OS::get_singleton()->get_ticks_msec();
	reset_time_ms = now + uint64_t(p_time_seconds * 1000.0);
}

void XRGridBoolTimer::reset() {
	const uint64_t now = OS::get_singleton()->get_ticks_msec();
	// Push deadline one ms into the past so get_value returns false.
	reset_time_ms = (now > 0) ? (now - 1) : uint64_t(0);
}

bool XRGridBoolTimer::get_value() const {
	const uint64_t now = OS::get_singleton()->get_ticks_msec();
	return now <= reset_time_ms;
}

void XRGridBoolTimer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_true", "time_seconds"), &XRGridBoolTimer::set_true);
	ClassDB::bind_method(D_METHOD("overwrite", "time_seconds"), &XRGridBoolTimer::overwrite);
	ClassDB::bind_method(D_METHOD("reset"), &XRGridBoolTimer::reset);
	ClassDB::bind_method(D_METHOD("get_value"), &XRGridBoolTimer::get_value);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "value"), "", "get_value");
}
