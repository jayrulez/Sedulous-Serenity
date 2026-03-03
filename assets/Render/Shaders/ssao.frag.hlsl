// SSAO Generation Fragment Shader
// Hemisphere-sampling ambient occlusion with depth-reconstructed normals.

cbuffer SSAOParams : register(b0)
{
    float4x4 ProjectionMatrix;
    float4x4 InvProjectionMatrix;
    float2 TexelSize;
    float Radius;
    float Intensity;
    float Bias;
    float NearPlane;
    float FarPlane;
    int SampleCount;
    float2 ScreenSize;
    float2 _Pad;
};

Texture2D DepthTexture : register(t0);
SamplerState PointSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Linearize depth from depth buffer [0,1] to view-space Z
float LinearizeDepth(float d)
{
    return NearPlane * FarPlane / (FarPlane - d * (FarPlane - NearPlane));
}

// Reconstruct view-space position from UV and depth
float3 ReconstructViewPos(float2 uv, float depth)
{
    // Convert UV to NDC
    float4 ndc = float4(uv * 2.0 - 1.0, depth, 1.0);
    ndc.y = -ndc.y; // Vulkan Y-flip

    // Unproject to view space
    float4 viewPos = mul(InvProjectionMatrix, ndc);
    return viewPos.xyz / viewPos.w;
}

// Reconstruct view-space normal from depth derivatives (best-fit of 5 taps)
float3 ReconstructNormal(float2 uv, float3 viewPos)
{
    // Sample 4 cardinal neighbors
    float depthL = DepthTexture.Sample(PointSampler, uv + float2(-TexelSize.x, 0)).r;
    float depthR = DepthTexture.Sample(PointSampler, uv + float2( TexelSize.x, 0)).r;
    float depthU = DepthTexture.Sample(PointSampler, uv + float2(0, -TexelSize.y)).r;
    float depthD = DepthTexture.Sample(PointSampler, uv + float2(0,  TexelSize.y)).r;

    float3 posL = ReconstructViewPos(uv + float2(-TexelSize.x, 0), depthL);
    float3 posR = ReconstructViewPos(uv + float2( TexelSize.x, 0), depthR);
    float3 posU = ReconstructViewPos(uv + float2(0, -TexelSize.y), depthU);
    float3 posD = ReconstructViewPos(uv + float2(0,  TexelSize.y), depthD);

    // Use the closest pair for each axis to avoid edge artifacts
    float3 ddx = (abs(posL.z - viewPos.z) < abs(posR.z - viewPos.z))
        ? (viewPos - posL) : (posR - viewPos);
    float3 ddy = (abs(posU.z - viewPos.z) < abs(posD.z - viewPos.z))
        ? (viewPos - posU) : (posD - viewPos);

    float3 normal = normalize(cross(ddy, ddx));
    return normal;
}

// Simple hash for per-pixel random rotation (avoids noise texture)
float Hash(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

// Hardcoded hemisphere sample kernel (16 samples, Poisson-distributed)
static const float3 KERNEL[16] = {
    float3( 0.5381, 0.1856,-0.4319),
    float3( 0.1379, 0.2486, 0.4430),
    float3( 0.3371, 0.5679,-0.0057),
    float3(-0.6999,-0.0451,-0.0019),
    float3( 0.0689,-0.1598,-0.8547),
    float3( 0.0560, 0.0069,-0.1843),
    float3(-0.0146, 0.1402, 0.0762),
    float3( 0.0100,-0.1924,-0.0344),
    float3(-0.3577,-0.5301,-0.4358),
    float3(-0.3169, 0.1063, 0.0158),
    float3( 0.0103,-0.5869, 0.0046),
    float3(-0.0897,-0.4940, 0.3287),
    float3( 0.7119,-0.0154,-0.0918),
    float3(-0.0533, 0.0596,-0.5411),
    float3( 0.0352,-0.0631, 0.5460),
    float3(-0.4776, 0.2847,-0.0271)
};

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    // Sample depth
    float depth = DepthTexture.Sample(PointSampler, uv).r;

    // Skip sky pixels
    if (depth >= 1.0)
        return float4(1.0, 1.0, 1.0, 1.0);

    // Reconstruct view-space position and normal
    float3 viewPos = ReconstructViewPos(uv, depth);
    float3 normal = ReconstructNormal(uv, viewPos);

    // Per-pixel random rotation angle
    float randomAngle = Hash(input.Position.xy) * 6.283185;
    float cosA = cos(randomAngle);
    float sinA = sin(randomAngle);

    // Build TBN from normal for hemisphere orientation
    float3 tangent = abs(normal.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    tangent = normalize(tangent - normal * dot(tangent, normal));
    float3 bitangent = cross(normal, tangent);

    // Accumulate occlusion
    float occlusion = 0.0;
    int validSamples = 0;

    for (int i = 0; i < SampleCount; i++)
    {
        // Get sample and apply random rotation around normal
        float3 sampleDir = KERNEL[i];

        // Rotate sample in tangent plane
        float3 rotated;
        rotated.x = sampleDir.x * cosA - sampleDir.y * sinA;
        rotated.y = sampleDir.x * sinA + sampleDir.y * cosA;
        rotated.z = sampleDir.z;

        // Orient to hemisphere via TBN
        float3 sampleOffset = tangent * rotated.x + bitangent * rotated.y + normal * rotated.z;

        // Scale by radius and apply progressive distance (closer samples weighted more)
        float scale = (float(i) + 1.0) / float(SampleCount);
        scale = lerp(0.1, 1.0, scale * scale);

        // Offset view-space position
        float3 samplePos = viewPos + sampleOffset * Radius * scale;

        // Project sample to screen UV
        float4 projected = mul(ProjectionMatrix, float4(samplePos, 1.0));
        projected.xy /= projected.w;
        projected.y = -projected.y; // Vulkan Y-flip
        float2 sampleUV = projected.xy * 0.5 + 0.5;

        // Skip if projected outside screen
        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0)
            continue;

        // Sample depth at projected UV and reconstruct view-space Z
        float sampleDepth = DepthTexture.Sample(PointSampler, sampleUV).r;
        float3 sampleViewPos = ReconstructViewPos(sampleUV, sampleDepth);
        float sampleZ = sampleViewPos.z;

        // Occlusion test: sample occluded if surface depth is closer than sample
        // Use a larger bias to prevent self-occlusion on flat surfaces
        float depthDiff = viewPos.z - sampleZ;
        float occluded = (depthDiff > Bias) ? 1.0 : 0.0;

        // Range check: only count occlusion from surfaces within Radius distance
        // Beyond that, it's just unrelated geometry
        float rangeCheck = smoothstep(0.0, 1.0, Radius / (abs(depthDiff) + 0.001));

        // Reject very large depth differences (background/foreground leaking)
        if (abs(depthDiff) > Radius * 2.0)
            rangeCheck = 0.0;

        occlusion += occluded * rangeCheck;
        validSamples++;
    }

    // Normalize and apply intensity
    float ao = 1.0;
    if (validSamples > 0)
    {
        ao = 1.0 - (occlusion / float(validSamples));
        ao = pow(saturate(ao), Intensity);
    }

    return float4(ao, ao, ao, 1.0);
}
