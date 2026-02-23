// Mipmap test vertex shader
// Renders a textured quad that can be moved away to show mipmap levels

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

cbuffer Uniforms : register(b0)
{
    float4x4 mvp;
    float mipBias;  // For explicit LOD testing
    float3 padding;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    output.position = mul(mvp, float4(input.position, 0.0, 1.0));
    output.texCoord = input.texCoord;
    return output;
}
