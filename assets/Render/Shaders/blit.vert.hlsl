// Fullscreen Blit Vertex Shader
// Uses SV_VertexID to generate a fullscreen triangle

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

VertexOutput main(uint vertexID : SV_VertexID)
{
    VertexOutput output;

    // Generate fullscreen triangle vertices from vertex ID
    // Triangle covers [-1,-1] to [3,-1] to [-1,3] in clip space
    output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(output.TexCoord * 2.0 - 1.0, 0.0, 1.0);

    // Flip Y for Vulkan
    output.Position.y = -output.Position.y;
    output.TexCoord.y = 1.0 - output.TexCoord.y; // Flip UV to match

    return output;
}
