// Textured quad vertex shader
// Receives vertex data from vertex buffer and transform from uniform buffer

struct VSInput
{
    float2 position : POSITION;
    float2 texCoord : TEXCOORD0;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD0;
};

// Uniform buffer with transform matrix
// Binding determined by DXC -fvk-b-shift option
cbuffer Uniforms : register(b0)
{
    float4x4 transform;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    float4 pos = float4(input.position, 0.0, 1.0);
    output.position = mul(transform, pos);
    output.texCoord = input.texCoord;
    return output;
}
