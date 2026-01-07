// Scene instanced vertex shader
// Uses row-major matrices with row-vector math: mul(vector, matrix)

#pragma pack_matrix(row_major)

struct VSInput
{
    // Per-vertex data
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;

    // Per-instance data (rows from row-major matrix)
    float4 instanceRow0 : TEXCOORD3;  // Transform matrix row 0
    float4 instanceRow1 : TEXCOORD4;  // Transform matrix row 1
    float4 instanceRow2 : TEXCOORD5;  // Transform matrix row 2
    float4 instanceRow3 : TEXCOORD6;  // Transform matrix row 3 (translation)
    float4 instanceColor : TEXCOORD7; // Instance color/material
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float4 color : COLOR;
};

cbuffer CameraUniforms : register(b0)
{
    float4x4 viewProjection;
    float3 cameraPosition;
    float _pad0;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Reconstruct world matrix from instance rows
    float4x4 world = float4x4(
        input.instanceRow0,
        input.instanceRow1,
        input.instanceRow2,
        input.instanceRow3
    );

    // Row-vector transforms: pos * matrix
    float4 worldPos = mul(float4(input.position, 1.0), world);
    output.position = mul(worldPos, viewProjection);
    output.worldPos = worldPos.xyz;
    output.worldNormal = normalize(mul(input.normal, (float3x3)world));
    output.uv = input.uv;
    output.color = input.instanceColor;

    return output;
}
