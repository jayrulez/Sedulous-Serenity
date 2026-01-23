// CPU Particle Trail Ribbon Vertex Shader
// Pre-computed ribbon vertices are passed directly (no billboarding needed)
#pragma pack_matrix(row_major)

cbuffer CameraUniforms : register(b0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 InvViewMatrix;
    float4x4 InvProjectionMatrix;
    float4x4 PrevViewProjectionMatrix;
    float3 CameraPosition;
    float Time;
    float3 CameraForward;
    float DeltaTime;
    float2 ScreenSize;
    float NearPlane;
    float FarPlane;
};

// Per-vertex data (TrailVertex layout, per-vertex rate)
struct VertexInput
{
    float3 Position : ATTRIB0;   // World position (ribbon edge)
    float2 TexCoord : ATTRIB1;   // UV
    float4 Color : ATTRIB2;      // RGBA (unorm8x4)
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
    float4 Color : TEXCOORD1;
};

VertexOutput main(VertexInput input)
{
    VertexOutput output;

    output.Position = mul(float4(input.Position, 1.0), ViewProjectionMatrix);
    output.TexCoord = input.TexCoord;
    output.Color = input.Color;

    return output;
}
