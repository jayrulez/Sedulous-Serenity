// Depth Prepass Fragment Shader
// Handles alpha testing for masked materials
#pragma pack_matrix(row_major)

#ifdef ALPHA_TEST
Texture2D AlbedoTexture : register(t0);
SamplerState LinearSampler : register(s0);

cbuffer MaterialUniforms : register(b3)
{
    float4 BaseColor;
    float AlphaCutoff;
    float3 _Padding;
};
#endif

struct FragmentInput
{
    float4 Position : SV_Position;
#ifdef ALPHA_TEST
    float2 TexCoord : TEXCOORD0;
#endif
};

void main(FragmentInput input)
{
#ifdef ALPHA_TEST
    float alpha = AlbedoTexture.Sample(LinearSampler, input.TexCoord).a * BaseColor.a;
    if (alpha < AlphaCutoff)
        discard;
#endif
    // Depth is written automatically
}
