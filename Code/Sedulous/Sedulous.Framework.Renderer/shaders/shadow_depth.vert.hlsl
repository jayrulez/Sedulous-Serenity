// Shadow Depth Vertex Shader
// Renders depth only for shadow map generation
// Uses row-major matrices with row-vector math: mul(vector, matrix)
// No fragment shader needed - depth is written automatically from SV_Position.z

#pragma pack_matrix(row_major)

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;    // Not used but matches vertex layout
    float2 uv : TEXCOORD0;     // Not used but matches vertex layout
};

struct VSOutput
{
    float4 position : SV_Position;
};

// Shadow pass uniforms
cbuffer ShadowPassUniforms : register(b0)
{
    float4x4 g_LightViewProjection;
    float4 g_DepthBias;  // x=constant, y=slope, z=normal, w=unused
};

// Per-object transform
cbuffer ObjectUniforms : register(b1)
{
    float4x4 g_Model;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Row-vector transform: pos * model * lightVP
    float4 worldPos = mul(float4(input.position, 1.0), g_Model);
    output.position = mul(worldPos, g_LightViewProjection);

    return output;
}
