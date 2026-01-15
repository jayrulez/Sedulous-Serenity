// Particle billboard vertex shader for RendererNG
// Expands particle instance data into camera-facing billboards

#include "common.hlsli"

// ============================================================================
// Particle Uniforms
// ============================================================================

cbuffer ParticleUniforms : register(b1)
{
    uint RenderMode;           // 0=Billboard, 1=Stretched, 2=Horizontal, 3=Vertical
    float StretchFactor;
    float MinStretchLength;
    uint UseTexture;

    uint SoftParticlesEnabled;
    float SoftParticleDistance;
    float ParticleNearPlane;
    float ParticleFarPlane;
};

// ============================================================================
// Particle Instance Data (per-instance vertex buffer)
// ============================================================================

struct ParticleInstance
{
    float3 Position : POSITION;        // 0
    float2 Size : TEXCOORD0;           // 12
    float4 Color : COLOR0;             // 20 (UByte4Normalized)
    float Rotation : TEXCOORD1;        // 24
    float2 TexCoordOffset : TEXCOORD2; // 28
    float2 TexCoordScale : TEXCOORD3;  // 36
    float2 Velocity2D : TEXCOORD4;     // 44
};

// ============================================================================
// Vertex Output
// ============================================================================

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
    float4 Color : COLOR0;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : TEXCOORD1;
#ifdef SOFT_PARTICLES
    float4 ScreenPos : TEXCOORD2;
#endif
};

// ============================================================================
// Quad Corner Offsets (counter-clockwise from bottom-left)
// ============================================================================

static const float2 QuadCorners[4] =
{
    float2(-0.5, -0.5),  // 0: bottom-left
    float2( 0.5, -0.5),  // 1: bottom-right
    float2(-0.5,  0.5),  // 2: top-left
    float2( 0.5,  0.5)   // 3: top-right
};

static const float2 QuadUVs[4] =
{
    float2(0.0, 1.0),    // 0: bottom-left
    float2(1.0, 1.0),    // 1: bottom-right
    float2(0.0, 0.0),    // 2: top-left
    float2(1.0, 0.0)     // 3: top-right
};

// ============================================================================
// Rotation Helper
// ============================================================================

float2 RotatePoint(float2 point, float rotation)
{
    float s = sin(rotation);
    float c = cos(rotation);
    return float2(
        point.x * c - point.y * s,
        point.x * s + point.y * c
    );
}

// ============================================================================
// Main Vertex Shader
// ============================================================================

VS_OUTPUT main(uint vertexID : SV_VertexID, ParticleInstance particle)
{
    VS_OUTPUT output = (VS_OUTPUT)0;

    // Get quad corner for this vertex (indices are 0,1,2,2,1,3)
    uint cornerIndex = vertexID;
    float2 corner = QuadCorners[cornerIndex];
    float2 uv = QuadUVs[cornerIndex];

    // Apply rotation
    float2 rotatedCorner = RotatePoint(corner, particle.Rotation);

    // Scale by particle size
    float2 scaledCorner = rotatedCorner * particle.Size;

    // Billboard expansion based on render mode
    float3 worldOffset;

    if (RenderMode == 0) // Billboard (face camera)
    {
        // Use camera right and up vectors from inverse view matrix
        float3 right = InverseViewMatrix[0].xyz;
        float3 up = InverseViewMatrix[1].xyz;
        worldOffset = right * scaledCorner.x + up * scaledCorner.y;
    }
    else if (RenderMode == 1) // Stretched Billboard (velocity aligned)
    {
        float3 velocity = float3(particle.Velocity2D, 0);
        float speed = length(velocity);

        if (speed > 0.001)
        {
            // Stretch along velocity direction
            float3 velocityDir = velocity / speed;
            float stretchAmount = max(speed * StretchFactor, MinStretchLength);

            // Use camera up for the perpendicular axis
            float3 up = InverseViewMatrix[1].xyz;
            float3 right = normalize(cross(velocityDir, up));
            up = cross(right, velocityDir);

            worldOffset = right * scaledCorner.x + velocityDir * scaledCorner.y * stretchAmount;
        }
        else
        {
            // Fallback to regular billboard
            float3 right = InverseViewMatrix[0].xyz;
            float3 up = InverseViewMatrix[1].xyz;
            worldOffset = right * scaledCorner.x + up * scaledCorner.y;
        }
    }
    else if (RenderMode == 2) // Horizontal Billboard (face up, Y-axis)
    {
        worldOffset = float3(scaledCorner.x, 0, scaledCorner.y);
    }
    else // Vertical Billboard (stay vertical, face camera horizontally)
    {
        // Project camera direction onto XZ plane
        float3 toCam = CameraPosition - particle.Position;
        toCam.y = 0;
        float len = length(toCam);

        if (len > 0.001)
        {
            float3 forward = toCam / len;
            float3 right = cross(float3(0, 1, 0), forward);
            worldOffset = right * scaledCorner.x + float3(0, 1, 0) * scaledCorner.y;
        }
        else
        {
            worldOffset = float3(scaledCorner.x, scaledCorner.y, 0);
        }
    }

    // Final world position
    float3 worldPos = particle.Position + worldOffset;
    output.WorldPos = worldPos;

    // Transform to clip space
    output.Position = mul(float4(worldPos, 1.0), ViewProjectionMatrix);

    // Apply texture atlas coordinates
    output.TexCoord = particle.TexCoordOffset + uv * particle.TexCoordScale;

    // Pass through color
    output.Color = particle.Color;

#ifdef SOFT_PARTICLES
    // Store screen position for depth comparison
    output.ScreenPos = output.Position;
#endif

    return output;
}
