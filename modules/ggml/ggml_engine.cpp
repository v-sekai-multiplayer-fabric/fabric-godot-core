/**************************************************************************/
/*  ggml_engine.cpp                                                       */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "ggml_engine.h"

#include "ggml.h"

#include "core/object/class_db.h"
#include "core/string/ustring.h"

// GgmlEngine wraps a ggml_context; GgmlTensor wraps a ggml_tensor* whose
// lifetime is tied to that context. The Godot classes expose the minimum
// surface a follow-up module can build on: init the context with a memory
// budget, allocate a tensor of a shape, read the tensor's shape back.

GgmlEngine *GgmlEngine::singleton = nullptr;

GgmlEngine *GgmlEngine::get_singleton() {
	return singleton;
}

GgmlEngine::GgmlEngine() {
	singleton = this;
}

GgmlEngine::~GgmlEngine() {
	if (impl != nullptr) {
		ggml_free(static_cast<ggml_context *>(impl));
		impl = nullptr;
	}
	if (singleton == this) {
		singleton = nullptr;
	}
}

Error GgmlEngine::init(int64_t p_memory_bytes) {
	if (impl != nullptr) {
		return ERR_ALREADY_EXISTS;
	}
	ggml_init_params params = {};
	params.mem_size = static_cast<size_t>(p_memory_bytes > 0 ? p_memory_bytes : (16 * 1024 * 1024));
	params.mem_buffer = nullptr;
	params.no_alloc = false;
	ggml_context *ctx = ggml_init(params);
	if (ctx == nullptr) {
		return ERR_OUT_OF_MEMORY;
	}
	impl = ctx;
	return OK;
}

String GgmlEngine::get_version() const {
	// ggml doesn't expose a version string; the fact that this string returns
	// at all is the smoke test that ggml linked. A future revision can expand
	// to report the specific ggml commit vendored under thirdparty/ggml/.
	return String("ggml linked");
}

void GgmlEngine::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init", "memory_bytes"), &GgmlEngine::init, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_version"), &GgmlEngine::get_version);
}

Vector<int> GgmlTensor::get_shape() const {
	Vector<int> out;
	if (impl == nullptr) {
		return out;
	}
	const ggml_tensor *t = static_cast<const ggml_tensor *>(impl);
	for (int i = 0; i < GGML_MAX_DIMS; ++i) {
		if (t->ne[i] <= 1 && i > 0) {
			break;
		}
		out.push_back(static_cast<int>(t->ne[i]));
	}
	return out;
}

void GgmlTensor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_shape"), &GgmlTensor::get_shape);
}
