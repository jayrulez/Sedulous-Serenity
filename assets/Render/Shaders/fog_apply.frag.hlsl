// Fog Apply - Fragment Shader
// Applies volumetric fog to scene color
#pragma pack_matrix(row_major)

cbuffer FogApplyParams : register(b0)
{
    float NearPlane;
    float FarPlane;
    uint FroxelDimensionsX;
    uint FroxelDimensionsY;
    uint FroxelDimensionsZ;
    float _Padding1;
    float _Padding2;
    float _Padding3;
};

Texture2D<float4> SceneColor : register(t0);
Texture2D<float> SceneDepth : register(t1);
Texture3D<float4> FogVolume : register(t2);

SamplerState PointSampler : register(s0);
SamplerState LinearSampler : register(s1);

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Convert depth to linear (reverse-Z projection)
float LinearizeDepth(float depth)
{
    return NearPlane * FarPlane / (FarPlane - depth * (FarPlane - NearPlane));
}

// Convert linear depth to froxel Z coordinate
float DepthToFroxelZ(float linearDepth)
{
    float t = (linearDepth - NearPlane) / (FarPlane - NearPlane);
    return sqrt(saturate(t)); // Inverse of exponential distribution
}

float4 main(VertexOutput input) : SV_Target
{
    // Sample scene color
    float4 color = SceneColor.Sample(PointSampler, input.TexCoord);

    // Sample depth and convert to froxel coordinates
    float depth = SceneDepth.Sample(PointSampler, input.TexCoord).r;
    float linearDepth = LinearizeDepth(depth);
    float froxelZ = DepthToFroxelZ(linearDepth);

    float3 froxelCoord = float3(input.TexCoord, froxelZ);

    // Sample integrated fog volume
    float4 fog = FogVolume.SampleLevel(LinearSampler, froxelCoord, 0);

    float3 inscattering = fog.rgb;
    float transmittance = fog.a;

    // Composite: scene * transmittance + inscattering
    color.rgb = color.rgb * transmittance + inscattering;

    return color;
}
