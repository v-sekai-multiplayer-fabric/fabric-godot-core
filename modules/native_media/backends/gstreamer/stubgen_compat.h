/**************************************************************************/
/*  stubgen_compat.h                                                      */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/**************************************************************************/

#pragma once

#include "modules/native_media/backends/gstreamer/gst_decls.h"

// generate_stubs.py emits this macro on every dispatched call to opt out of
// Chromium's Control Flow Integrity indirect-call check. Godot doesn't ship
// with CFI on the indirect-call path, so the macro can stay empty.
#define DISABLE_CFI_ICALL

// stubgen needs a type reachable everywhere (in particular: where the umbrella
// initializer lives). Provide an alias so the generated namespace name doesn't
// clash with user code.
namespace native_media_gst {}
