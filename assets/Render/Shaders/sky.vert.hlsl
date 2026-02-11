// Sky Vertex Shader
// Renders a fullscreen triangle for sky/atmosphere
#pragma pack_matrix(row_major)

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 ClipXY : TEXCOORD0;
};

VertexOutput main(uint vertexID : SV_VertexID)
{
    VertexOutput output;

    // Fullscreen triangle (vertices: 0, 1, 2)
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(uv * 2.0 - 1.0, 1.0, 1.0); // Z = 1 for sky at far plane
    output.ClipXY = output.Position.xy;

    return output;
}
