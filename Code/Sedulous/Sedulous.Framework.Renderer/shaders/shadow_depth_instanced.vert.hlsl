// Shadow Depth Vertex Shader - Instanced Variant
// Renders depth only for shadow map generation with GPU instancing

struct VSInput
{
    // Vertex data
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;

    // Instance data (per-instance transform matrix as 4 rows)
    float4 instanceRow0 : TEXCOORD3;
    float4 instanceRow1 : TEXCOORD4;
    float4 instanceRow2 : TEXCOORD5;
    float4 instanceRow3 : TEXCOORD6;
};

struct VSOutput
{
    float4 position : SV_Position;
};

// Shadow pass uniforms
cbuffer ShadowPassUniforms : register(b0)
{
    column_major float4x4 g_LightViewProjection;
    float4 g_DepthBias;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Reconstruct instance transform matrix from rows
    float4x4 instanceTransform = float4x4(
        input.instanceRow0,
        input.instanceRow1,
        input.instanceRow2,
        input.instanceRow3
    );

    float4 worldPos = mul(instanceTransform, float4(input.position, 1.0));
    output.position = mul(g_LightViewProjection, worldPos);

    return output;
}
