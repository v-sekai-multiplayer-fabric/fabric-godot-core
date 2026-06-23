/**************************************************************************/
/*  otel_exporter_http.h                                                  */
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

#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Fire-and-forget OTLP/HTTP JSON exporter targeting VictoriaMetrics / VictoriaTraces.
//
// Batches spans, metrics, and log records and flushes them to:
//   VictoriaTraces  → POST /opentelemetry/v1/traces
//   VictoriaMetrics → POST /opentelemetry/v1/metrics
//   VictoriaLogs    → POST /insert/opentelemetry/v1/logs
//
// Uses StreamPeerTCP for HTTP/1.0 so it works in headless servers.
//
// Round/phase API mirrors the GDScript version:
//   OtelExporter.new(service, host, port)  — _init bound so new() forwards args
//   begin_round() → trace_id
//   begin_phase(trace_id, phase_name, attrs) → span_id
//   end_phase(trace_id, phase_name, extra_attrs)
//   end_round(trace_id, attrs)
//   event_span(trace_id, name, start_ns, attrs)
//   counter(name, value, attrs)
//   gauge(name, value, attrs)
//   log_record(body, severity)
//   process(delta)   — call from _process
//   flush()
//   now_ns() → String

class OtelExporter : public RefCounted {
	GDCLASS(OtelExporter, RefCounted);

	static constexpr float FLUSH_INTERVAL = 5.0f;
	static constexpr int MAX_BATCH = 128;

	String _host;
	int _port = 4318;
	String _service_name;

	Array _spans;
	Array _metrics;
	Array _logs;
	float _flush_accum = 0.0f;

	// trace_id → { root_span_id, start_ns, phase_* }
	Dictionary _open_rounds;

	String _rand_hex(int p_bytes) const;
	String _now_ns() const;
	Array _kvlist(const Dictionary &p_dict) const;
	Dictionary _resource() const;

	void _enqueue_span(const String &p_trace_id, const String &p_span_id,
			const String &p_parent_id, const String &p_name,
			const String &p_start_ns, const String &p_end_ns,
			const Array &p_attrs);

	void _post(const String &p_path, const String &p_body) const;

	void _flush_traces();
	void _flush_metrics();
	void _flush_logs();

protected:
	static void _bind_methods();

public:
	OtelExporter() = default;

	void initialize(const String &p_service, const String &p_host = "127.0.0.1", int p_port = 4318);

	String now_ns() const;

	String begin_round();
	String begin_phase(const String &p_trace_id, const String &p_phase, const Dictionary &p_attrs = Dictionary());
	void end_phase(const String &p_trace_id, const String &p_phase, const Dictionary &p_extra = Dictionary());
	void end_round(const String &p_trace_id, const Dictionary &p_attrs = Dictionary());

	void event_span(const String &p_trace_id, const String &p_name,
			const String &p_start_ns, const Dictionary &p_attrs = Dictionary());

	void counter(const String &p_name, int p_value, const Dictionary &p_attrs = Dictionary());
	void gauge(const String &p_name, float p_value, const Dictionary &p_attrs = Dictionary());
	void log_record(const String &p_body, int p_severity = 9);

	void process(float p_delta);
	void flush();
};
