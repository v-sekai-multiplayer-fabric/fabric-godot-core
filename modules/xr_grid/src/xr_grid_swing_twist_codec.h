/**************************************************************************/
/*  xr_grid_swing_twist_codec.h                                            */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/fabric/swing_twist_codec.gd.     */
/*                                                                         */
/* Quaternion ↔ swing-twist Vector3 codec plus i16 quantization for the   */
/* fabric entity packet's 6-byte rotation slot. Twist about local X,       */
/* swing in the local YZ plane. Quantization clamps each axis to ±π and    */
/* scales to ±32767 — round-trip error is ~0.005 rad worst case.          */

#pragma once

#include "core/math/quaternion.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

class XRGridSwingTwistCodec : public RefCounted {
	GDCLASS(XRGridSwingTwistCodec, RefCounted);

protected:
	static void _bind_methods();

public:
	XRGridSwingTwistCodec() = default;

	static constexpr double QUANTIZE_SCALE = 32767.0;

	// vec is interpreted as (twist_x_radians, swing_y_radians, swing_z_radians).
	static Quaternion swing_twist_to_quat(const Vector3 &p_vec);
	static Vector3 quat_to_swing_twist(const Quaternion &p_q);

	// Returns [twist_x_i16, swing_y_i16, swing_z_i16] as ints in [-32767, 32767].
	static PackedInt32Array encode_rotation_i16(const Quaternion &p_q);

	static Quaternion decode_rotation_i16(int p_twist_x_i16,
			int p_swing_y_i16, int p_swing_z_i16);
};
