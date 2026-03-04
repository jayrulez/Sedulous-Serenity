// Terrain Vertex Shader
// Heightmap displacement on a patch grid
#pragma pack_matrix(row_major)

#include "scene_uniforms.hlsli"

cbuffer TerrainUniforms : register(b0, space1)
{
    float3 TerrainOrigin;
    float HeightScale;
    float2 TerrainWorldSize;
    float2 HeightmapSize;
    float4 LayerScales;
    float Roughness;
    float Metallic;
    float2 _Pad;
};

Texture2D<float> Heightmap : register(t0, space1);
SamplerState TerrainSampler : register(s0, space1);

struct VertexInput
{
    float2 LocalPos : POSITION;          // Grid vertex (0..1)
    float4 PatchData : ATTRIB0;          // Instance: offsetX, offsetZ, scaleX, scaleZ
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float3 WorldPosition : TEXCOORD0;
    float2 TerrainUV : TEXCOORD1;
};

VertexOutput main(VertexInput input)
{
    float2 worldXZ = input.PatchData.xy + input.LocalPos * input.PatchData.zw;
    float2 uv = worldXZ / TerrainWorldSize;
    float height = Heightmap.SampleLevel(TerrainSampler, uv, 0).r * HeightScale;
    float3 worldPos = float3(worldXZ.x, height, worldXZ.y) + TerrainOrigin;

    VertexOutput output;
    output.Position = mul(float4(worldPos, 1.0), ViewProjectionMatrix);
    output.WorldPosition = worldPos;
    output.TerrainUV = uv;
    return output;
}
