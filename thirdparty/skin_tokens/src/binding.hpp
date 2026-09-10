#pragma once

#include <skintokens/skintokens.hpp>

#include <cstdint>
#include <span>
#include <vector>

namespace skintokens::detail {

struct precise_vec3 { double x, y, z; };

struct binding_trace {
    std::vector<std::uint32_t> neighbor_indices;
    std::vector<float> interpolation_weights;
    std::vector<float> surface_weights;
    // Final dense matrix after interpolation and optional voxel_skin
    // multiplication, immediately before top-four selection.
    std::vector<float> final_dense_weights;
    std::vector<std::int32_t> voxel_coordinates;
    std::vector<std::uint32_t> surface_seeds;
    std::vector<float> surface_distances; // [joint, vertex], after fallback/inf replacement
    std::size_t surface_graph_edges = 0U;
    float maximum_surface_distance = 0.0F;
    std::vector<std::uint32_t> surface_graph_sources;
    std::vector<std::uint32_t> surface_graph_targets;
    std::vector<float> surface_graph_weights;
};

// Reproduce upstream Asset.from_data() followed by its Blender export: each
// source vertex receives inverse-distance interpolation from eight sampled
// points, then the greatest four learned joint weights are retained and
// normalized. This intentionally contains no geometric bone-distance gate.
skin integrate_learned_binding(
    const skeleton & target,
    std::span<const vec3> normalized_vertices,
    std::span<const vec3> sampled_points,
    std::span<const std::vector<float>> dense_joint_weights,
    binding_trace * trace = nullptr);

// Reproduce the optional postprocess used by the upstream demo: learned
// weights remain the signal, but are multiplied by a normalized surface-
// geodesic weight for each joint before the final top-four export. The
// upstream call does not pass parents to voxel_skin, so joints (rather than
// subdivided bones) seed the mesh graph.
skin integrate_postprocessed_binding(
    const skeleton & target,
    std::span<const vec3> normalized_vertices,
    std::span<const triangle> faces,
    std::span<const vec3> normalized_joints,
    std::span<const vec3> sampled_points,
    std::span<const std::vector<float>> dense_joint_weights,
    binding_trace * trace = nullptr);

skin integrate_postprocessed_binding_precise(
    const skeleton & target,
    std::span<const vec3> normalized_vertices,
    std::span<const precise_vec3> precise_vertices,
    std::span<const triangle> faces,
    std::span<const vec3> normalized_joints,
    std::span<const precise_vec3> precise_joints,
    std::span<const vec3> sampled_points,
    std::span<const std::vector<float>> dense_joint_weights,
    binding_trace * trace = nullptr);

} // namespace skintokens::detail
