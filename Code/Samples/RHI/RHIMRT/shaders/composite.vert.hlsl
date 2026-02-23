// Fullscreen quad vertex shader for compositing G-buffer

struct VSOutput
{
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD0;
};

// Fullscreen triangle trick - no vertex buffer needed
VSOutput main(uint vertexID : SV_VertexID)
{
    VSOutput output;

    // Generate fullscreen triangle from vertex ID
    float2 pos;
    pos.x = (vertexID == 1) ? 3.0 : -1.0;
    pos.y = (vertexID == 2) ? 3.0 : -1.0;

    output.position = float4(pos, 0.0, 1.0);
    output.texCoord = pos * 0.5 + 0.5;
    output.texCoord.y = 1.0 - output.texCoord.y;  // Flip Y for Vulkan

    return output;
}
