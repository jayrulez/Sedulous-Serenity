// Sprite billboard vertex shader for RendererNG
// Expands sprite instance data into billboards with multiple modes

#include "common.hlsli"

// ============================================================================
// Sprite Uniforms
// ============================================================================

cbuffer SpriteUniforms : register(b1)
{
    uint UseTexture;
    float DepthBias;
    float _Padding0;
    float _Padding1;
};

// ============================================================================
// Billboard Mode Constants
// ============================================================================

static const uint BILLBOARD_NONE = 0;
static const uint BILLBOARD_FULL = 1;
static const uint BILLBOARD_AXIS_Y = 2;
static const uint BILLBOARD_CUSTOM = 3;

static const uint FLAG_FLIP_X = 0x100;
static const uint FLAG_FLIP_Y = 0x200;

// ============================================================================
// Sprite Instance Data (per-instance vertex buffer)
// ============================================================================

struct SpriteInstance
{
    float3 Position : POSITION;        // 0
    float2 Size : TEXCOORD0;           // 12
    float4 Color : COLOR0;             // 20 (UByte4Normalized)
    float Rotation : TEXCOORD1;        // 24
    float4 UVRect : TEXCOORD2;         // 28 (x, y, width, height)
    uint Flags : TEXCOORD3;            // 44
};

// ============================================================================
// Vertex Output
// ============================================================================

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
    float4 Color : COLOR0;
    float2 TexCoord : TEXCOORD0;
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

VS_OUTPUT main(uint vertexID : SV_VertexID, SpriteInstance sprite)
{
    VS_OUTPUT output = (VS_OUTPUT)0;

    // Get quad corner for this vertex
    uint cornerIndex = vertexID;
    float2 corner = QuadCorners[cornerIndex];
    float2 uv = QuadUVs[cornerIndex];

    // Extract billboard mode
    uint billboardMode = sprite.Flags & 0xFF;

    // Apply flipping
    if (sprite.Flags & FLAG_FLIP_X)
        uv.x = 1.0 - uv.x;
    if (sprite.Flags & FLAG_FLIP_Y)
        uv.y = 1.0 - uv.y;

    // Apply rotation
    float2 rotatedCorner = RotatePoint(corner, sprite.Rotation);

    // Scale by sprite size
    float2 scaledCorner = rotatedCorner * sprite.Size;

    // Billboard expansion based on mode
    float3 worldOffset;

    if (billboardMode == BILLBOARD_FULL)
    {
        // Full billboard - face camera on all axes
        float3 right = InverseViewMatrix[0].xyz;
        float3 up = InverseViewMatrix[1].xyz;
        worldOffset = right * scaledCorner.x + up * scaledCorner.y;
    }
    else if (billboardMode == BILLBOARD_AXIS_Y)
    {
        // Y-axis billboard - only rotate around Y
        float3 toCam = CameraPosition - sprite.Position;
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
    else if (billboardMode == BILLBOARD_CUSTOM)
    {
        // Custom axis - not implemented, fall back to full billboard
        float3 right = InverseViewMatrix[0].xyz;
        float3 up = InverseViewMatrix[1].xyz;
        worldOffset = right * scaledCorner.x + up * scaledCorner.y;
    }
    else // BILLBOARD_NONE
    {
        // No billboarding - sprite in XY plane
        worldOffset = float3(scaledCorner.x, scaledCorner.y, 0);
    }

    // Final world position
    float3 worldPos = sprite.Position + worldOffset;

    // Transform to clip space
    output.Position = mul(float4(worldPos, 1.0), ViewProjectionMatrix);

    // Apply depth bias
    output.Position.z += DepthBias * output.Position.w;

    // Calculate texture coordinates from UV rect
    output.TexCoord = sprite.UVRect.xy + uv * sprite.UVRect.zw;

    // Pass through color
    output.Color = sprite.Color;

    return output;
}
