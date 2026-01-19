// Fog Apply - Vertex Shader
// Fullscreen triangle using SV_VertexID

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

VertexOutput main(uint vertexID : SV_VertexID)
{
    VertexOutput output;

    // Generate fullscreen triangle vertices from vertex ID
    output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(output.TexCoord * 2.0 - 1.0, 0.0, 1.0);

    // Flip Y for Vulkan
    output.Position.y = -output.Position.y;
    output.TexCoord.y = 1.0 - output.TexCoord.y;

    return output;
}
