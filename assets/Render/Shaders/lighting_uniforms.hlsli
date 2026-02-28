// Lighting uniforms and clustered lighting buffers
// Layout MUST match LightingUniforms struct in LightBuffer.bf
cbuffer LightingUniforms : register(b3)
{
    float3 AmbientColor;
    float AmbientIntensity;
    uint LightCount;
    uint ClusterDimensionX;
    uint ClusterDimensionY;
    uint ClusterDimensionZ;
    float2 ClusterScale;
    float2 ClusterBias;
    uint DebugMode;
    uint _Pad0;
    uint _Pad1;
    uint _Pad2;
};

// Clustered lighting buffers (read-only)
StructuredBuffer<Light> Lights : register(t4);
StructuredBuffer<uint2> ClusterLightInfo : register(t5); // offset, count
StructuredBuffer<uint> LightIndices : register(t6);
