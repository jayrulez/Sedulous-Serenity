#ifndef PROBE_UNIFORMS_HLSLI
#define PROBE_UNIFORMS_HLSLI

#define MAX_REFLECTION_PROBES 8

struct ProbeData
{
    float3 Position;
    float Radius;
    uint LayerIndex;
    float3 _Pad;
};

cbuffer ProbeUniforms : register(b6)
{
    ProbeData Probes[MAX_REFLECTION_PROBES];
    uint ProbeCount;
    uint3 _ProbePad;
};

TextureCubeArray ProbeCubemaps : register(t11);

// Samples reflection probes for the given world position and reflection direction.
// Returns float4(reflectedColor, blendWeight). Weight=0 means no probe in range.
float4 SampleReflectionProbe(float3 worldPos, float3 R, float roughness, SamplerState samp)
{
    if (ProbeCount == 0)
        return float4(0, 0, 0, 0);

    // Find two nearest probes within range
    float bestDist = 1e20;
    float secondDist = 1e20;
    int bestIdx = -1;
    int secondIdx = -1;

    for (uint i = 0; i < ProbeCount; i++)
    {
        float dist = length(worldPos - Probes[i].Position);
        if (dist < Probes[i].Radius)
        {
            if (dist < bestDist)
            {
                secondDist = bestDist;
                secondIdx = bestIdx;
                bestDist = dist;
                bestIdx = (int)i;
            }
            else if (dist < secondDist)
            {
                secondDist = dist;
                secondIdx = (int)i;
            }
        }
    }

    if (bestIdx < 0)
        return float4(0, 0, 0, 0);

    float mipLevel = roughness * 4.0;

    // Sample nearest probe
    float4 uv0 = float4(R, (float)Probes[bestIdx].LayerIndex);
    float3 color0 = ProbeCubemaps.SampleLevel(samp, uv0, mipLevel).rgb;

    // Edge fade: smooth falloff at probe boundary
    float weight0 = 1.0 - smoothstep(0.7, 1.0, bestDist / Probes[bestIdx].Radius);

    // Blend with second probe if available
    if (secondIdx >= 0)
    {
        float4 uv1 = float4(R, (float)Probes[secondIdx].LayerIndex);
        float3 color1 = ProbeCubemaps.SampleLevel(samp, uv1, mipLevel).rgb;
        float weight1 = 1.0 - smoothstep(0.7, 1.0, secondDist / Probes[secondIdx].Radius);

        float totalWeight = weight0 + weight1;
        float3 blended = (color0 * weight0 + color1 * weight1) / max(totalWeight, 0.001);
        return float4(blended, saturate(totalWeight));
    }

    return float4(color0, weight0);
}

#endif
