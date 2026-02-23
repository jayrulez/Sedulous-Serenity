// MSAA sample vertex shader

struct VSInput
{
    float2 position : POSITION;
    float3 color : COLOR0;
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 color : COLOR0;
};

cbuffer Uniforms : register(b0)
{
    float4x4 transform;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    output.position = mul(transform, float4(input.position, 0.0, 1.0));
    output.color = input.color;
    return output;
}
