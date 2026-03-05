// Water Vertex Shader
// Flat grid with wave displacement from normal/height map
#pragma pack_matrix(row_major)

#include "scene_uniforms.hlsli"

cbuffer WaterUniforms : register(b0, space1)
{
    float3 WaterCenter;     float WaveSpeed;
    float4 WaterColor;
    float2 WaterSize;       float WaveScale;       float NormalStrength;
    float FresnelR0;        float RefractionStrength; float SpecularPower;  float MaxVisibleDepth;
    float FoamDepthThreshold; float FoamIntensity;  float Roughness;       float WaterPad0;
    float2 FlowDirection;   float2 WaterPad1;
};

Texture2D<float4> NormalMap : register(t0, space1);
SamplerState WaterSampler : register(s0, space1);

struct VertexInput
{
    float2 LocalPos : POSITION;    // Grid vertex 0..1
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float3 WorldPosition : TEXCOORD0;
    float2 UV : TEXCOORD1;
};

VertexOutput main(VertexInput input)
{
    // Map grid [0,1] to world XZ centered on WaterCenter
    float2 worldXZ = WaterCenter.xz + (input.LocalPos - 0.5) * WaterSize;

    // Animated UV for wave sampling
    float2 uv = input.LocalPos * WaveScale;
    uv += FlowDirection * Time * WaveSpeed;

    // Sample height from normal map alpha channel
    float h = NormalMap.SampleLevel(WaterSampler, uv, 0).a * NormalStrength * 0.5;

    float3 worldPos = float3(worldXZ.x, WaterCenter.y + h, worldXZ.y);

    VertexOutput output;
    output.Position = mul(float4(worldPos, 1.0), ViewProjectionMatrix);
    output.WorldPosition = worldPos;
    output.UV = input.LocalPos;
    return output;
}
