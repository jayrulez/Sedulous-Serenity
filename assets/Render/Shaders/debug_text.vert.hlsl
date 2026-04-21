// Debug text vertex shader
// Transforms world-space text quads and passes through UVs

#pragma pack_matrix(row_major)

cbuffer Camera : register(b0)
{
    float4x4 viewProjection;
};

struct VSInput
{
    float3 position : TEXCOORD0;
    float2 texCoord : TEXCOORD1;
    float4 color : TEXCOORD2;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD0;
    float4 color : COLOR;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    output.position = mul(float4(input.position, 1.0), viewProjection);
    output.texCoord = input.texCoord;
    output.color = input.color;
    return output;
}
