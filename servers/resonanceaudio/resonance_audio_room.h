#pragma once

#include "scene/3d/node_3d.h"

class ResonanceAudioRoom : public Node3D {
	GDCLASS(ResonanceAudioRoom, Node3D);

	bool room_effects_enabled = true;
	float reflection_gain = 1.0f;
	float reverb_gain = 1.0f;
	float reverb_brightness = 0.0f;
	float reverb_time_scale = 1.0f;

	int wall_material = 1; // Default: kPlasterSmooth

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	void set_room_effects_enabled(bool p_enabled);
	bool get_room_effects_enabled() const;

	void set_reflection_gain(float p_gain);
	float get_reflection_gain() const;

	void set_reverb_gain(float p_gain);
	float get_reverb_gain() const;

	void set_reverb_brightness(float p_brightness);
	float get_reverb_brightness() const;

	void set_reverb_time_scale(float p_scale);
	float get_reverb_time_scale() const;

	void set_wall_material(int p_material);
	int get_wall_material() const;

	void update_room_from_colliders();

	ResonanceAudioRoom() = default;
};
