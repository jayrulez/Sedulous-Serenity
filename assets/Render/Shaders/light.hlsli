// Light structure — must match GPULight in LightBuffer.bf
struct Light
{
    float3 Position;
    float Range;
    float3 Direction;
    float SpotAngleCos;    // cos(outer cone angle) for spot lights
    float3 Color;
    float Intensity;
    uint Type;             // 0 = Directional, 1 = Point, 2 = Spot
    int ShadowIndex;
    float2 _Padding;
};
