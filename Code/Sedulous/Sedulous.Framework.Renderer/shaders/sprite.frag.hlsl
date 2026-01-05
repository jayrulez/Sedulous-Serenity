// Sprite/Billboard Fragment Shader
// Simple colored sprite (no texture)

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

float4 main(PSInput input) : SV_Target
{
    // Simple colored sprite (no texture for now)
    return input.color;
}
