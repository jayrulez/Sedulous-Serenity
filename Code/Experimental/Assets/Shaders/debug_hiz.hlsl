// Debug visualization for Hi-Z depth pyramid
// Shows the Hi-Z mip chain as a grayscale depth overlay.
// MipLevel selectable via uniform.
#pragma pack_matrix(row_major)

struct PSInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

cbuffer DebugHiZParams : register(b0)
{
    uint   DisplayMip;    // Which mip level to show
    uint   TotalMips;     // Total mip count
    float  DepthMin;      // Near plane for remapping (0)
    float  DepthMax;      // Far plane for remapping (1)
};

Texture2D<float> HiZTexture : register(t1);
SamplerState      PointSampler : register(s2);

PSInput VSMain(uint vertexID : SV_VertexID)
{
    PSInput output;
    output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(output.TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return output;
}

float4 PSMain(PSInput input) : SV_Target
{
    float depth = HiZTexture.SampleLevel(PointSampler, input.TexCoord, (float)DisplayMip);

    // Remap depth [near, far] → [0, 1] for visualization
    // Standard depth: near=0, far=1. Invert for better contrast (near=white, far=black).
    float viz = 1.0 - saturate((depth - DepthMin) / max(DepthMax - DepthMin, 0.001));

    // Color code: grayscale with slight blue tint to distinguish from scene
    float3 color = float3(viz * 0.8, viz * 0.8, viz);

    return float4(color, 1.0);
}
