// Reverb probe bake compute shader.
// Per-probe ray tracing to estimate mean absorption per frequency band.
// Output feeds into Resonance Audio's ComputeReverbProperties (Eyring equation).
//
// Compile targets:
//   GPU: slangc reverb_bake.slang -target spirv -profile sm_6_0 -entry main -o reverb_bake.spv
//   CPU: slangc reverb_bake.slang -target cpp -entry main -o reverb_bake.cpp

static const uint NUM_BANDS = 9;

struct BakeParams {
	uint ray_count;
	uint max_bounces;
	uint probe_count;
	uint triangle_count;
	uint ray_from;
	uint ray_to;
	float cell_size;
	int grid_size;
	float3 grid_offset;
	float bias;
};

struct Vertex {
	float3 position;
	float3 normal;
};

struct Triangle {
	uint i0;
	uint i1;
	uint i2;
	uint material_index;
};

struct MaterialAbsorption {
	float coefficients[NUM_BANDS];
};

struct ProbeAccum {
	float absorbed[NUM_BANDS];
	float total_hits;
};

[[vk::binding(0, 0)]] ConstantBuffer<BakeParams> params;
[[vk::binding(1, 0)]] StructuredBuffer<Vertex> vertices;
[[vk::binding(2, 0)]] StructuredBuffer<Triangle> triangles;
[[vk::binding(3, 0)]] StructuredBuffer<float4> probe_positions;
[[vk::binding(4, 0)]] StructuredBuffer<MaterialAbsorption> materials;
[[vk::binding(5, 0)]] StructuredBuffer<uint> grid_indices;
[[vk::binding(0, 1)]] RWStructuredBuffer<ProbeAccum> output_accum;

// PCG hash for deterministic pseudo-random numbers.
uint pcg_hash(uint state) {
	uint s = state * 747796405u + 2891336453u;
	uint word = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (word >> 22u) ^ word;
}

float rand_float(inout uint state) {
	state = pcg_hash(state);
	return float(state) / float(0xFFFFFFFFu);
}

// Uniform sphere direction from two random floats.
float3 random_sphere_direction(inout uint rng) {
	float z = 2.0 * rand_float(rng) - 1.0;
	float phi = 2.0 * 3.14159265 * rand_float(rng);
	float r = sqrt(max(0.0, 1.0 - z * z));
	return float3(r * cos(phi), r * sin(phi), z);
}

// Cosine-weighted hemisphere direction around normal.
float3 random_cosine_direction(float3 normal, inout uint rng) {
	float3 dir = random_sphere_direction(rng);
	return normalize(dir + normal);
}

// Moller-Trumbore ray-triangle intersection.
bool ray_triangle_intersect(float3 ro, float3 rd, float3 v0, float3 v1, float3 v2,
		out float t, out float3 normal_out) {
	t = 0.0;
	normal_out = float3(0, 0, 0);
	float3 e1 = v1 - v0;
	float3 e2 = v2 - v0;
	float3 h = cross(rd, e2);
	float a = dot(e1, h);
	if (abs(a) < 1e-8)
		return false;
	float f = 1.0 / a;
	float3 s = ro - v0;
	float u = f * dot(s, h);
	if (u < 0.0 || u > 1.0)
		return false;
	float3 q = cross(s, e1);
	float v = f * dot(rd, q);
	if (v < 0.0 || u + v > 1.0)
		return false;
	t = f * dot(e2, q);
	if (t < 1e-5)
		return false;
	normal_out = normalize(cross(e1, e2));
	if (dot(normal_out, rd) > 0.0)
		normal_out = -normal_out;
	return true;
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
	uint probe_index = tid.x;
	if (probe_index >= params.probe_count)
		return;

	float3 position = probe_positions[probe_index].xyz;
	uint rng = pcg_hash(probe_index * 1337u + params.ray_from * 7919u);

	float local_absorbed[NUM_BANDS];
	for (uint b = 0; b < NUM_BANDS; b++)
		local_absorbed[b] = 0.0;
	float local_hits = 0.0;

	for (uint ray_idx = params.ray_from; ray_idx < params.ray_to; ray_idx++) {
		float3 ray_dir = random_sphere_direction(rng);
		float3 ray_origin = position;

		for (uint bounce = 0; bounce < params.max_bounces; bounce++) {
			float best_t = 1e30;
			int best_tri = -1;
			float3 best_normal = float3(0, 1, 0);

			// Brute-force closest intersection (grid acceleration is future optimization).
			for (uint ti = 0; ti < params.triangle_count; ti++) {
				Triangle tri = triangles[ti];
				float3 v0 = vertices[tri.i0].position;
				float3 v1 = vertices[tri.i1].position;
				float3 v2 = vertices[tri.i2].position;

				float t;
				float3 n;
				if (ray_triangle_intersect(ray_origin, ray_dir, v0, v1, v2, t, n)) {
					if (t < best_t) {
						best_t = t;
						best_tri = int(ti);
						best_normal = n;
					}
				}
			}

			if (best_tri < 0)
				break; // Ray escaped — fully absorbed (outdoor).

			uint mat_idx = triangles[best_tri].material_index;
			for (uint b = 0; b < NUM_BANDS; b++) {
				local_absorbed[b] += materials[mat_idx].coefficients[b];
			}
			local_hits += 1.0;

			ray_origin = ray_origin + ray_dir * best_t + best_normal * params.bias;
			ray_dir = random_cosine_direction(best_normal, rng);
		}
	}

	// Write to output accumulator.
	for (uint b = 0; b < NUM_BANDS; b++) {
		output_accum[probe_index].absorbed[b] += local_absorbed[b];
	}
	output_accum[probe_index].total_hits += local_hits;
}
