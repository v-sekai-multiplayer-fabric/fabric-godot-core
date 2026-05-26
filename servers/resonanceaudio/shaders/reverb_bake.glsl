#version 460
layout(row_major) uniform;
layout(row_major) buffer;

#line 11 0
struct BakeParams_0
{
    uint ray_count_0;
    uint max_bounces_0;
    uint probe_count_0;
    uint triangle_count_0;
    uint ray_from_0;
    uint ray_to_0;
    float cell_size_0;
    int grid_size_0;
    vec3 grid_offset_0;
    float bias_0;
};


#line 45
layout(binding = 0)
layout(std140) uniform block_BakeParams_0
{
    uint ray_count_0;
    uint max_bounces_0;
    uint probe_count_0;
    uint triangle_count_0;
    uint ray_from_0;
    uint ray_to_0;
    float cell_size_0;
    int grid_size_0;
    vec3 grid_offset_0;
    float bias_0;
}params_0;

#line 48
layout(std430, binding = 3) readonly buffer StructuredBuffer_vectorx3Cfloatx2C4x3E_t_0 {
    vec4 _data[];
} probe_positions_0;

#line 29
struct Triangle_0
{
    uint i0_0;
    uint i1_0;
    uint i2_0;
    uint material_index_0;
};


#line 47
layout(std430, binding = 2) readonly buffer StructuredBuffer_Triangle_t_0 {
    Triangle_0 _data[];
} triangles_0;

#line 24
struct Vertex_0
{
    vec3 position_0;
    vec3 normal_0;
};


#line 46
layout(std430, binding = 1) readonly buffer StructuredBuffer_Vertex_t_0 {
    Vertex_0 _data[];
} vertices_0;

#line 36
struct MaterialAbsorption_0
{
    float  coefficients_0[9];
};


#line 49
layout(std430, binding = 4) readonly buffer StructuredBuffer_MaterialAbsorption_t_0 {
    MaterialAbsorption_0 _data[];
} materials_0;

#line 40
struct ProbeAccum_0
{
    float  absorbed_0[9];
    float total_hits_0;
};


#line 51
layout(std430, binding = 0, set = 1) buffer StructuredBuffer_ProbeAccum_t_0 {
    ProbeAccum_0 _data[];
} output_accum_0;
uint pcg_hash_0(uint state_0)
{

#line 55
    uint s_0 = state_0 * 747796405U + 2891336453U;
    uint word_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (word_0 >> 22U) ^ word_0;
}

float rand_float_0(inout uint state_1)
{

#line 61
    uint _S1 = pcg_hash_0(state_1);

#line 61
    state_1 = _S1;
    return float(_S1) / 4.294967296e+09;
}


vec3 random_sphere_direction_0(inout uint rng_0)
{

#line 67
    float _S2 = rand_float_0(rng_0);

#line 67
    float z_0 = 2.0 * _S2 - 1.0;
    float _S3 = rand_float_0(rng_0);

#line 68
    float phi_0 = 6.28318548202514648 * _S3;
    float r_0 = sqrt(max(0.0, 1.0 - z_0 * z_0));
    return vec3(r_0 * cos(phi_0), r_0 * sin(phi_0), z_0);
}


#line 80
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

#line 89
        return false;
    }

#line 90
    float f_0 = 1.0 / a_0;
    vec3 s_1 = ro_0 - v0_0;
    float u_0 = f_0 * dot(s_1, h_0);

#line 92
    bool _S4;
    if(u_0 < 0.0)
    {

#line 93
        _S4 = true;

#line 93
    }
    else
    {

#line 93
        _S4 = u_0 > 1.0;

#line 93
    }

#line 93
    if(_S4)
    {

#line 94
        return false;
    }

#line 95
    vec3 q_0 = cross(s_1, e1_0);
    float v_0 = f_0 * dot(rd_0, q_0);
    if(v_0 < 0.0)
    {

#line 97
        _S4 = true;

#line 97
    }
    else
    {

#line 97
        _S4 = (u_0 + v_0) > 1.0;

#line 97
    }

#line 97
    if(_S4)
    {

#line 98
        return false;
    }

#line 99
    float _S5 = f_0 * dot(e2_0, q_0);

#line 99
    t_0 = _S5;
    if(_S5 < 0.00000999999974738)
    {

#line 101
        return false;
    }

#line 102
    vec3 _S6 = normalize(cross(e1_0, e2_0));

#line 102
    normal_out_0 = _S6;
    if((dot(_S6, rd_0)) > 0.0)
    {

#line 104
        normal_out_0 = - normal_out_0;

#line 103
    }

    return true;
}


#line 74
vec3 random_cosine_direction_0(vec3 normal_1, inout uint rng_1)
{

#line 75
    vec3 dir_0 = random_sphere_direction_0(rng_1);
    return normalize(dir_0 + normal_1);
}


#line 109
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void main()
{

#line 110
    uint probe_index_0 = gl_GlobalInvocationID.x;
    if(probe_index_0 >= (params_0.probe_count_0))
    {

#line 112
        return;
    }
    vec3 _S7 = probe_positions_0._data[uint(probe_index_0)].xyz;
    uint rng_2 = pcg_hash_0(probe_index_0 * 1337U + params_0.ray_from_0 * 7919U);

    float  local_absorbed_0[9];

#line 117
    uint b_0 = 0U;
    for(;;)
    {

#line 118
        if(b_0 < 9U)
        {
        }
        else
        {

#line 118
            break;
        }

#line 119
        local_absorbed_0[b_0] = 0.0;

#line 118
        b_0 = b_0 + 1U;

#line 118
    }

#line 118
    uint ray_idx_0 = params_0.ray_from_0;

#line 118
    float local_hits_0 = 0.0;



    for(;;)
    {

#line 122
        if(ray_idx_0 < (params_0.ray_to_0))
        {
        }
        else
        {

#line 122
            break;
        }

#line 123
        vec3 _S8 = random_sphere_direction_0(rng_2);

#line 123
        vec3 ray_origin_0 = _S7;

#line 123
        vec3 ray_dir_0 = _S8;

#line 123
        uint bounce_0 = 0U;


        for(;;)
        {

#line 126
            if(bounce_0 < (params_0.max_bounces_0))
            {
            }
            else
            {

#line 126
                break;
            }

            const vec3 _S9 = vec3(0.0, 1.0, 0.0);

#line 129
            float best_t_0 = 1.00000001504746622e+30;

#line 129
            int best_tri_0 = -1;

#line 129
            vec3 best_normal_0 = _S9;

#line 129
            uint ti_0 = 0U;


            for(;;)
            {

#line 132
                if(ti_0 < (params_0.triangle_count_0))
                {
                }
                else
                {

#line 132
                    break;
                }

#line 133
                Triangle_0 tri_0 = triangles_0._data[uint(ti_0)];

#line 138
                float t_1;
                vec3 n_0;
                bool _S10 = ray_triangle_intersect_0(ray_origin_0, ray_dir_0, vertices_0._data[uint(tri_0.i0_0)].position_0, vertices_0._data[uint(tri_0.i1_0)].position_0, vertices_0._data[uint(tri_0.i2_0)].position_0, t_1, n_0);

#line 140
                if(_S10)
                {

#line 140
                    float best_t_1;

#line 140
                    vec3 best_normal_1;

#line 140
                    int best_tri_1;
                    if(t_1 < best_t_0)
                    {
                        int _S11 = int(ti_0);

#line 143
                        best_t_1 = t_1;

#line 143
                        best_tri_1 = _S11;

#line 143
                        best_normal_1 = n_0;

#line 141
                    }
                    else
                    {

#line 141
                        best_t_1 = best_t_0;

#line 141
                        best_tri_1 = best_tri_0;

#line 141
                        best_normal_1 = best_normal_0;

#line 141
                    }

#line 141
                    best_t_0 = best_t_1;

#line 141
                    best_tri_0 = best_tri_1;

#line 141
                    best_normal_0 = best_normal_1;

#line 140
                }

#line 132
                ti_0 = ti_0 + 1U;

#line 132
            }

#line 149
            if(best_tri_0 < 0)
            {

#line 150
                break;
            }
            Triangle_0 _S12 = triangles_0._data[uint(best_tri_0)];

#line 152
            b_0 = 0U;
            for(;;)
            {

#line 153
                if(b_0 < 9U)
                {
                }
                else
                {

#line 153
                    break;
                }

#line 154
                local_absorbed_0[b_0] = local_absorbed_0[b_0] + materials_0._data[uint(_S12.material_index_0)].coefficients_0[b_0];

#line 153
                b_0 = b_0 + 1U;

#line 153
            }


            float local_hits_1 = local_hits_0 + 1.0;

            vec3 _S13 = ray_origin_0 + ray_dir_0 * best_t_0 + best_normal_0 * params_0.bias_0;
            vec3 _S14 = random_cosine_direction_0(best_normal_0, rng_2);

#line 126
            uint _S15 = bounce_0 + 1U;

#line 126
            ray_origin_0 = _S13;

#line 126
            ray_dir_0 = _S14;

#line 126
            bounce_0 = _S15;

#line 126
            local_hits_0 = local_hits_1;

#line 126
        }

#line 122
        ray_idx_0 = ray_idx_0 + 1U;

#line 122
    }

#line 122
    b_0 = 0U;

#line 164
    for(;;)
    {

#line 164
        if(b_0 < 9U)
        {
        }
        else
        {

#line 164
            break;
        }

#line 165
        output_accum_0._data[uint(probe_index_0)].absorbed_0[b_0] = output_accum_0._data[uint(probe_index_0)].absorbed_0[b_0] + local_absorbed_0[b_0];

#line 164
        b_0 = b_0 + 1U;

#line 164
    }


    output_accum_0._data[uint(probe_index_0)].total_hits_0 = output_accum_0._data[uint(probe_index_0)].total_hits_0 + local_hits_0;
    return;
}

