// Unlit Material Vertex Shader
// Instanced rendering without lighting
// Uses row-major matrices with row-vector math: mul(vector, matrix)

#pragma pack_matrix(row_major)

struct VSInput
{
    // Per-vertex data (location 0-2)
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;

    // Per-instance data (location 3-7)
    float4 instanceRow0 : TEXCOORD3;     // Model matrix row 0
    float4 instanceRow1 : TEXCOORD4;     // Model matrix row 1
    float4 instanceRow2 : TEXCOORD5;     // Model matrix row 2
    float4 instanceRow3 : TEXCOORD6;     // Model matrix row 3
    float4 instanceData : TEXCOORD7;     // xyz=tint color, w=flags
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float3 tint : COLOR0;
};

// Camera uniform buffer (bind group 0, binding 0)
cbuffer CameraUniforms : register(b0, space0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Reconstruct model matrix from instance data rows
    float4x4 model = float4x4(
        input.instanceRow0,
        input.instanceRow1,
        input.instanceRow2,
        input.instanceRow3
    );

    float4 localPos = float4(input.position, 1.0);

    // Transform to world space (row-vector: pos * matrix)
    float4 worldPos = mul(localPos, model);

    output.uv = input.uv;
    output.tint = input.instanceData.xyz;

    // Transform to clip space (row-vector: pos * matrix)
    output.position = mul(worldPos, viewProjection);

    return output;
}
