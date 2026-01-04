// Shadow Depth Vertex Shader - Instanced Variant
// Renders depth only for shadow map generation with GPU instancing
// Uses row-major matrices with row-vector math: mul(vector, matrix)

#pragma pack_matrix(row_major)

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
    float4x4 g_LightViewProjection;
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

    // Row-vector transform: pos * model * lightVP
    float4 worldPos = mul(float4(input.position, 1.0), instanceTransform);
    output.position = mul(worldPos, g_LightViewProjection);

    return output;
}
