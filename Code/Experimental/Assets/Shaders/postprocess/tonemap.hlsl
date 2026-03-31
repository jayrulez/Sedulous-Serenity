// Post-processing tonemap shader
// Applies exposure + tonemap curve to HDR input → LDR output.
#pragma pack_matrix(row_major)

struct PSInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

Texture2D    InputTex     : register(t0);
SamplerState LinearSampler : register(s1);

cbuffer TonemapParams : register(b2)
{
    float Exposure;
    uint  TonemapMode;   // 0=ACES, 1=Reinhard, 2=AgX
    float2 _pad;
};

PSInput VSMain(uint vertexID : SV_VertexID)
{
    PSInput output;
    output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(output.TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return output;
}

// ACES filmic (Narkowicz approximation)
float3 TonemapACES(float3 x)
{
    float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Reinhard extended
float3 TonemapReinhard(float3 x)
{
    return x / (x + 1.0);
}

// AgX tonemapper — attempt at film-look tonemap.
// Falls back to a simple filmic curve that desaturates highlights naturally.
float3 TonemapAgX(float3 x)
{
    // Attempt a film-like response with highlight desaturation
    // Based on Uchimura 2017 (Gran Turismo)
    float P = 1.0;   // Max brightness
    float a = 1.0;   // Contrast
    float m = 0.22;  // Linear section start
    float l = 0.4;   // Linear section length
    float c = 1.33;  // Black tightness curve
    float b = 0.0;   // Black offset

    float l0 = ((P - m) * l) / a;
    float3 S0 = m + l0;
    float3 S1 = m + a * l0;
    float C2 = (a * P) / (P - S1);
    float3 CP = -C2 / P;

    float3 w0 = 1.0 - smoothstep(0.0, m, x);
    float3 w2 = step(m + l0, x);
    float3 w1 = 1.0 - w0 - w2;

    float3 T = m * pow(x / m, c) + b;
    float3 L = m + a * (x - m);
    float3 S = P - (P - S1) * exp(CP * (x - S0));

    return T * w0 + L * w1 + S * w2;
}

float4 PSMain(PSInput input) : SV_Target
{
    float3 hdr = InputTex.Sample(LinearSampler, input.TexCoord).rgb;

    // Apply exposure
    hdr *= Exposure;

    // Tonemap
    float3 ldr;
    if (TonemapMode == 1)
        ldr = TonemapReinhard(hdr);
    else if (TonemapMode == 2)
        ldr = TonemapAgX(hdr);
    else
        ldr = TonemapACES(hdr);

    // No gamma here — output linear LDR in RGBA16Float.
    // Final sRGB conversion happens in the blit pass (BGRA8UnormSrgb target).

    return float4(ldr, 1.0);
}
