// Depth buffer test vertex shader
// Renders 3D geometry with model-view-projection transform

struct VSInput
{
    float3 position : POSITION;
    float3 color : COLOR;
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 color : COLOR;
};

// Model-View-Projection matrix
cbuffer Uniforms : register(b0)
{
    float4x4 mvp;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    output.position = mul(mvp, float4(input.position, 1.0));
    output.color = input.color;
    return output;
}
