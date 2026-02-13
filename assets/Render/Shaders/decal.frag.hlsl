// Decal fragment shader - projects texture onto opaque geometry via depth buffer
#pragma pack_matrix(row_major)
#include "scene_uniforms.hlsli"

cbuffer DecalUniforms : register(b0, space1)
{
    float4x4 DecalWorldMatrix;
    float4x4 DecalInvWorldMatrix;
    float4 DecalColor;
    float AngleFadeStart;
    float AngleFadeEnd;
    float2 _Pad0;
};

Texture2D<float> DepthTexture : register(t0);
SamplerState DepthSampler : register(s0);

Texture2D AlbedoTexture : register(t0, space1);
SamplerState AlbedoSampler : register(s0, space1);

struct PSInput
{
    float4 Position : SV_POSITION;
    float4 ScreenPos : TEXCOORD0;
};

float4 main(PSInput input) : SV_TARGET
{
    // Get screen-space UV from fragment position
    float2 screenUV = input.Position.xy / ScreenSize;

    // Sample depth buffer
    float depth = DepthTexture.Load(int3(input.Position.xy, 0)).r;

    // Discard sky pixels (depth at far plane)
    if (depth >= 1.0)
        discard;

    // Reconstruct world position from depth using InvProjectionMatrix + InvViewMatrix
    // from CameraUniforms. No Y-flip needed: InvProjectionMatrix is the inverse of
    // the already-flipped projection, so it handles Vulkan Y convention automatically.
    float2 ndc = screenUV * 2.0 - 1.0;

    // NDC -> View space (undo projection including Y-flip)
    float4 viewPos4 = mul(float4(ndc, depth, 1.0), InvProjectionMatrix);
    float3 viewPos = viewPos4.xyz / viewPos4.w;

    // View space -> World space
    float3 worldPos = mul(float4(viewPos, 1.0), InvViewMatrix).xyz;

    // Transform world position to decal local space
    float3 localPos = mul(float4(worldPos, 1.0), DecalInvWorldMatrix).xyz;

    // Discard if clearly outside the unit cube [-0.5, 0.5]
    if (abs(localPos.x) > 0.5 || abs(localPos.y) > 0.5 || abs(localPos.z) > 0.5)
        discard;

    // Smooth edge fade to avoid hard boundaries and Z-fighting between overlapping decals
    float3 edgeFade = saturate((0.5 - abs(localPos)) * 4.0);
    float edgeAlpha = edgeFade.x * edgeFade.y * edgeFade.z;

    // Project along Y axis: UV from XZ plane
    float2 uv = localPos.xz + 0.5;

    // Sample albedo texture
    float4 albedo = AlbedoTexture.Sample(AlbedoSampler, uv);

    // Apply decal color tint and edge fade
    float4 result = albedo * DecalColor;
    result.a *= edgeAlpha;

    return result;
}
