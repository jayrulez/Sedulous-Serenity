#ifndef PROBE_UNIFORMS_HLSLI
#define PROBE_UNIFORMS_HLSLI

#define MAX_REFLECTION_PROBES 8

struct ProbeData
{
    float3 Position;
    float Radius;
    uint LayerIndex;
    float3 _Pad;
    float4 IrradianceSH[9]; // SH9 irradiance (xyz = RGB, w = unused)
};

cbuffer ProbeUniforms : register(b6)
{
    ProbeData Probes[MAX_REFLECTION_PROBES];
    uint ProbeCount;
    uint3 _ProbePad;
};

TextureCubeArray ProbeCubemaps : register(t11);

// ===================== Probe Search Helper =====================

// Result of nearest-2-probe search
struct ProbeSearchResult
{
    int bestIdx;
    float bestWeight;
    int secondIdx;
    float secondWeight;
};

// Finds the two nearest probes within range of worldPos.
// Returns indices and edge-fade weights. bestIdx = -1 means no probe in range.
ProbeSearchResult FindNearestProbes(float3 worldPos)
{
    ProbeSearchResult result;
    result.bestIdx = -1;
    result.bestWeight = 0.0;
    result.secondIdx = -1;
    result.secondWeight = 0.0;

    if (ProbeCount == 0)
        return result;

    float bestDist = 1e20;
    float secondDist = 1e20;

    for (uint i = 0; i < ProbeCount; i++)
    {
        float dist = length(worldPos - Probes[i].Position);
        if (dist < Probes[i].Radius)
        {
            if (dist < bestDist)
            {
                secondDist = bestDist;
                result.secondIdx = result.bestIdx;
                bestDist = dist;
                result.bestIdx = (int)i;
            }
            else if (dist < secondDist)
            {
                secondDist = dist;
                result.secondIdx = (int)i;
            }
        }
    }

    if (result.bestIdx >= 0)
        result.bestWeight = 1.0 - smoothstep(0.7, 1.0, bestDist / Probes[result.bestIdx].Radius);
    if (result.secondIdx >= 0)
        result.secondWeight = 1.0 - smoothstep(0.7, 1.0, secondDist / Probes[result.secondIdx].Radius);

    return result;
}

// ===================== SH9 Evaluation =====================

// Evaluates pre-convolved SH9 irradiance for a given normal direction.
float3 EvaluateSH9(float4 sh[9], float3 N)
{
    float3 result = sh[0].xyz * 0.282095;                          // Y00
    result += sh[1].xyz * 0.488603 * N.y;                          // Y1,-1
    result += sh[2].xyz * 0.488603 * N.z;                          // Y1,0
    result += sh[3].xyz * 0.488603 * N.x;                          // Y1,1
    result += sh[4].xyz * 1.092548 * N.x * N.y;                   // Y2,-2
    result += sh[5].xyz * 1.092548 * N.y * N.z;                   // Y2,-1
    result += sh[6].xyz * 0.315392 * (3.0 * N.z * N.z - 1.0);    // Y2,0
    result += sh[7].xyz * 1.092548 * N.x * N.z;                   // Y2,1
    result += sh[8].xyz * 0.546274 * (N.x * N.x - N.y * N.y);    // Y2,2
    return max(result, 0.0);
}

// ===================== Probe Sampling =====================

// Samples reflection probes for the given world position and reflection direction.
// Returns float4(reflectedColor, blendWeight). Weight=0 means no probe in range.
float4 SampleReflectionProbe(float3 worldPos, float3 R, float roughness, SamplerState samp)
{
    ProbeSearchResult search = FindNearestProbes(worldPos);

    if (search.bestIdx < 0)
        return float4(0, 0, 0, 0);

    float mipLevel = roughness * 4.0;

    // Sample nearest probe
    float4 uv0 = float4(R, (float)Probes[search.bestIdx].LayerIndex);
    float3 color0 = ProbeCubemaps.SampleLevel(samp, uv0, mipLevel).rgb;

    // Blend with second probe if available
    if (search.secondIdx >= 0)
    {
        float4 uv1 = float4(R, (float)Probes[search.secondIdx].LayerIndex);
        float3 color1 = ProbeCubemaps.SampleLevel(samp, uv1, mipLevel).rgb;

        float totalWeight = search.bestWeight + search.secondWeight;
        float3 blended = (color0 * search.bestWeight + color1 * search.secondWeight) / max(totalWeight, 0.001);
        return float4(blended, saturate(totalWeight));
    }

    return float4(color0, search.bestWeight);
}

// Samples probe diffuse irradiance via SH9 for the given world position and normal.
// Returns float4(irradiance, blendWeight). Weight=0 means no probe in range.
float4 SampleProbeDiffuse(float3 worldPos, float3 N)
{
    ProbeSearchResult search = FindNearestProbes(worldPos);

    if (search.bestIdx < 0)
        return float4(0, 0, 0, 0);

    // Evaluate SH9 for nearest probe
    float3 color0 = EvaluateSH9(Probes[search.bestIdx].IrradianceSH, N);

    // Blend with second probe if available
    if (search.secondIdx >= 0)
    {
        float3 color1 = EvaluateSH9(Probes[search.secondIdx].IrradianceSH, N);

        float totalWeight = search.bestWeight + search.secondWeight;
        float3 blended = (color0 * search.bestWeight + color1 * search.secondWeight) / max(totalWeight, 0.001);
        return float4(blended, saturate(totalWeight));
    }

    return float4(color0, search.bestWeight);
}

#endif
