// Blit sample vertex shader

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

cbuffer Uniforms : register(b0)
{
    float4 quadRect;  // x, y, width, height in NDC
};

VSOutput main(uint vertexId : SV_VertexID)
{
    // Generate fullscreen triangle or quad vertices
    float2 positions[6] = {
        float2(0, 0), float2(1, 0), float2(1, 1),
        float2(0, 0), float2(1, 1), float2(0, 1)
    };
    float2 uvs[6] = {
        float2(0, 1), float2(1, 1), float2(1, 0),
        float2(0, 1), float2(1, 0), float2(0, 0)
    };

    VSOutput output;
    float2 pos = positions[vertexId];
    output.position = float4(quadRect.x + pos.x * quadRect.z, quadRect.y + pos.y * quadRect.w, 0.0, 1.0);
    output.uv = uvs[vertexId];
    return output;
}
