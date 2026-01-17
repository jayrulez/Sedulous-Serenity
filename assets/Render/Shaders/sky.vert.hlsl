// Sky Vertex Shader
// Renders a fullscreen triangle for sky/atmosphere
#pragma pack_matrix(row_major)

cbuffer CameraUniforms : register(b0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 InvViewMatrix;
    float4x4 InvProjectionMatrix;
    float3 CameraPosition;
    float NearPlane;
    float3 CameraForward;
    float FarPlane;
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float3 ViewDir : TEXCOORD0;
};

VertexOutput main(uint vertexID : SV_VertexID)
{
    VertexOutput output;

    // Fullscreen triangle (vertices: 0, 1, 2)
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(uv * 2.0 - 1.0, 1.0, 1.0); // Z = 1 for sky at far plane

    // Calculate view direction in world space
    float4 clipPos = float4(output.Position.xy, 1.0, 1.0);
    float4 viewPos = mul(clipPos, InvProjectionMatrix);
    viewPos.xyz /= viewPos.w;

    float3 viewDir = mul(float4(viewPos.xyz, 0.0), InvViewMatrix).xyz;
    output.ViewDir = normalize(viewDir);

    return output;
}
