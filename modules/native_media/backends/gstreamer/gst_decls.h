/**************************************************************************/
/*  gst_decls.h                                                           */
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

// Self-contained vendored declarations of the GLib / GStreamer 1.x API
// surface used by the native_media GStreamer backend. We never include
// upstream <gst/gst.h> or link against -lgstreamer-1.0; instead a
// stubgen-generated table dispatches calls through dlsym at runtime
// (LGPL-clean dynamic loading, no build-time host deps).
//
// ABI stability: GStreamer 1.x guarantees its public ABI across minor
// versions. The types declared here are either opaque (we only hold
// pointers) or are the documented public stack-allocatable structs
// (GstMapInfo, GstMappedMemory). Avoid touching internal struct fields —
// always go through library functions.

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- GLib basic typedefs ------------------------------------------------

typedef void *gpointer;
typedef const void *gconstpointer;
typedef char gchar;
typedef int gboolean;
typedef int gint;
typedef unsigned int guint;
typedef long glong;
typedef unsigned long gulong;
typedef size_t gsize;
typedef ptrdiff_t gssize;
typedef int8_t gint8;
typedef uint8_t guint8;
typedef int16_t gint16;
typedef uint16_t guint16;
typedef int32_t gint32;
typedef uint32_t guint32;
typedef int64_t gint64;
typedef uint64_t guint64;
typedef float gfloat;
typedef double gdouble;
typedef gsize GType;

typedef void (*GCallback)(void);
typedef void (*GClosureNotify)(gpointer, void *);

#define G_GNUC_CONST
#define G_TRUE 1
#define G_FALSE 0
#define G_MAXUINT64 ((guint64)0xFFFFFFFFFFFFFFFFULL)

typedef struct _GError {
	guint32 domain;
	gint code;
	gchar *message;
} GError;

// --- GStreamer opaque types ---------------------------------------------

typedef struct _GstElement GstElement;
typedef struct _GstPad GstPad;
typedef struct _GstCaps GstCaps;
typedef struct _GstStructure GstStructure;
typedef struct _GstBuffer GstBuffer;
typedef struct _GstSample GstSample;
typedef struct _GstBin GstBin;
typedef struct _GstObject GstObject;
typedef struct _GstMemory GstMemory;
typedef struct _GstAppSrc GstAppSrc;
typedef struct _GstAppSink GstAppSink;

typedef guint64 GstClockTime;
typedef gint64 GstClockTimeDiff;

// --- GStreamer enums (numeric values are part of the public ABI) --------

typedef enum {
	GST_FLOW_CUSTOM_SUCCESS_2 = 102,
	GST_FLOW_CUSTOM_SUCCESS_1 = 101,
	GST_FLOW_CUSTOM_SUCCESS = 100,
	GST_FLOW_OK = 0,
	GST_FLOW_NOT_LINKED = -1,
	GST_FLOW_FLUSHING = -2,
	GST_FLOW_EOS = -3,
	GST_FLOW_NOT_NEGOTIATED = -4,
	GST_FLOW_ERROR = -5,
} GstFlowReturn;

typedef enum {
	GST_STATE_VOID_PENDING = 0,
	GST_STATE_NULL = 1,
	GST_STATE_READY = 2,
	GST_STATE_PAUSED = 3,
	GST_STATE_PLAYING = 4,
} GstState;

typedef enum {
	GST_STATE_CHANGE_FAILURE = 0,
	GST_STATE_CHANGE_SUCCESS = 1,
	GST_STATE_CHANGE_ASYNC = 2,
	GST_STATE_CHANGE_NO_PREROLL = 3,
} GstStateChangeReturn;

typedef enum {
	GST_FORMAT_UNDEFINED = 0,
	GST_FORMAT_DEFAULT = 1,
	GST_FORMAT_BYTES = 2,
	GST_FORMAT_TIME = 3,
	GST_FORMAT_BUFFERS = 4,
	GST_FORMAT_PERCENT = 5,
} GstFormat;

typedef enum {
	GST_SEEK_FLAG_NONE = 0,
	GST_SEEK_FLAG_FLUSH = (1 << 0),
	GST_SEEK_FLAG_ACCURATE = (1 << 1),
	GST_SEEK_FLAG_KEY_UNIT = (1 << 2),
} GstSeekFlags;

typedef enum {
	GST_MAP_READ = (1 << 0),
	GST_MAP_WRITE = (1 << 1),
} GstMapFlags;

typedef enum {
	GST_MEMORY_FLAG_READONLY = (1 << 1),
} GstMemoryFlags;

// --- Stack-allocatable public structs -----------------------------------

// Public, stable since GStreamer 1.0. Used by gst_buffer_map() / unmap().
typedef struct _GstMapInfo {
	GstMemory *memory;
	GstMapFlags flags;
	guint8 *data;
	gsize size;
	gsize maxsize;
	gpointer user_data[4];
	gpointer _gst_reserved[4];
} GstMapInfo;

// --- Constants ---------------------------------------------------------

#define GST_SECOND ((GstClockTime)1000000000ULL)
#define GST_MSECOND ((GstClockTime)1000000ULL)
#define GST_USECOND ((GstClockTime)1000ULL)
#define GST_NSECOND ((GstClockTime)1ULL)
#define GST_CLOCK_TIME_NONE G_MAXUINT64

// --- Cast macros (just pointer casts; no field access) -----------------

#define GST_OBJECT(obj) ((GstObject *)(obj))
#define GST_BIN(obj) ((GstBin *)(obj))
#define GST_ELEMENT(obj) ((GstElement *)(obj))
#define GST_APP_SRC(obj) ((GstAppSrc *)(obj))
#define GST_APP_SINK(obj) ((GstAppSink *)(obj))

#ifdef __cplusplus
}
#endif
