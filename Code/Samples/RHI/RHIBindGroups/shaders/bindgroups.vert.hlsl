// Bind groups sample - Vertex shader
// Demonstrates multiple bind groups and dynamic offsets

struct VSInput
{
    float2 position : POSITION;
};

struct VSOutput
{
    float4 position : SV_Position;
    float4 color : COLOR0;
};

// Set 0: Global per-frame data (static binding)
cbuffer GlobalUniforms : register(b0, space0)
{
    float time;
    float3 padding;
};

// Set 1: Per-object data (dynamic offset into buffer)
cbuffer ObjectUniforms : register(b0, space1)
{
    float4x4 transform;
    float4 color;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Apply per-object transform
    float4 pos = mul(transform, float4(input.position, 0.0, 1.0));

    // Add subtle animation based on global time
    pos.x += sin(time * 2.0 + pos.y * 3.0) * 0.02;
    pos.y += cos(time * 2.0 + pos.x * 3.0) * 0.02;

    output.position = pos;

    // Test: output the actual color from the cbuffer
    output.color = color;

    return output;
}
