// G-buffer pass vertex shader
// Transforms vertices and passes through position/normal/color for MRT output

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float3 color : COLOR;
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float3 color : TEXCOORD2;
};

cbuffer Uniforms : register(b0)
{
    float4x4 mvp;
    float4x4 model;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    output.position = mul(mvp, float4(input.position, 1.0));
    output.worldPos = mul(model, float4(input.position, 1.0)).xyz;
    output.normal = normalize(mul((float3x3)model, input.normal));
    output.color = input.color;
    return output;
}
