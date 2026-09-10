/**************************************************************************/
/*  ggml_engine.h                                                         */
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

#pragma once

#include "core/error/error_list.h"
#include "core/io/resource.h"
#include "core/object/ref_counted.h"
#include "core/string/ustring.h"
#include "core/templates/vector.h"

// The foundation Godot-facing surface for RFD 2242. GgmlEngine wraps
// ggml_context; GgmlTensor wraps a ggml_tensor* whose lifetime is tied to
// that context. `impl` holds the opaque pointer so this header does not
// have to include ggml.h — downstream code that uses these classes gets a
// clean Godot-typed surface without pulling ggml through their headers.

class GgmlTensor : public RefCounted {
	GDCLASS(GgmlTensor, RefCounted);

protected:
	static void _bind_methods();

public:
	Vector<int> get_shape() const;

	void *impl = nullptr; // ggml_tensor *
};

class GgmlEngine : public Object {
	GDCLASS(GgmlEngine, Object);

protected:
	static void _bind_methods();

public:
	static GgmlEngine *get_singleton();

	Error init(int64_t p_memory_bytes = 0);
	String get_version() const;

	GgmlEngine();
	~GgmlEngine();

private:
	static GgmlEngine *singleton;
	void *impl = nullptr; // ggml_context *
};
