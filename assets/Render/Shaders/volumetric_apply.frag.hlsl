// Volumetric Fog - Apply Fragment Shader
// Samples the fog volume and composites with the scene
#pragma pack_matrix(row_major)

cbuffer VolumetricParams : register(b0)
{
    float4x4 ViewMatrix;
    float4x4 InvProjectionMatrix;
    float NearPlane;
    float FarPlane;
    float2 ScreenSize;
    uint3 FroxelDimensions;
    float _Padding;
};

Texture2D<float4> SceneColor : register(t0);
Texture2D<float> SceneDepth : register(t1);
Texture3D<float4> IntegratedVolume : register(t2);

SamplerState LinearSampler : register(s0);
SamplerState PointSampler : register(s1);

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Fullscreen triangle vertex shader
VertexOutput VSMain(uint vertexID : SV_VertexID)
{
    VertexOutput output;
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    output.TexCoord = float2(uv.x, 1.0 - uv.y);
    return output;
}

// Convert depth to linear
float LinearizeDepth(float depth)
{
    // Assuming reverse-Z projection
    return NearPlane * FarPlane / (FarPlane - depth * (FarPlane - NearPlane));
}

// Convert linear depth to froxel Z coordinate
float DepthToFroxelZ(float linearDepth)
{
    float t = (linearDepth - NearPlane) / (FarPlane - NearPlane);
    return sqrt(saturate(t)); // Inverse of exponential distribution
}

float4 PSMain(VertexOutput input) : SV_Target
{
    // Sample scene
    float4 sceneColor = SceneColor.Sample(PointSampler, input.TexCoord);
    float depth = SceneDepth.Sample(PointSampler, input.TexCoord).r;

    // Convert to froxel coordinates
    float linearDepth = LinearizeDepth(depth);
    float froxelZ = DepthToFroxelZ(linearDepth);

    float3 froxelCoord = float3(input.TexCoord, froxelZ);

    // Sample integrated volume
    float4 volumetric = IntegratedVolume.SampleLevel(LinearSampler, froxelCoord, 0);

    float3 inscattering = volumetric.rgb;
    float transmittance = volumetric.a;

    // Composite: scene * transmittance + inscattering
    float3 finalColor = sceneColor.rgb * transmittance + inscattering;

    return float4(finalColor, sceneColor.a);
}
