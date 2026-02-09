// Simple triangle vertex shader with rotation
// Receives vertex data from vertex buffer and rotation from uniform buffer

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

// Uniform buffer with rotation angle
cbuffer Uniforms : register(b0)
{
    float4x4 transform;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    float4 pos = float4(input.position, 0.0, 1.0);
    output.position = mul(transform, pos);
    output.color = input.color;
    return output;
}
