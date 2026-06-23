/**************************************************************************/
/*  otel_exporter_http.cpp                                                */
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

#include "otel_exporter_http.h"

#include "core/io/ip.h"
#include "core/io/json.h"
#include "core/io/stream_peer_tcp.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/os/time.h"

// ── Binding ───────────────────────────────────────────────────────────────────

void OtelExporter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("_init", "service_name", "host", "port"),
			&OtelExporter::initialize, DEFVAL("127.0.0.1"), DEFVAL(4318));

	ClassDB::bind_method(D_METHOD("now_ns"), &OtelExporter::now_ns);

	ClassDB::bind_method(D_METHOD("begin_round"), &OtelExporter::begin_round);
	ClassDB::bind_method(D_METHOD("begin_phase", "trace_id", "phase_name", "attrs"),
			&OtelExporter::begin_phase, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("end_phase", "trace_id", "phase_name", "extra_attrs"),
			&OtelExporter::end_phase, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("end_round", "trace_id", "attrs"),
			&OtelExporter::end_round, DEFVAL(Dictionary()));

	ClassDB::bind_method(D_METHOD("event_span", "trace_id", "name", "start_ns", "attrs"),
			&OtelExporter::event_span, DEFVAL(Dictionary()));

	ClassDB::bind_method(D_METHOD("counter", "name", "value", "attrs"),
			&OtelExporter::counter, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("gauge", "name", "value", "attrs"),
			&OtelExporter::gauge, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("log_record", "body", "severity"),
			&OtelExporter::log_record, DEFVAL(9));

	ClassDB::bind_method(D_METHOD("process", "delta"), &OtelExporter::process);
	ClassDB::bind_method(D_METHOD("flush"), &OtelExporter::flush);
}

// ── Init ──────────────────────────────────────────────────────────────────────

void OtelExporter::initialize(const String &p_service, const String &p_host, int p_port) {
	_service_name = p_service;
	_host = p_host;
	_port = p_port;
}

// ── ID / time helpers ─────────────────────────────────────────────────────────

String OtelExporter::_rand_hex(int p_bytes) const {
	String s;
	for (int i = 0; i < p_bytes; i++) {
		s += String::num_int64((int64_t)Math::rand() & 0xFF, 16).lpad(2, "0");
	}
	return s;
}

String OtelExporter::_now_ns() const {
	return now_ns();
}

String OtelExporter::now_ns() const {
	return String::num_int64((int64_t)(Time::get_singleton()->get_unix_time_from_system() * 1'000'000'000.0));
}

// ── Resource attribute ────────────────────────────────────────────────────────

Dictionary OtelExporter::_resource() const {
	Array attrs;
	Dictionary svc;
	svc["key"] = "service.name";
	Dictionary svc_val;
	svc_val["stringValue"] = _service_name;
	svc["value"] = svc_val;
	attrs.push_back(svc);
	Dictionary res;
	res["attributes"] = attrs;
	return res;
}

// ── kvlist helper ─────────────────────────────────────────────────────────────

Array OtelExporter::_kvlist(const Dictionary &p_dict) const {
	Array out;
	for (int i = 0; i < p_dict.size(); i++) {
		Variant key = p_dict.get_key_at_index(i);
		Variant val = p_dict.get_value_at_index(i);
		Dictionary kv;
		kv["key"] = key;
		Dictionary v;
		switch (val.get_type()) {
			case Variant::INT:
				v["intValue"] = String::num_int64((int64_t)val);
				break;
			case Variant::FLOAT:
				v["doubleValue"] = (double)val;
				break;
			default:
				v["stringValue"] = String(val);
				break;
		}
		kv["value"] = v;
		out.push_back(kv);
	}
	return out;
}

// ── Round / phase API ─────────────────────────────────────────────────────────

String OtelExporter::begin_round() {
	String trace_id = _rand_hex(16);
	String span_id = _rand_hex(8);
	Dictionary info;
	info["root_span_id"] = span_id;
	info["start_ns"] = _now_ns();
	_open_rounds[trace_id] = info;
	return trace_id;
}

String OtelExporter::begin_phase(const String &p_trace_id, const String &p_phase, const Dictionary &p_attrs) {
	if (!_open_rounds.has(p_trace_id)) {
		return String();
	}
	String span_id = _rand_hex(8);
	Dictionary round = _open_rounds[p_trace_id];
	String parent_id = round.get("root_span_id", String());

	Dictionary phase_info;
	phase_info["span_id"] = span_id;
	phase_info["start_ns"] = _now_ns();
	phase_info["name"] = p_phase;
	phase_info["attrs"] = _kvlist(p_attrs);
	phase_info["parent_id"] = parent_id;
	phase_info["trace_id"] = p_trace_id;

	round["phase_" + p_phase] = phase_info;
	_open_rounds[p_trace_id] = round;
	return span_id;
}

void OtelExporter::end_phase(const String &p_trace_id, const String &p_phase, const Dictionary &p_extra) {
	if (!_open_rounds.has(p_trace_id)) {
		return;
	}
	Dictionary round = _open_rounds[p_trace_id];
	String key = "phase_" + p_phase;
	if (!round.has(key)) {
		return;
	}
	Dictionary info = round[key];
	round.erase(key);
	_open_rounds[p_trace_id] = round;

	Array attrs = info.get("attrs", Array());
	Array extra = _kvlist(p_extra);
	for (int i = 0; i < extra.size(); i++) {
		attrs.push_back(extra[i]);
	}
	_enqueue_span(p_trace_id, info["span_id"], info.get("parent_id", String()),
			info["name"], info["start_ns"], _now_ns(), attrs);
}

void OtelExporter::end_round(const String &p_trace_id, const Dictionary &p_attrs) {
	if (!_open_rounds.has(p_trace_id)) {
		return;
	}
	Dictionary info = _open_rounds[p_trace_id];
	_open_rounds.erase(p_trace_id);
	_enqueue_span(p_trace_id, info["root_span_id"], String(),
			"game.round", info["start_ns"], _now_ns(), _kvlist(p_attrs));
	flush();
}

// ── One-shot event span ───────────────────────────────────────────────────────

void OtelExporter::event_span(const String &p_trace_id, const String &p_name,
		const String &p_start_ns, const Dictionary &p_attrs) {
	String parent_id;
	if (_open_rounds.has(p_trace_id)) {
		Dictionary round = _open_rounds[p_trace_id];
		parent_id = round.get("root_span_id", String());
	}
	_enqueue_span(p_trace_id, _rand_hex(8), parent_id, p_name, p_start_ns, _now_ns(), _kvlist(p_attrs));
}

// ── Metrics ───────────────────────────────────────────────────────────────────

void OtelExporter::counter(const String &p_name, int p_value, const Dictionary &p_attrs) {
	Dictionary m;
	m["type"] = "sum";
	m["name"] = p_name;
	m["value"] = p_value;
	m["attrs"] = _kvlist(p_attrs);
	m["ts"] = _now_ns();
	_metrics.push_back(m);
	if (_metrics.size() >= MAX_BATCH) {
		_flush_metrics();
	}
}

void OtelExporter::gauge(const String &p_name, float p_value, const Dictionary &p_attrs) {
	Dictionary m;
	m["type"] = "gauge";
	m["name"] = p_name;
	m["value"] = p_value;
	m["attrs"] = _kvlist(p_attrs);
	m["ts"] = _now_ns();
	_metrics.push_back(m);
	if (_metrics.size() >= MAX_BATCH) {
		_flush_metrics();
	}
}

// ── Logs ──────────────────────────────────────────────────────────────────────

void OtelExporter::log_record(const String &p_body, int p_severity) {
	Dictionary l;
	l["body"] = p_body;
	l["severity"] = p_severity;
	l["ts"] = _now_ns();
	_logs.push_back(l);
	if (_logs.size() >= MAX_BATCH) {
		_flush_logs();
	}
}

// ── Tick ──────────────────────────────────────────────────────────────────────

void OtelExporter::process(float p_delta) {
	_flush_accum += p_delta;
	if (_flush_accum >= FLUSH_INTERVAL) {
		_flush_accum = 0.0f;
		flush();
	}
}

void OtelExporter::flush() {
	if (!_spans.is_empty()) {
		_flush_traces();
	}
	if (!_metrics.is_empty()) {
		_flush_metrics();
	}
	if (!_logs.is_empty()) {
		_flush_logs();
	}
}

// ── Internal: enqueue span ────────────────────────────────────────────────────

void OtelExporter::_enqueue_span(const String &p_trace_id, const String &p_span_id,
		const String &p_parent_id, const String &p_name,
		const String &p_start_ns, const String &p_end_ns,
		const Array &p_attrs) {
	Dictionary s;
	s["traceId"] = p_trace_id;
	s["spanId"] = p_span_id;
	s["name"] = p_name;
	s["kind"] = 2;
	s["startTimeUnixNano"] = p_start_ns;
	s["endTimeUnixNano"] = p_end_ns;
	s["attributes"] = p_attrs;
	Dictionary status;
	status["code"] = 1;
	s["status"] = status;
	if (!p_parent_id.is_empty()) {
		s["parentSpanId"] = p_parent_id;
	}
	_spans.push_back(s);
	if (_spans.size() >= MAX_BATCH) {
		_flush_traces();
	}
}

// ── Internal: HTTP POST via StreamPeerTCP ─────────────────────────────────────

void OtelExporter::_post(const String &p_path, const String &p_body) const {
	IPAddress addr = IP::get_singleton()->resolve_hostname(_host);
	if (!addr.is_valid()) {
		return;
	}

	Ref<StreamPeerTCP> tcp = StreamPeerTCP::create_ref();
	if (tcp->connect_to_host(addr, _port) != OK) {
		return;
	}

	uint64_t t = OS::get_singleton()->get_ticks_msec();
	while (tcp->get_status() == StreamPeerSocket::STATUS_CONNECTING) {
		OS::get_singleton()->delay_usec(1000);
		tcp->poll();
		if (OS::get_singleton()->get_ticks_msec() - t > 500) {
			tcp->disconnect_from_host();
			return;
		}
	}
	if (tcp->get_status() != StreamPeerSocket::STATUS_CONNECTED) {
		return;
	}

	PackedByteArray body_bytes = p_body.to_utf8_buffer();
	String header = vformat("POST %s HTTP/1.0\r\nHost: %s:%d\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n",
			p_path, _host, _port, body_bytes.size());
	PackedByteArray header_bytes = header.to_utf8_buffer();

	tcp->put_data(header_bytes.ptr(), header_bytes.size());
	tcp->put_data(body_bytes.ptr(), body_bytes.size());
	tcp->disconnect_from_host();
}

// ── Internal: flush helpers ───────────────────────────────────────────────────

void OtelExporter::_flush_traces() {
	Array spans = _spans.duplicate();
	_spans.clear();

	Dictionary scope;
	scope["scope"] = Dictionary();
	scope["spans"] = spans;
	Array scope_spans;
	scope_spans.push_back(scope);

	Dictionary resource_spans;
	resource_spans["resource"] = _resource();
	resource_spans["scopeSpans"] = scope_spans;
	Array rs;
	rs.push_back(resource_spans);

	Dictionary payload;
	payload["resourceSpans"] = rs;

	_post("/opentelemetry/v1/traces", JSON::stringify(payload));
}

void OtelExporter::_flush_metrics() {
	Array list;
	for (int i = 0; i < _metrics.size(); i++) {
		Dictionary m = _metrics[i];
		Dictionary dp;
		dp["timeUnixNano"] = m["ts"];
		dp["attributes"] = m["attrs"];
		Variant val = m["value"];
		if (val.get_type() == Variant::INT) {
			dp["asInt"] = String::num_int64((int64_t)val);
		} else {
			dp["asDouble"] = (double)val;
		}
		Dictionary metric;
		metric["name"] = m["name"];
		if (String(m["type"]) == "gauge") {
			Array dps;
			dps.push_back(dp);
			Dictionary g;
			g["dataPoints"] = dps;
			metric["gauge"] = g;
		} else {
			Array dps;
			dps.push_back(dp);
			Dictionary sum;
			sum["dataPoints"] = dps;
			sum["aggregationTemporality"] = 2;
			sum["isMonotonic"] = true;
			metric["sum"] = sum;
		}
		list.push_back(metric);
	}
	_metrics.clear();

	Dictionary scope;
	scope["scope"] = Dictionary();
	scope["metrics"] = list;
	Array scope_metrics;
	scope_metrics.push_back(scope);

	Dictionary resource_metrics;
	resource_metrics["resource"] = _resource();
	resource_metrics["scopeMetrics"] = scope_metrics;
	Array rm;
	rm.push_back(resource_metrics);

	Dictionary payload;
	payload["resourceMetrics"] = rm;

	_post("/opentelemetry/v1/metrics", JSON::stringify(payload));
}

void OtelExporter::_flush_logs() {
	Array records;
	for (int i = 0; i < _logs.size(); i++) {
		Dictionary l = _logs[i];
		int sev = (int)l["severity"];
		String sev_text = sev >= 17 ? "ERROR" : (sev >= 13 ? "WARN" : "INFO");
		Dictionary body_val;
		body_val["stringValue"] = l["body"];
		Dictionary rec;
		rec["timeUnixNano"] = l["ts"];
		rec["severityNumber"] = sev;
		rec["severityText"] = sev_text;
		rec["body"] = body_val;
		records.push_back(rec);
	}
	_logs.clear();

	Dictionary scope;
	scope["scope"] = Dictionary();
	scope["logRecords"] = records;
	Array scope_logs;
	scope_logs.push_back(scope);

	Dictionary resource_logs;
	resource_logs["resource"] = _resource();
	resource_logs["scopeLogs"] = scope_logs;
	Array rl;
	rl.push_back(resource_logs);

	Dictionary payload;
	payload["resourceLogs"] = rl;

	_post("/insert/opentelemetry/v1/logs", JSON::stringify(payload));
}
