#include "C:/Users/ernest.lee/scoop/apps/slang/current/include/slang-cpp-prelude.h"

#ifdef SLANG_PRELUDE_NAMESPACE
using namespace SLANG_PRELUDE_NAMESPACE;
#endif


#line 11 "E:/multiplayer-fabric-godot/servers/resonanceaudio/shaders/reverb_bake.slang"
struct BakeParams_0
{
    uint32_t ray_count_0;
    uint32_t max_bounces_0;
    uint32_t probe_count_0;
    uint32_t triangle_count_0;
    uint32_t ray_from_0;
    uint32_t ray_to_0;
    float cell_size_0;
    int32_t grid_size_0;
    Vector<float, 3>  grid_offset_0;
    float bias_0;
};


#line 24
struct Vertex_0
{
    Vector<float, 3>  position_0;
    Vector<float, 3>  normal_0;
};


#line 29
struct Triangle_0
{
    uint32_t i0_0;
    uint32_t i1_0;
    uint32_t i2_0;
    uint32_t material_index_0;
};


#line 36
struct MaterialAbsorption_0
{
    FixedArray<float, 9>  coefficients_0;
};


#line 40
struct ProbeAccum_0
{
    FixedArray<float, 9>  absorbed_0;
    float total_hits_0;
};


#line 165
struct GlobalParams_0
{
    BakeParams_0* params_0;
    StructuredBuffer<Vertex_0> vertices_0;
    StructuredBuffer<Triangle_0> triangles_0;
    StructuredBuffer<Vector<float, 4> > probe_positions_0;
    StructuredBuffer<MaterialAbsorption_0> materials_0;
    StructuredBuffer<uint32_t> grid_indices_0;
    RWStructuredBuffer<ProbeAccum_0> output_accum_0;
};


#line 165
struct KernelContext_0
{
    GlobalParams_0* globalParams_0;
};


#line 9865 "hlsl.meta.slang"
static float dot_0(Vector<float, 3>  x_0, Vector<float, 3>  y_0)
{

#line 9865
    int32_t i_0 = int(0);

#line 9865
    float result_0 = 0.0f;

#line 9884
    for(;;)
    {

#line 9884
        if(i_0 < int(3))
        {
        }
        else
        {

#line 9884
            break;
        }

#line 9885
        float result_1 = result_0 + _slang_vector_get_element(x_0, i_0) * _slang_vector_get_element(y_0, i_0);

#line 9884
        i_0 = i_0 + int(1);

#line 9884
        result_0 = result_1;

#line 9884
    }

    return result_0;
}


#line 12120
static float length_0(Vector<float, 3>  x_1)
{

#line 12132
    return (F32_sqrt((dot_0(x_1, x_1))));
}


#line 13723
static Vector<float, 3>  normalize_0(Vector<float, 3>  x_2)
{

#line 13735
    return x_2 / (Vector<float, 3> )length_0(x_2);
}


#line 9310
static Vector<float, 3>  cross_0(Vector<float, 3>  left_0, Vector<float, 3>  right_0)
{

#line 9324
    float _S1 = left_0.y;

#line 9324
    float _S2 = right_0.z;

#line 9324
    float _S3 = left_0.z;

#line 9324
    float _S4 = right_0.y;
    float _S5 = right_0.x;

#line 9325
    float _S6 = left_0.x;

#line 9323
    return Vector<float, 3> (_S1 * _S2 - _S3 * _S4, _S3 * _S5 - _S6 * _S2, _S6 * _S4 - _S1 * _S5);
}


#line 54 "E:/multiplayer-fabric-godot/servers/resonanceaudio/shaders/reverb_bake.slang"
static uint32_t pcg_hash_0(uint32_t state_0)
{

#line 55
    uint32_t s_0 = state_0 * 747796405U + 2891336453U;
    uint32_t word_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (word_0 >> 22U) ^ word_0;
}

static float rand_float_0(uint32_t * state_1)
{

#line 61
    uint32_t _S7 = pcg_hash_0(*state_1);

#line 61
    *state_1 = _S7;
    return float(_S7) / 4.294967296e+09f;
}


static Vector<float, 3>  random_sphere_direction_0(uint32_t * rng_0)
{

#line 67
    float _S8 = rand_float_0(rng_0);

#line 67
    float z_0 = 2.0f * _S8 - 1.0f;
    float _S9 = rand_float_0(rng_0);

#line 68
    float phi_0 = 6.28318548202514648f * _S9;
    float r_0 = (F32_sqrt(((F32_max((0.0f), (1.0f - z_0 * z_0))))));
    return Vector<float, 3> (r_0 * (F32_cos((phi_0))), r_0 * (F32_sin((phi_0))), z_0);
}


#line 80
static bool ray_triangle_intersect_0(Vector<float, 3>  ro_0, Vector<float, 3>  rd_0, Vector<float, 3>  v0_0, Vector<float, 3>  v1_0, Vector<float, 3>  v2_0, float * t_0, Vector<float, 3>  * normal_out_0)
{
    *t_0 = 0.0f;
    *normal_out_0 = Vector<float, 3> (0.0f, 0.0f, 0.0f);
    Vector<float, 3>  e1_0 = v1_0 - v0_0;
    Vector<float, 3>  e2_0 = v2_0 - v0_0;
    Vector<float, 3>  h_0 = cross_0(rd_0, e2_0);
    float a_0 = dot_0(e1_0, h_0);
    if((F32_abs((a_0))) < 9.99999993922529029e-09f)
    {

#line 89
        return false;
    }

#line 90
    float f_0 = 1.0f / a_0;
    Vector<float, 3>  s_1 = ro_0 - v0_0;
    float u_0 = f_0 * dot_0(s_1, h_0);

#line 92
    bool _S10;
    if(u_0 < 0.0f)
    {

#line 93
        _S10 = true;

#line 93
    }
    else
    {

#line 93
        _S10 = u_0 > 1.0f;

#line 93
    }

#line 93
    if(_S10)
    {

#line 94
        return false;
    }

#line 95
    Vector<float, 3>  q_0 = cross_0(s_1, e1_0);
    float v_0 = f_0 * dot_0(rd_0, q_0);
    if(v_0 < 0.0f)
    {

#line 97
        _S10 = true;

#line 97
    }
    else
    {

#line 97
        _S10 = (u_0 + v_0) > 1.0f;

#line 97
    }

#line 97
    if(_S10)
    {

#line 98
        return false;
    }

#line 99
    float _S11 = f_0 * dot_0(e2_0, q_0);

#line 99
    *t_0 = _S11;
    if(_S11 < 0.00000999999974738f)
    {

#line 101
        return false;
    }

#line 102
    Vector<float, 3>  _S12 = normalize_0(cross_0(e1_0, e2_0));

#line 102
    *normal_out_0 = _S12;
    if((dot_0(_S12, rd_0)) > 0.0f)
    {

#line 104
        *normal_out_0 = - *normal_out_0;

#line 103
    }

    return true;
}


#line 74
static Vector<float, 3>  random_cosine_direction_0(Vector<float, 3>  normal_1, uint32_t * rng_1)
{

#line 75
    Vector<float, 3>  dir_0 = random_sphere_direction_0(rng_1);
    return normalize_0(dir_0 + normal_1);
}


#line 109
void _main_0(void* _S13, void* entryPointParams_0, void* globalParams_1)
{

#line 109
    ComputeThreadVaryingInput * _S14 = (slang_bit_cast<ComputeThreadVaryingInput *>(_S13));

#line 109
    KernelContext_0 kernelContext_0;

#line 109
    (&kernelContext_0)->globalParams_0 = (slang_bit_cast<GlobalParams_0*>(globalParams_1));
    uint32_t probe_index_0 = (_S14->groupID * Vector<uint32_t, 3> (64U, 1U, 1U) + _S14->groupThreadID).x;
    if(probe_index_0 >= ((slang_bit_cast<GlobalParams_0*>(globalParams_1))->params_0->probe_count_0))
    {

#line 112
        return;
    }
    Vector<float, 3>  _S15 = Vector<float, 3> {(&kernelContext_0)->globalParams_0->probe_positions_0.Load(probe_index_0).x, (&kernelContext_0)->globalParams_0->probe_positions_0.Load(probe_index_0).y, (&kernelContext_0)->globalParams_0->probe_positions_0.Load(probe_index_0).z};
    uint32_t rng_2 = pcg_hash_0(probe_index_0 * 1337U + (slang_bit_cast<GlobalParams_0*>(globalParams_1))->params_0->ray_from_0 * 7919U);

    FixedArray<float, 9>  local_absorbed_0;

#line 117
    uint32_t b_0 = 0U;
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
        local_absorbed_0[b_0] = 0.0f;

#line 118
        b_0 = b_0 + 1U;

#line 118
    }

#line 118
    uint32_t ray_idx_0 = (slang_bit_cast<GlobalParams_0*>(globalParams_1))->params_0->ray_from_0;

#line 118
    float local_hits_0 = 0.0f;



    for(;;)
    {

#line 122
        if(ray_idx_0 < ((slang_bit_cast<GlobalParams_0*>(globalParams_1))->params_0->ray_to_0))
        {
        }
        else
        {

#line 122
            break;
        }

#line 123
        Vector<float, 3>  _S16 = random_sphere_direction_0(&rng_2);

#line 123
        Vector<float, 3>  ray_origin_0 = _S15;

#line 123
        Vector<float, 3>  ray_dir_0 = _S16;

#line 123
        uint32_t bounce_0 = 0U;


        for(;;)
        {

#line 126
            if(bounce_0 < ((slang_bit_cast<GlobalParams_0*>(globalParams_1))->params_0->max_bounces_0))
            {
            }
            else
            {

#line 126
                break;
            }

            Vector<float, 3>  _S17 = Vector<float, 3> (0.0f, 1.0f, 0.0f);

#line 129
            float best_t_0 = 1.00000001504746622e+30f;

#line 129
            int32_t best_tri_0 = int(-1);

#line 129
            Vector<float, 3>  best_normal_0 = _S17;

#line 129
            uint32_t ti_0 = 0U;


            for(;;)
            {

#line 132
                if(ti_0 < ((slang_bit_cast<GlobalParams_0*>(globalParams_1))->params_0->triangle_count_0))
                {
                }
                else
                {

#line 132
                    break;
                }

#line 133
                Triangle_0 tri_0 = (&kernelContext_0)->globalParams_0->triangles_0.Load(ti_0);

#line 138
                float t_1;
                Vector<float, 3>  n_0;
                bool _S18 = ray_triangle_intersect_0(ray_origin_0, ray_dir_0, (&kernelContext_0)->globalParams_0->vertices_0.Load(tri_0.i0_0).position_0, (&kernelContext_0)->globalParams_0->vertices_0.Load(tri_0.i1_0).position_0, (&kernelContext_0)->globalParams_0->vertices_0.Load(tri_0.i2_0).position_0, &t_1, &n_0);

#line 140
                if(_S18)
                {

#line 140
                    float best_t_1;

#line 140
                    Vector<float, 3>  best_normal_1;

#line 140
                    int32_t best_tri_1;
                    if(t_1 < best_t_0)
                    {
                        int32_t _S19 = int32_t(ti_0);

#line 143
                        best_t_1 = t_1;

#line 143
                        best_tri_1 = _S19;

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
            if(best_tri_0 < int(0))
            {

#line 150
                break;
            }
            Triangle_0 _S20 = (&kernelContext_0)->globalParams_0->triangles_0.Load(best_tri_0);

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
                local_absorbed_0[b_0] = local_absorbed_0[b_0] + (&((&kernelContext_0)->globalParams_0->materials_0)[_S20.material_index_0])->coefficients_0[b_0];

#line 153
                b_0 = b_0 + 1U;

#line 153
            }


            float local_hits_1 = local_hits_0 + 1.0f;

            Vector<float, 3>  _S21 = ray_origin_0 + ray_dir_0 * (Vector<float, 3> )best_t_0 + best_normal_0 * (Vector<float, 3> )(slang_bit_cast<GlobalParams_0*>(globalParams_1))->params_0->bias_0;
            Vector<float, 3>  _S22 = random_cosine_direction_0(best_normal_0, &rng_2);

#line 126
            uint32_t _S23 = bounce_0 + 1U;

#line 126
            ray_origin_0 = _S21;

#line 126
            ray_dir_0 = _S22;

#line 126
            bounce_0 = _S23;

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
        (&((&kernelContext_0)->globalParams_0->output_accum_0)[probe_index_0])->absorbed_0[b_0] = (&((&kernelContext_0)->globalParams_0->output_accum_0)[probe_index_0])->absorbed_0[b_0] + local_absorbed_0[b_0];

#line 164
        b_0 = b_0 + 1U;

#line 164
    }


    (&((&kernelContext_0)->globalParams_0->output_accum_0)[probe_index_0])->total_hits_0 = (&((&kernelContext_0)->globalParams_0->output_accum_0)[probe_index_0])->total_hits_0 + local_hits_0;
    return;
}

// [numthreads(64, 1, 1)]
SLANG_PRELUDE_EXPORT
void main_0_Thread(ComputeThreadVaryingInput* varyingInput, void* entryPointParams, void* globalParams)
{
    _main_0(varyingInput, entryPointParams, globalParams);
}
// [numthreads(64, 1, 1)]
SLANG_PRELUDE_EXPORT
void main_0_Group(ComputeVaryingInput* varyingInput, void* entryPointParams, void* globalParams)
{
    ComputeThreadVaryingInput threadInput = {};
    threadInput.groupID = varyingInput->startGroupID;
    for (uint32_t x = 0; x < 64; ++x)
    {
        threadInput.groupThreadID.x = x;
        _main_0(&threadInput, entryPointParams, globalParams);
    }
}
// [numthreads(64, 1, 1)]
SLANG_PRELUDE_EXPORT
void main_0(ComputeVaryingInput* varyingInput, void* entryPointParams, void* globalParams)
{
    ComputeVaryingInput vi = *varyingInput;
    ComputeVaryingInput groupVaryingInput = {};
    for (uint32_t z = vi.startGroupID.z; z < vi.endGroupID.z; ++z)
    {
        groupVaryingInput.startGroupID.z = z;
        for (uint32_t y = vi.startGroupID.y; y < vi.endGroupID.y; ++y)
        {
            groupVaryingInput.startGroupID.y = y;
            for (uint32_t x = vi.startGroupID.x; x < vi.endGroupID.x; ++x)
            {
                groupVaryingInput.startGroupID.x = x;
                main_0_Group(&groupVaryingInput, entryPointParams, globalParams);
            }
        }
    }
}
