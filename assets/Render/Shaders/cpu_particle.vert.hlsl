// CPU Particle Render Vertex Shader
// Billboard rendering of CPU-simulated particles via instance buffer
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

// Per-instance data from vertex buffer (CPUParticleVertex layout)
struct InstanceInput
{
    float3 Position : ATTRIB0;       // World position
    float2 Size : ATTRIB1;           // Billboard size
    float4 Color : ATTRIB2;          // RGBA color (unorm8x4)
    float Rotation : ATTRIB3;        // Rotation angle
    float4 TexCoordOffsetScale : ATTRIB4; // xy=offset, zw=scale
    float2 Velocity2D : ATTRIB5;     // For stretched billboard
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

    float2 offset = quadOffsets[vertexID];

    // Apply rotation
    float cosR = cos(inst.Rotation);
    float sinR = sin(inst.Rotation);
    float2 rotatedOffset = float2(
        offset.x * cosR - offset.y * sinR,
        offset.x * sinR + offset.y * cosR
    );

    // Apply size
    rotatedOffset *= inst.Size;

    // Extract camera right/up from inverse view matrix for billboarding
    float3 CameraRight = InvViewMatrix[0].xyz;
    float3 CameraUp = InvViewMatrix[1].xyz;

    // Billboard: expand in camera space
    float3 worldPos = inst.Position +
                      CameraRight * rotatedOffset.x +
                      CameraUp * rotatedOffset.y;

    output.Position = mul(float4(worldPos, 1.0), ViewProjectionMatrix);

    // Apply texture atlas offset/scale
    float2 baseUV = quadUVs[vertexID];
    output.TexCoord = inst.TexCoordOffsetScale.xy + baseUV * inst.TexCoordOffsetScale.zw;

    output.Color = inst.Color;

    return output;
}
