// Debug drawing vertex shader
// Transforms world-space positions using view-projection matrix

#pragma pack_matrix(row_major)

cbuffer Camera : register(b0)
{
    float4x4 viewProjection;
};

struct VSInput
{
    float3 position : TEXCOORD0;
    float4 color : TEXCOORD1;
};

struct VSOutput
{
    float4 position : SV_Position;
    float4 color : COLOR;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    output.position = mul(float4(input.position, 1.0), viewProjection);
    output.color = input.color;
    return output;
}
