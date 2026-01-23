// Sky Fragment Shader
// Procedural atmosphere with Rayleigh/Mie scattering
#pragma pack_matrix(row_major)

static const float PI = 3.14159265359;
static const float EARTH_RADIUS = 6371000.0;
static const float ATMOSPHERE_HEIGHT = 100000.0;
static const float ATMOSPHERE_RADIUS = EARTH_RADIUS + ATMOSPHERE_HEIGHT;

// Scattering coefficients
static const float3 RAYLEIGH_COEFF = float3(5.5e-6, 13.0e-6, 22.4e-6);
static const float MIE_COEFF = 21e-6;
static const float RAYLEIGH_SCALE_HEIGHT = 8000.0;
static const float MIE_SCALE_HEIGHT = 1200.0;
static const float MIE_G = 0.76;

cbuffer SkyUniforms : register(b1)
{
    float3 SunDirection;
    float SunIntensity;
    float3 SunColor;
    float AtmosphereDensity;
    float3 GroundColor;
    float ExposureValue;
    float3 ZenithColor;
    float CloudCoverage;
    float3 HorizonColor;
    float Time;
    float3 SolidColorValue;
    float SkyMode; // 0 = Procedural, 1 = SolidColor, 2 = EnvironmentMap
};

TextureCube EnvironmentMap : register(t0);
SamplerState EnvSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float3 ViewDir : TEXCOORD0;
};

// Ray-sphere intersection
float2 RaySphereIntersect(float3 rayOrigin, float3 rayDir, float3 sphereCenter, float sphereRadius)
{
    float3 offset = rayOrigin - sphereCenter;
    float a = dot(rayDir, rayDir);
    float b = 2.0 * dot(offset, rayDir);
    float c = dot(offset, offset) - sphereRadius * sphereRadius;
    float d = b * b - 4.0 * a * c;

    if (d < 0.0)
        return float2(-1.0, -1.0);

    float sqrtD = sqrt(d);
    return float2((-b - sqrtD) / (2.0 * a), (-b + sqrtD) / (2.0 * a));
}

// Rayleigh phase function
float RayleighPhase(float cosTheta)
{
    return 3.0 / (16.0 * PI) * (1.0 + cosTheta * cosTheta);
}

// Mie phase function (Henyey-Greenstein)
float MiePhase(float cosTheta, float g)
{
    float g2 = g * g;
    return 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + cosTheta * cosTheta)) /
           ((2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

// Calculate optical depth along a ray
float2 OpticalDepth(float3 rayOrigin, float3 rayDir, float rayLength, int numSamples)
{
    float3 samplePoint = rayOrigin;
    float stepSize = rayLength / float(numSamples);
    float2 opticalDepth = float2(0.0, 0.0);

    for (int i = 0; i < numSamples; i++)
    {
        float height = length(samplePoint) - EARTH_RADIUS;
        float rayleighDensity = exp(-height / RAYLEIGH_SCALE_HEIGHT);
        float mieDensity = exp(-height / MIE_SCALE_HEIGHT);
        opticalDepth += float2(rayleighDensity, mieDensity) * stepSize;
        samplePoint += rayDir * stepSize;
    }

    return opticalDepth;
}

// Calculate atmosphere scattering
float3 CalculateAtmosphere(float3 rayOrigin, float3 rayDir, float rayLength, float3 sunDir)
{
    const int NUM_SAMPLES = 16;
    const int NUM_LIGHT_SAMPLES = 8;

    float stepSize = rayLength / float(NUM_SAMPLES);
    float3 samplePoint = rayOrigin + rayDir * stepSize * 0.5;

    float3 rayleighSum = float3(0.0, 0.0, 0.0);
    float3 mieSum = float3(0.0, 0.0, 0.0);
    float2 opticalDepth = float2(0.0, 0.0);

    for (int i = 0; i < NUM_SAMPLES; i++)
    {
        float height = length(samplePoint) - EARTH_RADIUS;
        float rayleighDensity = exp(-height / RAYLEIGH_SCALE_HEIGHT) * stepSize;
        float mieDensity = exp(-height / MIE_SCALE_HEIGHT) * stepSize;
        opticalDepth += float2(rayleighDensity, mieDensity);

        // Light ray to sun
        float2 sunIntersect = RaySphereIntersect(samplePoint, sunDir, float3(0, 0, 0), ATMOSPHERE_RADIUS);
        float2 lightOpticalDepth = OpticalDepth(samplePoint, sunDir, sunIntersect.y, NUM_LIGHT_SAMPLES);

        float2 totalOpticalDepth = opticalDepth + lightOpticalDepth;
        float3 transmittance = exp(-(RAYLEIGH_COEFF * totalOpticalDepth.x + MIE_COEFF * totalOpticalDepth.y) * AtmosphereDensity);

        rayleighSum += transmittance * rayleighDensity;
        mieSum += transmittance * mieDensity;

        samplePoint += rayDir * stepSize;
    }

    float cosTheta = dot(rayDir, sunDir);
    float3 rayleigh = rayleighSum * RAYLEIGH_COEFF * RayleighPhase(cosTheta);
    float3 mie = mieSum * MIE_COEFF * MiePhase(cosTheta, MIE_G);

    return (rayleigh + mie) * SunColor * SunIntensity;
}

float4 main(FragmentInput input) : SV_Target
{
    // Solid color mode
    if (SkyMode > 0.5 && SkyMode < 1.5)
    {
        return float4(SolidColorValue, 1.0);
    }

    // Environment map mode - sample cubemap
    if (SkyMode > 1.5)
    {
        float3 dir = normalize(input.ViewDir);
        float3 color = EnvironmentMap.Sample(EnvSampler, dir).rgb;
        return float4(color, 1.0);
    }

    float3 viewDir = normalize(input.ViewDir);

    // Simple fallback if looking below horizon
    if (viewDir.y < -0.01)
    {
        float t = -viewDir.y;
        return float4(lerp(HorizonColor, GroundColor, t), 1.0);
    }

    // Ray origin at camera position above Earth surface
    float3 rayOrigin = float3(0.0, EARTH_RADIUS + 100.0, 0.0);

    // Intersect ray with atmosphere
    float2 atmosphereIntersect = RaySphereIntersect(rayOrigin, viewDir, float3(0, 0, 0), ATMOSPHERE_RADIUS);

    if (atmosphereIntersect.y < 0.0)
        return float4(0.0, 0.0, 0.0, 1.0);

    // Check for earth intersection
    float2 earthIntersect = RaySphereIntersect(rayOrigin, viewDir, float3(0, 0, 0), EARTH_RADIUS);
    float rayLength = earthIntersect.x > 0.0 ? earthIntersect.x : atmosphereIntersect.y;

    // Calculate atmosphere color
    float3 color = CalculateAtmosphere(rayOrigin, viewDir, rayLength, SunDirection);

    // Add sun disc
    float sunDot = dot(viewDir, SunDirection);
    if (sunDot > 0.9995)
    {
        float sunFade = smoothstep(0.9995, 0.99975, sunDot);
        color += SunColor * SunIntensity * sunFade * 50.0;
    }

    // Exposure tone mapping
    color = 1.0 - exp(-color * ExposureValue);

    return float4(color, 1.0);
}
