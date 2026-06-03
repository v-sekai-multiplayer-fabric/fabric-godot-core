/**************************************************************************/
/*  xr_grid_entity_packet.h                                                */
/**************************************************************************/
/* Native port of                                                          */
/* xr-grid/addons/procedural_3d_grid/core/fabric/entity_packet.gd.         */
/*                                                                         */
/* Fixed 100-byte packet format the xr-grid fabric uses for player + stroke*/
/* entity sync. Layout (little-endian):                                    */
/*   [0..3]   global_id u32     (peer_id × 3 + sub_index)                  */
/*   [4..27]  position 3× f64                                              */
/*   [28..33] velocity 3× i16   (quantized × 1000, clamped ±32767)         */
/*   [34..39] acceleration 3× i16 (currently always zero, reserved)        */
/*   [40..43] HLC frame×counter (u24 frame | u8 counter)                   */
/*   [44..47] entity_class u8 << 24 | flags u8 << 16 | owner_id u16        */
/*   [48..51] sub_index u16 << 16 | 0                                      */
/*   [52..55] rotation pack: swing_y_i16 lo | swing_z_i16 hi               */
/*   [56..59] rotation pack: twist_x_i16 lo | reserved 0 hi                */
/*   [60..99] payload[4..13] reserved zeros                                */

#pragma once

#include "core/math/quaternion.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

class XRGridEntityPacket : public RefCounted {
	GDCLASS(XRGridEntityPacket, RefCounted);

protected:
	static void _bind_methods();

public:
	XRGridEntityPacket() = default;

	static constexpr int PACKET_SIZE = 100;
	static constexpr int64_t PLAYER_ENTITY_BASE = 2'000'000;
	static constexpr int64_t STROKE_ENTITY_BASE = 1'000'000;
	static constexpr int64_t MAX_PLAYER_ID = 700'000'000;

	// Encode the entity envelope into a fixed-size byte buffer ready for
	// fabric broadcast. Returns a 100-byte PackedByteArray.
	static PackedByteArray encode(
			int64_t p_global_id,
			const Vector3 &p_pos,
			const Vector3 &p_vel,
			const Quaternion &p_quat,
			int p_entity_class,
			int p_owner_id,
			int p_hlc_frame,
			int p_hlc_counter,
			int p_sub_index);

	// Decode a packet. Returns:
	//   {global_id, position, velocity, rotation, entity_class, owner_id,
	//    sub_index, hlc_frame, hlc_counter}
	// Returns an empty Dictionary on size mismatch.
	static Dictionary decode(const PackedByteArray &p_data);
};
