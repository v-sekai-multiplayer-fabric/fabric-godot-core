/**************************************************************************/
/*  xr_grid_bool_timer.h                                                   */
/**************************************************************************/
/* Native port of xr-grid/addons/procedural_3d_grid/core/bool_timer.gd.    */
/* Holds a deadline timestamp; `value` is true while the wall clock hasn't */
/* passed the deadline. Used by xr-grid input handlers to debounce / hold  */
/* a transient signal for a few seconds after an event.                    */

#pragma once

#include "core/object/ref_counted.h"

class XRGridBoolTimer : public RefCounted {
	GDCLASS(XRGridBoolTimer, RefCounted);

	uint64_t reset_time_ms = 0;

protected:
	static void _bind_methods();

public:
	XRGridBoolTimer() = default;

	// Sets the deadline to now + time_seconds IF that pushes it later; never
	// shrinks an existing deadline.
	void set_true(double p_time_seconds);

	// Overwrites the deadline to now + time_seconds unconditionally.
	void overwrite(double p_time_seconds);

	// Resets the deadline so `value` reads false until the next set_true.
	void reset();

	// True while now <= deadline.
	bool get_value() const;
};
