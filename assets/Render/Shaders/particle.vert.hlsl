// Particle Render Vertex Shader
// Billboard rendering of GPU particles
#pragma pack_matrix(row_major)

// Particle structure (must match compute shader)
struct Particle
{
    float3 Position;
    float Age;
    float3 Velocity;
    float Lifetime;
    float4 Color;
    float2 Size;
    float Rotation;
    float RotationSpeed;
};

cbuffer CameraUniforms : register(b0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 InvViewMatrix;
    float3 CameraPosition;
    float NearPlane;
    float3 CameraRight;
    float FarPlane;
    float3 CameraUp;
    float _Padding;
};

StructuredBuffer<Particle> Particles : register(t0);
StructuredBuffer<uint> AliveList : register(t1);

cbuffer ParticleParams : register(b1)
{
    uint AliveCount;
    uint3 _ParticlePadding;
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
    float4 Color : TEXCOORD1;
};

VertexOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID)
{
    VertexOutput output;

    if (instanceID >= AliveCount)
    {
        output.Position = float4(0, 0, 0, 0);
        output.TexCoord = float2(0, 0);
        output.Color = float4(0, 0, 0, 0);
        return output;
    }

    // Get particle from alive list
    uint particleIndex = AliveList[instanceID];
    Particle p = Particles[particleIndex];

    // Quad vertex positions (2 triangles, 6 vertices)
    // Vertex order: 0-1-2, 2-1-3
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
    float cosR = cos(p.Rotation);
    float sinR = sin(p.Rotation);
    float2 rotatedOffset = float2(
        offset.x * cosR - offset.y * sinR,
        offset.x * sinR + offset.y * cosR
    );

    // Apply size
    rotatedOffset *= p.Size;

    // Billboard: expand in camera space
    float3 worldPos = p.Position +
                      CameraRight * rotatedOffset.x +
                      CameraUp * rotatedOffset.y;

    output.Position = mul(float4(worldPos, 1.0), ViewProjectionMatrix);
    output.TexCoord = quadUVs[vertexID];
    output.Color = p.Color;

    return output;
}
