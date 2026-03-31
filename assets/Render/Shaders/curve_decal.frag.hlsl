// Curve decal fragment shader - depth-proximity fade for surface conformity
#pragma pack_matrix(row_major)
#include "scene_uniforms.hlsli"

cbuffer CurveDecalParams : register(b0, space1)
{
    float4 DecalColor;
    float ProjectionDepth;
    float3 _Pad;
};

Texture2D<float> DepthTexture : register(t0);
SamplerState DepthSampler : register(s0);

Texture2D AlbedoTexture : register(t0, space1);
SamplerState AlbedoSampler : register(s0, space1);

struct PSInput
{
    float4 Position : SV_POSITION;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : TEXCOORD1;
    float3 Normal : TEXCOORD2;
};

float4 main(PSInput input) : SV_TARGET
{
    // Sample depth buffer at fragment position
    float sceneDepth = DepthTexture.Load(int3(input.Position.xy, 0)).r;

    // Discard sky pixels
    if (sceneDepth >= 1.0)
        discard;

    // Reconstruct scene world position from depth
    float2 screenUV = input.Position.xy / ScreenSize;
    float2 ndc = float2(screenUV.x * 2.0 - 1.0, (1.0 - screenUV.y) * 2.0 - 1.0);

    float4 viewPos4 = mul(float4(ndc, sceneDepth, 1.0), InvProjectionMatrix);
    float3 viewPos = viewPos4.xyz / viewPos4.w;
    float3 sceneWorldPos = mul(float4(viewPos, 1.0), InvViewMatrix).xyz;

    // Depth proximity test: discard if scene is too far from decal strip
    float dist = abs(sceneWorldPos.y - input.WorldPos.y);
    if (dist > ProjectionDepth)
        discard;

    // Fade by depth proximity (1 at surface, 0 at ProjectionDepth)
    float depthFade = 1.0 - saturate(dist / max(ProjectionDepth, 0.001));

    // Sample albedo
    float4 albedo = AlbedoTexture.Sample(AlbedoSampler, input.TexCoord);

    // Apply color tint and depth fade
    float4 result = albedo * DecalColor;
    result.a *= depthFade;

    return result;
}
