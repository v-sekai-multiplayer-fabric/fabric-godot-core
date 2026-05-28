/**************************************************************************/
/*  resource_importer_audio_native.cpp                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/**************************************************************************/

#ifdef TOOLS_ENABLED

#include "resource_importer_audio_native.h"

#include "core/io/resource_saver.h"
#include "modules/native_media/audio_stream_native.h"

String ResourceImporterAudioNative::get_importer_name() const {
	return "audio_native";
}

String ResourceImporterAudioNative::get_visible_name() const {
	return "Native Media Audio";
}

void ResourceImporterAudioNative::get_recognized_extensions(List<String> *p_extensions) const {
	// Container formats Godot core doesn't already import (mp3 / wav / ogg
	// have their own importers; we cover the OS-native-decoded rest).
	p_extensions->push_back("m4a");
	p_extensions->push_back("aac");
	p_extensions->push_back("flac");
	p_extensions->push_back("opus");
}

String ResourceImporterAudioNative::get_save_extension() const {
	return "natstr";
}

String ResourceImporterAudioNative::get_resource_type() const {
	return "AudioStreamNative";
}

int ResourceImporterAudioNative::get_preset_count() const {
	return 0;
}

String ResourceImporterAudioNative::get_preset_name(int p_idx) const {
	return String();
}

void ResourceImporterAudioNative::get_import_options(const String &p_path, List<ImportOption> *r_options, int p_preset) const {
	r_options->push_back(ImportOption(PropertyInfo(Variant::BOOL, "loop"), false));
	r_options->push_back(ImportOption(PropertyInfo(Variant::FLOAT, "loop_offset"), 0.0));
	r_options->push_back(ImportOption(PropertyInfo(Variant::INT, "container_hint", PROPERTY_HINT_ENUM, "Auto,WebM,MP4,Ogg,WAV"), 0));
}

bool ResourceImporterAudioNative::get_option_visibility(const String &p_path, const String &p_option, const HashMap<StringName, Variant> &p_options) const {
	return true;
}

Error ResourceImporterAudioNative::import(ResourceUID::ID p_source_id, const String &p_source_file, const String &p_save_path, const HashMap<StringName, Variant> &p_options, List<String> *r_platform_variants, List<String> *r_gen_files, Variant *r_metadata) {
	bool loop = false;
	float loop_offset = 0.0f;
	int container_hint = 0;
	if (p_options.has("loop")) {
		loop = bool(p_options["loop"]);
	}
	if (p_options.has("loop_offset")) {
		loop_offset = float(p_options["loop_offset"]);
	}
	if (p_options.has("container_hint")) {
		container_hint = int(p_options["container_hint"]);
	}

	Ref<AudioStreamNative> stream = AudioStreamNative::load_from_file(p_source_file);
	if (stream.is_null() || stream->get_data().is_empty()) {
		return ERR_CANT_OPEN;
	}
	stream->set_container_hint(container_hint);
	stream->set_loop(loop);
	stream->set_loop_offset(loop_offset);

	return ResourceSaver::save(stream, p_save_path + ".natstr");
}

#endif // TOOLS_ENABLED
