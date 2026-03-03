// Screen-Space Reflections Fragment Shader
// Linear ray marching against depth buffer with binary refinement.
// Without GBuffer roughness data, SSR is limited to glancing-angle reflections.

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
    ndc.y = -ndc.y; // Vulkan Y-flip
    float4 viewPos = mul(InvProjectionMatrix, ndc);
    return viewPos.xyz / viewPos.w;
}

// Project view-space position to screen UV and clip-space Z
float3 ProjectToScreen(float3 viewPos)
{
    float4 projected = mul(ProjectionMatrix, float4(viewPos, 1.0));
    projected.xyz /= projected.w;
    projected.y = -projected.y; // Vulkan Y-flip
    return float3(projected.xy * 0.5 + 0.5, projected.z);
}

// Reconstruct view-space normal from depth derivatives.
// Returns normal and a quality metric (0 = unreliable, 1 = good).
float4 ReconstructNormalWithQuality(float2 uv, float3 viewPos)
{
    float depthL = DepthTexture.Sample(PointSampler, uv + float2(-TexelSize.x, 0)).r;
    float depthR = DepthTexture.Sample(PointSampler, uv + float2( TexelSize.x, 0)).r;
    float depthU = DepthTexture.Sample(PointSampler, uv + float2(0, -TexelSize.y)).r;
    float depthD = DepthTexture.Sample(PointSampler, uv + float2(0,  TexelSize.y)).r;

    float3 posL = ReconstructViewPos(uv + float2(-TexelSize.x, 0), depthL);
    float3 posR = ReconstructViewPos(uv + float2( TexelSize.x, 0), depthR);
    float3 posU = ReconstructViewPos(uv + float2(0, -TexelSize.y), depthU);
    float3 posD = ReconstructViewPos(uv + float2(0,  TexelSize.y), depthD);

    float3 ddxL = viewPos - posL;
    float3 ddxR = posR - viewPos;
    float3 ddyU = viewPos - posU;
    float3 ddyD = posD - viewPos;

    float3 ddx = (abs(ddxL.z) < abs(ddxR.z)) ? ddxL : ddxR;
    float3 ddy = (abs(ddyU.z) < abs(ddyD.z)) ? ddyU : ddyD;

    float3 normal = normalize(cross(ddy, ddx));

    // Quality: check consistency between left/right and up/down derivatives.
    // Large disagreement = depth discontinuity or noisy surface = unreliable normal.
    float xConsistency = 1.0 - saturate(abs(ddxL.z - ddxR.z) / (abs(viewPos.z) * 0.01 + 0.01));
    float yConsistency = 1.0 - saturate(abs(ddyU.z - ddyD.z) / (abs(viewPos.z) * 0.01 + 0.01));
    float quality = xConsistency * yConsistency;

    return float4(normal, quality);
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

    // Reconstruct view-space position and normal with quality
    float3 viewPos = ReconstructViewPos(uv, depth);
    float4 normalQ = ReconstructNormalWithQuality(uv, viewPos);
    float3 normal = normalQ.xyz;
    float normalQuality = normalQ.w;

    // Skip pixels with unreliable normals (depth edges, noisy surfaces)
    if (normalQuality < 0.5)
        return float4(sceneColor, 1.0);

    // View direction (camera at origin in view space)
    float3 viewDir = normalize(viewPos);

    // Reflection direction
    float3 reflectDir = reflect(viewDir, normal);

    // Skip if reflecting backward (into the surface)
    if (reflectDir.z > 0.0)
        return float4(sceneColor, 1.0);

    // Fresnel: only reflect at glancing angles (no roughness data available)
    float NdotV = saturate(dot(-viewDir, normal));
    float fresnel = 0.04 + (1.0 - 0.04) * pow(1.0 - NdotV, 5.0);

    // Skip pixels where Fresnel contribution is negligible
    if (fresnel < 0.05)
        return float4(sceneColor, 1.0);

    // Skip if reflection direction is nearly parallel to the surface
    // (causes streaking artifacts as the ray slides along the surface)
    float RdotN = abs(dot(reflectDir, normal));
    if (RdotN < 0.1)
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
        float depthDiff = rayPos.z - rayViewPos.z;
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

                float refineDiff = refineMid.z - refineViewPos.z;
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

    // Composite — Fresnel-weighted, quality-weighted, edge-faded, distance-faded
    float blendFactor = fresnel * Intensity * edgeFade * distFade * normalQuality;
    float3 result = lerp(sceneColor, reflectedColor, saturate(blendFactor));

    return float4(result, 1.0);
}
