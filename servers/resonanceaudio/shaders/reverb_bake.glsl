#version 460
layout(row_major) uniform;
layout(row_major) buffer;

#line 12 0
struct BakeParams_0
{
    uint ray_count_0;
    uint max_bounces_0;
    uint probe_count_0;
    uint triangle_count_0;
    uint ray_from_0;
    uint ray_to_0;
    vec3 to_cell_offset_0;
    int grid_size_0;
    vec3 to_cell_size_0;
    float bias_0;
};


#line 82
layout(binding = 0)
layout(std140) uniform block_BakeParams_0
{
    uint ray_count_0;
    uint max_bounces_0;
    uint probe_count_0;
    uint triangle_count_0;
    uint ray_from_0;
    uint ray_to_0;
    vec3 to_cell_offset_0;
    int grid_size_0;
    vec3 to_cell_size_0;
    float bias_0;
}params_0;

#line 53
struct ProbePosition_0
{
    vec3 position_0;
    float pad0_0;
    vec3 position_lo_0;
    float pad1_0;
};


#line 85
layout(std430, binding = 3) readonly buffer StructuredBuffer_ProbePosition_t_0 {
    ProbePosition_0 _data[];
} probe_positions_0;

#line 87
layout(std430, binding = 5) readonly buffer StructuredBuffer_vectorx3Cuintx2C2x3E_t_0 {
    uvec2 _data[];
} grid_data_0;

#line 88
layout(std430, binding = 6) readonly buffer StructuredBuffer_vectorx3Cuintx2C2x3E_t_1 {
    uvec2 _data[];
} cluster_indices_0;

#line 41
struct ClusterAABB_0
{
    vec3 min_bounds_0;
    float pad0_1;
    vec3 max_bounds_0;
    float pad1_1;
};


#line 89
layout(std430, binding = 7) readonly buffer StructuredBuffer_ClusterAABB_t_0 {
    ClusterAABB_0 _data[];
} cluster_aabbs_0;

#line 90
layout(std430, binding = 8) readonly buffer StructuredBuffer_uint_t_0 {
    uint _data[];
} triangle_indices_0;

#line 30
struct Triangle_0
{
    uint i0_0;
    uint i1_0;
    uint i2_0;
    uint material_index_0;
};


#line 84
layout(std430, binding = 2) readonly buffer StructuredBuffer_Triangle_t_0 {
    Triangle_0 _data[];
} triangles_0;

#line 25
struct Vertex_0
{
    vec3 position_1;
    vec3 position_lo_1;
};


#line 83
layout(std430, binding = 1) readonly buffer StructuredBuffer_Vertex_t_0 {
    Vertex_0 _data[];
} vertices_0;

#line 37
struct MaterialAbsorption_0
{
    float  coefficients_0[9];
};


#line 86
layout(std430, binding = 4) readonly buffer StructuredBuffer_MaterialAbsorption_t_0 {
    MaterialAbsorption_0 _data[];
} materials_0;

#line 48
struct ProbeAccum_0
{
    float  absorbed_0[9];
    float total_hits_0;
};


#line 91
layout(std430, binding = 0, set = 1) buffer StructuredBuffer_ProbeAccum_t_0 {
    ProbeAccum_0 _data[];
} output_accum_0;

#line 93
uint pcg_hash_0(uint state_0)
{

#line 94
    uint s_0 = state_0 * 747796405U + 2891336453U;
    uint word_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (word_0 >> 22U) ^ word_0;
}

float rand_float_0(inout uint state_1)
{

#line 100
    uint _S1 = pcg_hash_0(state_1);

#line 100
    state_1 = _S1;
    return float(_S1) / 4.294967296e+09;
}

vec3 random_sphere_direction_0(inout uint rng_0)
{

#line 105
    float _S2 = rand_float_0(rng_0);

#line 105
    float z_0 = 2.0 * _S2 - 1.0;
    float _S3 = rand_float_0(rng_0);

#line 106
    float phi_0 = 6.28318548202514648 * _S3;
    float r_0 = sqrt(max(0.0, 1.0 - z_0 * z_0));
    return vec3(r_0 * cos(phi_0), r_0 * sin(phi_0), z_0);
}


#line 144
bool ray_box_test_0(vec3 origin_0, vec3 inv_dir_0, vec3 box_min_0, vec3 box_max_0)
{

#line 145
    vec3 t0_0 = (box_min_0 - origin_0) * inv_dir_0;
    vec3 t1_0 = (box_max_0 - origin_0) * inv_dir_0;
    vec3 tmin_0 = min(t0_0, t1_0);
    vec3 tmax_0 = max(t0_0, t1_0);

    float _S4 = min(min(tmax_0.x, tmax_0.y), tmax_0.z);

#line 150
    bool _S5;
    if((max(max(tmin_0.x, tmin_0.y), tmin_0.z)) <= _S4)
    {

#line 151
        _S5 = _S4 >= 0.0;

#line 151
    }
    else
    {

#line 151
        _S5 = false;

#line 151
    }

#line 151
    return _S5;
}


#line 116
bool ray_triangle_intersect_0(vec3 ro_0, vec3 rd_0, vec3 v0_0, vec3 v1_0, vec3 v2_0, out float t_0, out vec3 normal_out_0)
{
    t_0 = 0.0;
    normal_out_0 = vec3(0.0, 0.0, 0.0);
    vec3 e1_0 = v1_0 - v0_0;
    vec3 e2_0 = v2_0 - v0_0;
    vec3 h_0 = cross(rd_0, e2_0);
    float a_0 = dot(e1_0, h_0);
    if((abs(a_0)) < 9.99999993922529029e-09)
    {

#line 125
        return false;
    }

#line 126
    float f_0 = 1.0 / a_0;
    vec3 s_1 = ro_0 - v0_0;
    float u_0 = f_0 * dot(s_1, h_0);

#line 128
    bool _S6;
    if(u_0 < 0.0)
    {

#line 129
        _S6 = true;

#line 129
    }
    else
    {

#line 129
        _S6 = u_0 > 1.0;

#line 129
    }

#line 129
    if(_S6)
    {

#line 130
        return false;
    }

#line 131
    vec3 q_0 = cross(s_1, e1_0);
    float v_0 = f_0 * dot(rd_0, q_0);
    if(v_0 < 0.0)
    {

#line 133
        _S6 = true;

#line 133
    }
    else
    {

#line 133
        _S6 = (u_0 + v_0) > 1.0;

#line 133
    }

#line 133
    if(_S6)
    {

#line 134
        return false;
    }

#line 135
    float _S7 = f_0 * dot(e2_0, q_0);

#line 135
    t_0 = _S7;
    if(_S7 < 0.00000999999974738)
    {

#line 137
        return false;
    }

#line 138
    vec3 _S8 = normalize(cross(e1_0, e2_0));

#line 138
    normal_out_0 = _S8;
    if((dot(_S8, rd_0)) > 0.0)
    {

#line 140
        normal_out_0 = - normal_out_0;

#line 139
    }

    return true;
}


#line 155
bool trace_ray_grid_0(vec3 ray_origin_0, vec3 ray_dir_0, out float hit_t_0, out uint hit_tri_0)
{

#line 156
    hit_t_0 = 1.00000001504746622e+30;
    hit_tri_0 = 4294967295U;

    vec3 _S9 = 1.0 / ray_dir_0;
    int gs_0 = params_0.grid_size_0;


    vec3 from_cell_0 = (ray_origin_0 - params_0.to_cell_offset_0) * params_0.to_cell_size_0;
    ivec3 _S10 = ivec3(floor(from_cell_0));

#line 164
    ivec3 icell_0 = _S10;


    ivec3 step_0 = (ivec3(sign((ray_dir_0))));
    vec3 dir_cell_0 = normalize(ray_dir_0 * (1.0 / params_0.to_cell_size_0));
    vec3 _S11 = min(abs(1.0 / dir_cell_0), vec3(float(params_0.grid_size_0)));

    vec3 t_max_0 = (vec3(_S10) + max(vec3(0.0, 0.0, 0.0), vec3(step_0)) - from_cell_0) / dir_cell_0;


    int _S12 = step_0.x;

#line 174
    if(_S12 == 0)
    {

#line 174
        t_max_0[0] = 1.00000001504746622e+30;

#line 174
    }
    int _S13 = step_0.y;

#line 175
    if(_S13 == 0)
    {

#line 175
        t_max_0[1] = 1.00000001504746622e+30;

#line 175
    }
    int _S14 = step_0.z;

#line 176
    if(_S14 == 0)
    {

#line 176
        t_max_0[2] = 1.00000001504746622e+30;

#line 176
    }

#line 176
    uint iters_0 = 0U;


    for(;;)
    {

#line 179
        bool _S15;

#line 179
        if((all(bvec3((greaterThanEqual(icell_0,ivec3(0, 0, 0)))))))
        {

#line 179
            _S15 = (all(bvec3((lessThan(icell_0,ivec3(gs_0, gs_0, gs_0))))));

#line 179
        }
        else
        {

#line 179
            _S15 = false;

#line 179
        }

#line 179
        bool _S16;

#line 179
        if(_S15)
        {

#line 179
            _S16 = iters_0 < 1000U;

#line 179
        }
        else
        {

#line 179
            _S16 = false;

#line 179
        }

#line 179
        if(_S16)
        {
        }
        else
        {

#line 179
            break;
        }
        uvec2 cell_data_0 = grid_data_0._data[uint(uint(icell_0.x + icell_0.y * gs_0 + icell_0.z * gs_0 * gs_0))];
        uint tri_count_0 = cell_data_0.x;

        if(tri_count_0 > 0U)
        {

#line 185
            uint cell_solid_index_0 = cell_data_0.y;
            uint _S17 = cluster_indices_0._data[uint(cell_solid_index_0)].x;
            uint _S18 = cluster_indices_0._data[uint(cell_solid_index_0)].y;
            uint _S19 = (tri_count_0 + 32U - 1U) / 32U;

#line 188
            uint ci_0 = 0U;

            for(;;)
            {

#line 190
                if(ci_0 < _S19)
                {
                }
                else
                {

#line 190
                    break;
                }

#line 191
                ClusterAABB_0 ca_0 = cluster_aabbs_0._data[uint(_S17 + ci_0)];
                if(!ray_box_test_0(ray_origin_0, _S9, ca_0.min_bounds_0, ca_0.max_bounds_0))
                {

#line 193
                    ci_0 = ci_0 + 1U;

#line 190
                    continue;
                }



                uint tri_base_0 = ci_0 * 32U;
                uint _S20 = min(32U, tri_count_0 - tri_base_0);

#line 196
                uint ti_0 = 0U;
                for(;;)
                {

#line 197
                    if(ti_0 < _S20)
                    {
                    }
                    else
                    {

#line 197
                        break;
                    }

#line 198
                    uint tri_idx_0 = triangle_indices_0._data[uint(_S18 + tri_base_0 + ti_0)];
                    Triangle_0 tri_0 = triangles_0._data[uint(tri_idx_0)];

#line 205
                    float t_1;
                    vec3 n_0;
                    bool _S21 = ray_triangle_intersect_0(ray_origin_0, ray_dir_0, vertices_0._data[uint(tri_0.i0_0)].position_1, vertices_0._data[uint(tri_0.i1_0)].position_1, vertices_0._data[uint(tri_0.i2_0)].position_1, t_1, n_0);

#line 207
                    bool _S22;

#line 207
                    if(_S21)
                    {

#line 207
                        _S22 = t_1 < hit_t_0;

#line 207
                    }
                    else
                    {

#line 207
                        _S22 = false;

#line 207
                    }

#line 207
                    if(_S22)
                    {

#line 208
                        hit_t_0 = t_1;
                        hit_tri_0 = tri_idx_0;

#line 207
                    }

#line 197
                    ti_0 = ti_0 + 1U;

#line 197
                }

#line 190
                ci_0 = ci_0 + 1U;

#line 190
            }

#line 184
        }

#line 216
        if((t_max_0.x) < (t_max_0.y))
        {

#line 217
            if((t_max_0.x) < (t_max_0.z))
            {

#line 218
                icell_0[0] = icell_0[0] + _S12;
                t_max_0[0] = t_max_0[0] + _S11.x;

#line 217
            }
            else
            {

                icell_0[2] = icell_0[2] + _S14;
                t_max_0[2] = t_max_0[2] + _S11.z;

#line 217
            }

#line 216
        }
        else
        {

#line 225
            if((t_max_0.y) < (t_max_0.z))
            {

#line 226
                icell_0[1] = icell_0[1] + _S13;
                t_max_0[1] = t_max_0[1] + _S11.y;

#line 225
            }
            else
            {

                icell_0[2] = icell_0[2] + _S14;
                t_max_0[2] = t_max_0[2] + _S11.z;

#line 225
            }

#line 216
        }

#line 233
        uint _S23 = iters_0 + 1U;


        if(hit_tri_0 != 4294967295U)
        {

            if(hit_t_0 < (min(min(t_max_0.x, t_max_0.y), t_max_0.z) / length(params_0.to_cell_size_0)))
            {

#line 240
                break;
            }

#line 236
        }

#line 236
        iters_0 = _S23;

#line 179
    }

#line 244
    return hit_tri_0 != 4294967295U;
}


#line 111
vec3 random_cosine_direction_0(vec3 normal_0, inout uint rng_1)
{

#line 112
    vec3 dir_0 = random_sphere_direction_0(rng_1);
    return normalize(dir_0 + normal_0);
}


#line 248
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void main()
{

#line 249
    uint probe_index_0 = gl_GlobalInvocationID.x;
    if(probe_index_0 >= (params_0.probe_count_0))
    {

#line 251
        return;
    }

    vec3 _S24 = probe_positions_0._data[uint(probe_index_0)].position_0 + probe_positions_0._data[uint(probe_index_0)].position_lo_0;
    uint rng_2 = pcg_hash_0(probe_index_0 * 1337U + params_0.ray_from_0 * 7919U);

    float  local_absorbed_0[9];

#line 257
    uint b_0 = 0U;
    for(;;)
    {

#line 258
        if(b_0 < 9U)
        {
        }
        else
        {

#line 258
            break;
        }

#line 259
        local_absorbed_0[b_0] = 0.0;

#line 258
        b_0 = b_0 + 1U;

#line 258
    }

#line 258
    uint ray_idx_0 = params_0.ray_from_0;

#line 258
    float local_hits_0 = 0.0;



    for(;;)
    {

#line 262
        if(ray_idx_0 < (params_0.ray_to_0))
        {
        }
        else
        {

#line 262
            break;
        }

#line 263
        vec3 _S25 = random_sphere_direction_0(rng_2);

#line 263
        vec3 ray_origin_1 = _S24;

#line 263
        vec3 ray_dir_1 = _S25;

#line 263
        uint bounce_0 = 0U;

#line 263
        float local_hits_1 = local_hits_0;


        for(;;)
        {

#line 266
            if(bounce_0 < (params_0.max_bounces_0))
            {
            }
            else
            {

#line 266
                local_hits_0 = local_hits_1;

#line 266
                break;
            }

#line 267
            float hit_t_1;
            uint hit_tri_1;
            bool _S26 = trace_ray_grid_0(ray_origin_1, ray_dir_1, hit_t_1, hit_tri_1);

#line 269
            if(!_S26)
            {

#line 269
                local_hits_0 = local_hits_1;
                break;
            }
            Triangle_0 _S27 = triangles_0._data[uint(hit_tri_1)];

#line 272
            float max_alpha_0 = 0.0;

#line 272
            b_0 = 0U;

            for(;;)
            {

#line 274
                if(b_0 < 9U)
                {
                }
                else
                {

#line 274
                    break;
                }

#line 274
                float alpha_0 = materials_0._data[uint(_S27.material_index_0)].coefficients_0[b_0];

                local_absorbed_0[b_0] = local_absorbed_0[b_0] + materials_0._data[uint(_S27.material_index_0)].coefficients_0[b_0];
                if((materials_0._data[uint(_S27.material_index_0)].coefficients_0[b_0]) > max_alpha_0)
                {

#line 277
                    max_alpha_0 = alpha_0;

#line 277
                }

#line 274
                b_0 = b_0 + 1U;

#line 274
            }

#line 279
            float local_hits_2 = local_hits_1 + 1.0;



            if(bounce_0 > 4U)
            {

#line 284
                float _S28 = max(1.0 - max_alpha_0, 0.05000000074505806);
                float _S29 = rand_float_0(rng_2);

#line 285
                if(_S29 > _S28)
                {

#line 285
                    local_hits_0 = local_hits_2;
                    break;
                }

#line 283
            }

#line 290
            Triangle_0 tri_1 = triangles_0._data[uint(hit_tri_1)];
            Vertex_0 _S30 = vertices_0._data[uint(tri_1.i0_0)];


            vec3 hit_normal_0 = normalize(cross(vertices_0._data[uint(tri_1.i1_0)].position_1 - _S30.position_1, vertices_0._data[uint(tri_1.i2_0)].position_1 - _S30.position_1));

#line 294
            vec3 hit_normal_1;
            if((dot(hit_normal_0, ray_dir_1)) > 0.0)
            {

#line 295
                hit_normal_1 = - hit_normal_0;

#line 295
            }
            else
            {

#line 295
                hit_normal_1 = hit_normal_0;

#line 295
            }


            vec3 _S31 = ray_origin_1 + ray_dir_1 * hit_t_1 + hit_normal_1 * params_0.bias_0;
            vec3 _S32 = random_cosine_direction_0(hit_normal_1, rng_2);

#line 266
            uint _S33 = bounce_0 + 1U;

#line 266
            ray_origin_1 = _S31;

#line 266
            ray_dir_1 = _S32;

#line 266
            bounce_0 = _S33;

#line 266
            local_hits_1 = local_hits_2;

#line 266
        }

#line 262
        ray_idx_0 = ray_idx_0 + 1U;

#line 262
    }

#line 262
    b_0 = 0U;

#line 303
    for(;;)
    {

#line 303
        if(b_0 < 9U)
        {
        }
        else
        {

#line 303
            break;
        }

#line 304
        output_accum_0._data[uint(probe_index_0)].absorbed_0[b_0] = output_accum_0._data[uint(probe_index_0)].absorbed_0[b_0] + local_absorbed_0[b_0];

#line 303
        b_0 = b_0 + 1U;

#line 303
    }


    output_accum_0._data[uint(probe_index_0)].total_hits_0 = output_accum_0._data[uint(probe_index_0)].total_hits_0 + local_hits_0;
    return;
}

