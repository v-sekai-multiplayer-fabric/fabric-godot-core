/**************************************************************************/
/*  xr_grid_entity_packet.cpp                                              */
/**************************************************************************/

#include "xr_grid_entity_packet.h"

#include "xr_grid_swing_twist_codec.h"

#include "core/object/class_db.h"

namespace {

inline void _put_u32_le(uint8_t *p, uint32_t v) {
	p[0] = uint8_t(v & 0xFF);
	p[1] = uint8_t((v >> 8) & 0xFF);
	p[2] = uint8_t((v >> 16) & 0xFF);
	p[3] = uint8_t((v >> 24) & 0xFF);
}

inline void _put_i16_le(uint8_t *p, int16_t v) {
	const uint16_t u = uint16_t(v);
	p[0] = uint8_t(u & 0xFF);
	p[1] = uint8_t((u >> 8) & 0xFF);
}

inline void _put_f64_le(uint8_t *p, double v) {
	uint64_t bits;
	memcpy(&bits, &v, 8);
	for (int i = 0; i < 8; ++i) {
		p[i] = uint8_t((bits >> (i * 8)) & 0xFF);
	}
}

inline uint32_t _get_u32_le(const uint8_t *p) {
	return uint32_t(p[0]) |
			(uint32_t(p[1]) << 8) |
			(uint32_t(p[2]) << 16) |
			(uint32_t(p[3]) << 24);
}

inline int16_t _get_i16_le(const uint8_t *p) {
	const uint16_t u = uint16_t(p[0]) | (uint16_t(p[1]) << 8);
	return int16_t(u);
}

inline double _get_f64_le(const uint8_t *p) {
	uint64_t bits = 0;
	for (int i = 0; i < 8; ++i) {
		bits |= uint64_t(p[i]) << (i * 8);
	}
	double v;
	memcpy(&v, &bits, 8);
	return v;
}

inline int _quantize_vel(double v) {
	const double q = v * 1000.0;
	return int(CLAMP(q, -32767.0, 32767.0));
}

inline double _dequantize_vel(int v) {
	return double(v) / 1000.0;
}

} // namespace

PackedByteArray XRGridEntityPacket::encode(
		int64_t p_global_id,
		const Vector3 &p_pos,
		const Vector3 &p_vel,
		const Quaternion &p_quat,
		int p_entity_class,
		int p_owner_id,
		int p_hlc_frame,
		int p_hlc_counter,
		int p_sub_index) {
	PackedByteArray out;
	out.resize(PACKET_SIZE);
	uint8_t *w = out.ptrw();
	memset(w, 0, PACKET_SIZE);

	_put_u32_le(w + 0, uint32_t(p_global_id));
	_put_f64_le(w + 4, double(p_pos.x));
	_put_f64_le(w + 12, double(p_pos.y));
	_put_f64_le(w + 20, double(p_pos.z));
	_put_i16_le(w + 28, int16_t(_quantize_vel(double(p_vel.x))));
	_put_i16_le(w + 30, int16_t(_quantize_vel(double(p_vel.y))));
	_put_i16_le(w + 32, int16_t(_quantize_vel(double(p_vel.z))));
	// acceleration 34..39 already zeroed by memset
	const uint32_t hlc = (uint32_t(p_hlc_frame & 0xFFFFFF) << 8) |
			uint32_t(p_hlc_counter & 0xFF);
	_put_u32_le(w + 40, hlc);
	const uint32_t p0 = (uint32_t(p_entity_class & 0xFF) << 24) |
			uint32_t(p_owner_id & 0xFFFF);
	_put_u32_le(w + 44, p0);
	const uint32_t p1 = uint32_t(p_sub_index & 0xFFFF) << 16;
	_put_u32_le(w + 48, p1);
	// Rotation pack — encode_rotation_i16 returns [twist_x, swing_y, swing_z].
	const PackedInt32Array rot = XRGridSwingTwistCodec::encode_rotation_i16(p_quat);
	const int32_t twist_x = rot.size() >= 3 ? rot[0] : 0;
	const int32_t swing_y = rot.size() >= 3 ? rot[1] : 0;
	const int32_t swing_z = rot.size() >= 3 ? rot[2] : 0;
	_put_i16_le(w + 52, int16_t(swing_y));
	_put_i16_le(w + 54, int16_t(swing_z));
	_put_i16_le(w + 56, int16_t(twist_x));
	// 58..59 and 60..99 remain zero
	return out;
}

Dictionary XRGridEntityPacket::decode(const PackedByteArray &p_data) {
	Dictionary d;
	if (p_data.size() < PACKET_SIZE) {
		return d;
	}
	const uint8_t *r = p_data.ptr();
	const uint32_t global_id = _get_u32_le(r + 0);
	const Vector3 pos(
			real_t(_get_f64_le(r + 4)),
			real_t(_get_f64_le(r + 12)),
			real_t(_get_f64_le(r + 20)));
	const Vector3 vel(
			real_t(_dequantize_vel(_get_i16_le(r + 28))),
			real_t(_dequantize_vel(_get_i16_le(r + 30))),
			real_t(_dequantize_vel(_get_i16_le(r + 32))));
	const uint32_t hlc_raw = _get_u32_le(r + 40);
	const int hlc_frame = int((hlc_raw >> 8) & 0xFFFFFFu);
	const int hlc_counter = int(hlc_raw & 0xFFu);
	const uint32_t p0 = _get_u32_le(r + 44);
	const int entity_class = int((p0 >> 24) & 0xFF);
	const int owner_id = int(p0 & 0xFFFF);
	const uint32_t p1 = _get_u32_le(r + 48);
	const int sub_index = int((p1 >> 16) & 0xFFFF);
	const int swing_y = int(_get_i16_le(r + 52));
	const int swing_z = int(_get_i16_le(r + 54));
	const int twist_x = int(_get_i16_le(r + 56));
	const Quaternion rotation = XRGridSwingTwistCodec::decode_rotation_i16(twist_x, swing_y, swing_z);

	d["global_id"] = int64_t(global_id);
	d["position"] = pos;
	d["velocity"] = vel;
	d["rotation"] = rotation;
	d["entity_class"] = entity_class;
	d["owner_id"] = owner_id;
	d["sub_index"] = sub_index;
	d["hlc_frame"] = hlc_frame;
	d["hlc_counter"] = hlc_counter;
	return d;
}

void XRGridEntityPacket::_bind_methods() {
	ClassDB::bind_static_method("XRGridEntityPacket",
			D_METHOD("encode", "global_id", "pos", "vel", "quat",
					"entity_class", "owner_id", "hlc_frame", "hlc_counter", "sub_index"),
			&XRGridEntityPacket::encode);
	ClassDB::bind_static_method("XRGridEntityPacket",
			D_METHOD("decode", "data"),
			&XRGridEntityPacket::decode);

	BIND_CONSTANT(PACKET_SIZE);
	BIND_CONSTANT(PLAYER_ENTITY_BASE);
	BIND_CONSTANT(STROKE_ENTITY_BASE);
	BIND_CONSTANT(MAX_PLAYER_ID);
}
