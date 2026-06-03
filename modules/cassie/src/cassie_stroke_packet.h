#pragma once

#include "core/io/resource.h"
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"
#include "core/variant/variant.h"

// CassieStrokePacket — fixed-shape, byte-deterministic serializer for the
// raw input samples xr-grid broadcasts over the WebTransport "fabric"
// reliable channel. Each peer decodes the same bytes and reruns Beautify
// locally; bit-determinism guarantees the resulting FinalStroke / graph
// state is identical across clients.
//
// Wire format (all integers little-endian):
//   [magic u32 = 'CSP1'][peer_id u32][stroke_id u32][seq u16]
//   [sample_count u16][closed_flag u8][reserved u8]
//   // then sample_count × (pos.x f32, pos.y f32, pos.z f32, pressure f32)
//
// creation_time is NOT on the wire: receiver reconstructs it as
// (sample_index × sample_dt) so wall-clock drift between peers does not
// leak into Beautify input.
//
// f32 pressure (not f16) because a single byte-flip must be reproducible
// bit-exactly inside the determinism test.
//
// Magic 'CSP1' = 0x31_50_53_43 little-endian (CSP1 ASCII).

class CassieStrokePacket : public RefCounted {
	GDCLASS(CassieStrokePacket, RefCounted);

protected:
	static void _bind_methods();

public:
	CassieStrokePacket() = default;

	static constexpr uint32_t MAGIC = 0x31'50'53'43u; // 'CSP1' LE
	static constexpr int HEADER_BYTES = 4 + 4 + 4 + 2 + 2 + 1 + 1; // 18
	static constexpr int SAMPLE_BYTES = 4 * 4; // pos xyz + pressure

	// Encode a sample run into a PackedByteArray. ints are taken as i64
	// to play nice with GDScript; we truncate to u32/u16 in the body.
	// `positions` and `pressures` must be the same length.
	static PackedByteArray encode(int64_t p_peer_id, int64_t p_stroke_id,
			int64_t p_seq, bool p_closed,
			const PackedVector3Array &p_positions,
			const PackedFloat32Array &p_pressures);

	// Decode a PackedByteArray. Result dict:
	//   ok          : bool
	//   peer_id     : int (uint32 widened)
	//   stroke_id   : int
	//   seq         : int
	//   closed      : bool
	//   positions   : PackedVector3Array
	//   pressures   : PackedFloat32Array
	// Returns ok=false with empty arrays on magic mismatch / size mismatch.
	static Dictionary decode(const PackedByteArray &p_bytes);
};
