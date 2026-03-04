// Screen-Space Reflections Fragment Shader
// Linear ray marching against depth buffer with binary refinement.
// Uses GBuffer for accurate normals and roughness-based reflection fade.
#pragma pack_matrix(row_major)

#include "gbuffer_utils.hlsli"

cbuffer SSRParams : register(b0)
{
    float4x4 ProjectionMatrix;
    float4x4 InvProjectionMatrix;
    float2 TexelSize;
    float Intensity;
    float MaxDistance;
    float NearPlane;
    float FarPlane;
    int MaxSteps;
    float StepSize;
    float Thickness;
    float3 _Pad;
};

Texture2D SceneColor : register(t0);
Texture2D DepthTexture : register(t1);
Texture2D GBufferTexture : register(t2);
SamplerState LinearSampler : register(s0);
SamplerState PointSampler : register(s1);

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

// Project view-space position to screen UV and clip-space Z
float3 ProjectToScreen(float3 viewPos)
{
    float4 projected = mul(float4(viewPos, 1.0), ProjectionMatrix);
    projected.xyz /= projected.w;
    // No Y-flip needed: ProjectionMatrix already has M22 negated on CPU
    return float3(projected.xy * 0.5 + 0.5, projected.z);
}

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    float3 sceneColor = SceneColor.Sample(PointSampler, uv).rgb;

    // Sample depth
    float depth = DepthTexture.Sample(PointSampler, uv).r;

    // Skip sky
    if (depth >= 1.0)
        return float4(sceneColor, 1.0);

    // Read GBuffer: view-space normal, roughness, metallic
    float4 gbuffer = GBufferTexture.Sample(PointSampler, uv);
    float3 normal;
    float roughness;
    float metallic;
    UnpackGBuffer(gbuffer, normal, roughness, metallic);

    // Skip rough surfaces (no visible reflections above roughness 0.5)
    if (roughness > 0.5)
        return float4(sceneColor, 1.0);

    // Roughness fade: smooth surfaces get full reflection, rougher surfaces fade out
    float roughnessFade = 1.0 - roughness * 2.0;

    // Reconstruct view-space position
    float3 viewPos = ReconstructViewPos(uv, depth);

    // View direction (camera at origin in view space)
    float3 viewDir = normalize(viewPos);

    // Reflection direction
    float3 reflectDir = reflect(viewDir, normal);

    // Skip if reflecting backward (into the surface)
    if (reflectDir.z > 0.0)
        return float4(sceneColor, 1.0);

    // Fresnel with metallic and roughness modulation
    // Metals have high base reflectivity (F0 ~0.5-1.0), dielectrics ~0.04
    float NdotV = saturate(dot(-viewDir, normal));
    float f0 = lerp(0.04, 0.7, metallic);
    float fresnel = f0 + (1.0 - f0) * pow(1.0 - NdotV, 5.0);
    fresnel *= roughnessFade;

    // Skip pixels where Fresnel contribution is negligible
    if (fresnel < 0.02)
        return float4(sceneColor, 1.0);

    // Start ray with an offset to prevent self-intersection
    float3 rayStart = viewPos + normal * 0.05 + reflectDir * StepSize * 2.0;
    float3 rayPos = rayStart;
    float3 rayStep = reflectDir * StepSize;
    float2 hitUV = float2(0, 0);
    bool hit = false;
    float2 startScreenUV = uv;

    for (int i = 0; i < MaxSteps; i++)
    {
        rayPos += rayStep;

        // Check if ray has gone too far
        if (length(rayPos - viewPos) > MaxDistance)
            break;

        // Project ray position to screen
        float3 rayScreen = ProjectToScreen(rayPos);
        float2 rayUV = rayScreen.xy;

        // Check screen bounds
        if (rayUV.x < 0.0 || rayUV.x > 1.0 || rayUV.y < 0.0 || rayUV.y > 1.0)
            break;

        // Skip if the ray hasn't moved far enough on screen (prevents self-hits)
        if (length(rayUV - startScreenUV) < TexelSize.x * 3.0)
        {
            rayStep *= 1.1;
            continue;
        }

        // Sample depth at ray UV
        float rayDepth = DepthTexture.Sample(PointSampler, rayUV).r;

        // Skip sky hits
        if (rayDepth >= 1.0)
        {
            rayStep *= 1.05;
            continue;
        }

        float3 rayViewPos = ReconstructViewPos(rayUV, rayDepth);

        // Check if ray crossed behind the depth buffer surface
        // View space is right-handed (negative Z into scene), so ray behind surface = more negative Z
        float depthDiff = rayViewPos.z - rayPos.z;
        if (depthDiff > 0.0 && depthDiff < Thickness)
        {
            // Binary refinement for precise hit
            float3 refineMin = rayPos - rayStep;
            float3 refineMax = rayPos;

            for (int j = 0; j < 4; j++)
            {
                float3 refineMid = (refineMin + refineMax) * 0.5;
                float3 refineScreen = ProjectToScreen(refineMid);
                float refineDepth = DepthTexture.Sample(PointSampler, refineScreen.xy).r;
                float3 refineViewPos = ReconstructViewPos(refineScreen.xy, refineDepth);

                float refineDiff = refineViewPos.z - refineMid.z;
                if (refineDiff > 0.0)
                    refineMax = refineMid;
                else
                    refineMin = refineMid;
            }

            float3 hitScreen = ProjectToScreen((refineMin + refineMax) * 0.5);
            hitUV = hitScreen.xy;
            hit = true;
            break;
        }

        // Accelerate step size as we move further
        rayStep *= 1.05;
    }

    if (!hit)
        return float4(sceneColor, 1.0);

    // Sample reflected color
    float3 reflectedColor = SceneColor.Sample(LinearSampler, hitUV).rgb;

    // Edge fade: reduce near screen borders
    float2 edgeFade2D = smoothstep(0.0, 0.15, hitUV) * (1.0 - smoothstep(0.85, 1.0, hitUV));
    float edgeFade = edgeFade2D.x * edgeFade2D.y;

    // Distance fade: far-away reflections fade out
    float hitDist = length(ReconstructViewPos(hitUV, DepthTexture.Sample(PointSampler, hitUV).r) - viewPos);
    float distFade = 1.0 - saturate(hitDist / MaxDistance);

    // Composite — Fresnel-weighted, roughness-faded, edge-faded, distance-faded
    float blendFactor = fresnel * Intensity * edgeFade * distFade;
    float3 result = lerp(sceneColor, reflectedColor, saturate(blendFactor));

    return float4(result, 1.0);
}
