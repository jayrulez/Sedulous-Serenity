// Skybox vertex shader for RendererNG
// Generates fullscreen triangle and ray directions for cubemap sampling

#include "common.hlsli"

// ============================================================================
// Skybox Uniforms
// ============================================================================

cbuffer SkyboxUniforms : register(b1)
{
    float4x4 InverseViewProjection;
    float Exposure;
    float Rotation;
    float _Padding0;
    float _Padding1;
};

// ============================================================================
// Vertex Output
// ============================================================================

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
    float3 RayDir : TEXCOORD0;
};

// ============================================================================
// Main Vertex Shader
// ============================================================================

VS_OUTPUT main(uint vertexID : SV_VertexID)
{
    VS_OUTPUT output = (VS_OUTPUT)0;

    // Generate fullscreen triangle from vertex ID
    // Triangle covers [-1,-1] to [3,3] in NDC
    // This ensures full screen coverage with a single triangle
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    float4 clipPos = float4(uv * 2.0 - 1.0, 1.0, 1.0);

    // Flip Y for Vulkan
    clipPos.y = -clipPos.y;

    // Output position at far plane (z = 1)
    output.Position = float4(clipPos.xy, 1.0, 1.0);

    // Calculate world-space ray direction
    float4 worldPos = mul(clipPos, InverseViewProjection);
    float3 rayDir = worldPos.xyz / worldPos.w;

    // Apply rotation around Y axis
    if (Rotation != 0.0)
    {
        float s = sin(Rotation);
        float c = cos(Rotation);
        float3 rotated;
        rotated.x = rayDir.x * c - rayDir.z * s;
        rotated.y = rayDir.y;
        rotated.z = rayDir.x * s + rayDir.z * c;
        rayDir = rotated;
    }

    output.RayDir = normalize(rayDir);

    return output;
}
