// Particle Trail Vertex Shader
// Renders trail ribbons that follow particles

struct VSInput
{
    float3 position : POSITION;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

// View uniforms (same as particle shader - binding 0)
cbuffer ViewUniforms : register(b0)
{
    float4x4 viewProjection;
    float4 cameraPosition;
    float4 cameraRight;
    float4 cameraUp;
    float4 screenParams; // x = width, y = height, z = 1/width, w = 1/height
};

// Trail uniforms (binding 1)
cbuffer TrailUniforms : register(b1)
{
    float4 trailParams; // x = unused, y = unused, z = unused, w = unused
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Trail vertices are already in world space, just apply view-projection
    output.position = mul(viewProjection, float4(input.position, 1.0));
    output.uv = input.uv;
    output.color = input.color;

    return output;
}
