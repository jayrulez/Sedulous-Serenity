// Sprite Vertex Shader
// Camera-facing billboarded quads with per-instance data
#pragma pack_matrix(row_major)

// Must match SceneUniforms in FrameContext.bf
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

// Per-instance data from vertex buffer (SpriteInstance layout)
struct InstanceInput
{
    float3 Position : ATTRIB0;   // World position
    float2 Size : ATTRIB1;       // Billboard size
    float4 UVRect : ATTRIB2;     // minU, minV, maxU, maxV
    float4 Color : ATTRIB3;      // RGBA color (unorm8x4)
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
    float4 Color : TEXCOORD1;
};

VertexOutput main(uint vertexID : SV_VertexID, InstanceInput inst)
{
    VertexOutput output;

    // Quad vertex positions (2 triangles, 6 vertices)
    static const float2 quadOffsets[6] = {
        float2(-0.5, -0.5), // 0
        float2(0.5, -0.5),  // 1
        float2(-0.5, 0.5),  // 2
        float2(-0.5, 0.5),  // 2
        float2(0.5, -0.5),  // 1
        float2(0.5, 0.5)    // 3
    };

    static const float2 quadUVs[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };

    float2 offset = quadOffsets[vertexID] * inst.Size;

    // Extract camera right/up from inverse view matrix for billboarding
    float3 CameraRight = InvViewMatrix[0].xyz;
    float3 CameraUp = InvViewMatrix[1].xyz;

    // Billboard: expand in camera space
    float3 worldPos = inst.Position +
                      CameraRight * offset.x +
                      CameraUp * offset.y;

    output.Position = mul(float4(worldPos, 1.0), ViewProjectionMatrix);

    // Map UV using UVRect (minU, minV, maxU, maxV)
    float2 baseUV = quadUVs[vertexID];
    output.TexCoord = float2(
        lerp(inst.UVRect.x, inst.UVRect.z, baseUV.x),
        lerp(inst.UVRect.y, inst.UVRect.w, baseUV.y)
    );

    output.Color = inst.Color;

    return output;
}
