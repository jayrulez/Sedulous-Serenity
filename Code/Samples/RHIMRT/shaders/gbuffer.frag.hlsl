// G-buffer pass fragment shader
// Outputs to multiple render targets (MRT)

struct PSInput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float3 color : TEXCOORD2;
};

struct PSOutput
{
    float4 albedo : SV_Target0;    // RGB = color, A = unused
    float4 normal : SV_Target1;    // RGB = normal (remapped), A = unused
    float4 position : SV_Target2;  // RGB = world position, A = unused
};

PSOutput main(PSInput input)
{
    PSOutput output;

    // Albedo (color)
    output.albedo = float4(input.color, 1.0);

    // Normal (remap from [-1,1] to [0,1] for storage)
    output.normal = float4(input.normal * 0.5 + 0.5, 1.0);

    // World position
    output.position = float4(input.worldPos, 1.0);

    return output;
}
