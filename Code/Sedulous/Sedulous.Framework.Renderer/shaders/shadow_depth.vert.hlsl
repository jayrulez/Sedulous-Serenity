// Shadow Depth Vertex Shader
// Renders depth only for shadow map generation
// No fragment shader needed - depth is written automatically from SV_Position.z

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
    column_major float4x4 g_LightViewProjection;
    float4 g_DepthBias;  // x=constant, y=slope, z=normal, w=unused
};

// Per-object transform
cbuffer ObjectUniforms : register(b1)
{
    column_major float4x4 g_Model;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    float4 worldPos = mul(g_Model, float4(input.position, 1.0));
    output.position = mul(g_LightViewProjection, worldPos);

    return output;
}
