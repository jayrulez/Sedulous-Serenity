// Contact Shadows Fragment Shader
// Short-range screen-space ray march toward the main directional light.
// Adds fine shadow detail in crevices and contact points that CSM can't resolve.
#pragma pack_matrix(row_major)

#include "gbuffer_utils.hlsli"

cbuffer ContactShadowParams : register(b0)
{
    float4x4 ProjectionMatrix;
    float4x4 InvProjectionMatrix;
    float3 LightDirViewSpace;
    float ContactShadowLength;
    float2 TexelSize;
    float NearPlane;
    float FarPlane;
};

Texture2D SceneColor : register(t0);
Texture2D DepthTexture : register(t1);
Texture2D GBufferTexture : register(t2);
SamplerState PointSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Reconstruct view-space position from UV and depth
float3 ReconstructViewPos(float2 uv, float depth)
{
    float4 ndc = float4(uv * 2.0 - 1.0, depth, 1.0);
    // No Y-flip needed: ProjectionMatrix already has M22 negated on CPU
    float4 viewPos = mul(ndc, InvProjectionMatrix);
    return viewPos.xyz / viewPos.w;
}

// Project view-space position to screen UV
float2 ProjectToUV(float3 viewPos)
{
    float4 projected = mul(float4(viewPos, 1.0), ProjectionMatrix);
    projected.xy /= projected.w;
    // No Y-flip needed: ProjectionMatrix already has M22 negated on CPU
    return projected.xy * 0.5 + 0.5;
}

// Read view-space normal from GBuffer (octahedral encoded in RG channels)
float3 ReadNormalFromGBuffer(float2 uv)
{
    float4 gbuffer = GBufferTexture.Sample(PointSampler, uv);
    return OctahedralDecode(gbuffer.rg);
}

static const int NUM_STEPS = 16;

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    float3 sceneColor = SceneColor.Sample(PointSampler, uv).rgb;

    // Sample depth
    float depth = DepthTexture.Sample(PointSampler, uv).r;

    // Skip sky
    if (depth >= 1.0)
        return float4(sceneColor, 1.0);

    // Reconstruct view-space position, read normal from GBuffer
    float3 viewPos = ReconstructViewPos(uv, depth);
    float3 normal = ReadNormalFromGBuffer(uv);

    // Check if surface faces the light — backlit surfaces don't need contact shadows
    float NdotL = dot(normal, normalize(-LightDirViewSpace));
    if (NdotL < 0.05)
        return float4(sceneColor, 1.0);

    // Ray march toward light (negative light direction = toward the light source)
    float3 rayDir = normalize(-LightDirViewSpace);
    float stepLength = ContactShadowLength / float(NUM_STEPS);

    // Self-shadow bias: start the ray slightly away from the surface
    float3 startPos = viewPos + normal * stepLength * 2.0 + rayDir * stepLength;

    float shadow = 0.0;

    for (int i = 1; i <= NUM_STEPS; i++)
    {
        // Step along ray toward light
        float3 samplePos = startPos + rayDir * stepLength * float(i);

        // Project to screen
        float2 sampleUV = ProjectToUV(samplePos);

        // Check screen bounds
        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0)
            break;

        // Sample depth at projected position
        float sampleDepth = DepthTexture.Sample(PointSampler, sampleUV).r;
        float3 depthViewPos = ReconstructViewPos(sampleUV, sampleDepth);

        // Check if ray is behind the depth buffer (occluded)
        // Right-handed view space: ray behind surface when ray Z is more negative
        float depthDiff = depthViewPos.z - samplePos.z;
        float thickness = stepLength * 3.0; // Only detect nearby surfaces
        if (depthDiff > stepLength * 0.5 && depthDiff < thickness)
        {
            // Softer shadows for farther occlusion
            float t = float(i) / float(NUM_STEPS);
            float softness = 1.0 - t;
            shadow = max(shadow, softness);
        }
    }

    // Apply contact shadow as subtle darkening (max 30%)
    float3 result = sceneColor * (1.0 - shadow * 0.3);
    return float4(result, 1.0);
}
