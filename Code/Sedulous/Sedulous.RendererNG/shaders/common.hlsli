// Common shader definitions for RendererNG
// Shared constants, structures, and utilities

#ifndef COMMON_HLSLI
#define COMMON_HLSLI

// ============================================================================
// Constants
// ============================================================================

static const float PI = 3.14159265359;
static const float TWO_PI = 6.28318530718;
static const float HALF_PI = 1.57079632679;
static const float INV_PI = 0.31830988618;

static const uint MAX_BONES = 256;
static const uint MAX_LIGHTS = 1024;

// ============================================================================
// Scene Uniform Buffer (binding 0, set 0 / space0)
// ============================================================================

cbuffer SceneUniforms : register(b0, space0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 InverseViewMatrix;
    float4x4 InverseProjectionMatrix;
    float4x4 PreviousViewProjectionMatrix; // For motion vectors

    float3 CameraPosition;
    float Time;

    float3 CameraForward;
    float DeltaTime;

    float2 ScreenSize;
    float NearPlane;
    float FarPlane;
};

// ============================================================================
// Object/Instance Data
// ============================================================================

struct InstanceData
{
    float4x4 WorldMatrix;
    float4x4 NormalMatrix;
    float4 CustomData; // User-defined per-instance data
};

// ============================================================================
// Skinning Data (Set 2 / space2 when skinned)
// ============================================================================

#ifdef SKINNED
cbuffer BoneMatrices : register(b0, space2)
{
    float4x4 Bones[MAX_BONES];
};
#endif

// ============================================================================
// Vertex Layouts
// ============================================================================

struct VS_INPUT_POS
{
    float3 Position : POSITION;
};

struct VS_INPUT_PNU
{
    float3 Position : POSITION;
    float3 Normal : NORMAL;
    float2 TexCoord : TEXCOORD0;
};

struct VS_INPUT_PNUT
{
    float3 Position : POSITION;
    float3 Normal : NORMAL;
    float2 TexCoord : TEXCOORD0;
    float4 Tangent : TANGENT; // w = handedness
};

struct VS_INPUT_SKINNED
{
    float3 Position : POSITION;
    float3 Normal : NORMAL;
    float2 TexCoord : TEXCOORD0;
    float4 Tangent : TANGENT;
    uint4 BoneIndices : BLENDINDICES;
    float4 BoneWeights : BLENDWEIGHT;
};

// ============================================================================
// Vertex Output / Pixel Input
// ============================================================================

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
    float3 WorldPos : TEXCOORD0;
    float3 Normal : TEXCOORD1;
    float2 TexCoord : TEXCOORD2;
#ifdef NORMAL_MAP
    float3 Tangent : TEXCOORD3;
    float3 Bitangent : TEXCOORD4;
#endif
#ifdef VERTEX_COLORS
    float4 Color : COLOR0;
#endif
};

// ============================================================================
// Utility Functions
// ============================================================================

// Linear to sRGB conversion
float3 LinearToSRGB(float3 color)
{
    return pow(color, 1.0 / 2.2);
}

// sRGB to linear conversion
float3 SRGBToLinear(float3 color)
{
    return pow(color, 2.2);
}

// Pack normal to [0,1] range
float3 PackNormal(float3 n)
{
    return n * 0.5 + 0.5;
}

// Unpack normal from [0,1] range
float3 UnpackNormal(float3 n)
{
    return n * 2.0 - 1.0;
}

// Reconstruct Z component of normal
float3 UnpackNormalMap(float2 xy)
{
    float3 n;
    n.xy = xy * 2.0 - 1.0;
    n.z = sqrt(saturate(1.0 - dot(n.xy, n.xy)));
    return n;
}

#endif // COMMON_HLSLI
