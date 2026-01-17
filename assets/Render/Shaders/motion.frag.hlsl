// Motion Vector Fragment Shader
// Outputs screen-space motion vectors for TAA and motion blur
#pragma pack_matrix(row_major)

#ifdef ALPHA_TEST
Texture2D AlbedoTexture : register(t0);
SamplerState LinearSampler : register(s0);

cbuffer MaterialUniforms : register(b4)
{
    float4 BaseColor;
    float AlphaCutoff;
    float3 _Padding;
};
#endif

cbuffer CameraUniforms : register(b0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 PrevViewProjectionMatrix;
    float3 CameraPosition;
    float NearPlane;
    float3 CameraForward;
    float FarPlane;
    float2 JitterOffset;
    float2 PrevJitterOffset;
};

struct FragmentInput
{
    float4 Position : SV_Position;
    float4 CurrentPos : TEXCOORD0;
    float4 PrevPos : TEXCOORD1;
#ifdef ALPHA_TEST
    float2 TexCoord : TEXCOORD2;
#endif
};

float2 main(FragmentInput input) : SV_Target
{
#ifdef ALPHA_TEST
    float alpha = AlbedoTexture.Sample(LinearSampler, input.TexCoord).a * BaseColor.a;
    if (alpha < AlphaCutoff)
        discard;
#endif

    // Convert clip space to NDC
    float2 currentNDC = input.CurrentPos.xy / input.CurrentPos.w;
    float2 prevNDC = input.PrevPos.xy / input.PrevPos.w;

    // Remove jitter
    currentNDC -= JitterOffset;
    prevNDC -= PrevJitterOffset;

    // Motion vector is current - previous
    // Scaled to screen space (0-1 range)
    float2 motion = (currentNDC - prevNDC) * 0.5;

    return motion;
}
