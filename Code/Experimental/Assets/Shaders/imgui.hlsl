#pragma pack_matrix(row_major)

// ImGui vertex/fragment shader
// 2D UI rendering with orthographic projection, textured + vertex-colored

cbuffer ImGuiUniforms : register(b0)
{
	float4x4 Projection;
};

Texture2D FontTexture : register(t1);
SamplerState FontSampler : register(s2);

struct VSInput
{
	float2 Position : TEXCOORD0;
	float2 TexCoord : TEXCOORD1;
	float4 Color    : TEXCOORD2;
};

struct PSInput
{
	float4 Position : SV_Position;
	float2 TexCoord : TEXCOORD0;
	float4 Color    : COLOR0;
};

PSInput VSMain(VSInput input)
{
	PSInput output;
	output.Position = mul(float4(input.Position, 0.0, 1.0), Projection);
	output.TexCoord = input.TexCoord;
	output.Color = input.Color;
	return output;
}

float4 PSMain(PSInput input) : SV_Target
{
	float4 texColor = FontTexture.Sample(FontSampler, input.TexCoord);
	return input.Color * texColor;
}
