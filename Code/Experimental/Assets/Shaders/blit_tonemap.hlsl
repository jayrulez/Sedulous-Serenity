#pragma pack_matrix(row_major)

struct PSInput
{
	float4 Position : SV_Position;
	float2 TexCoord : TEXCOORD0;
};

Texture2D    SceneColorTex : register(t0, space0);
SamplerState LinearSampler : register(s1, space0);

PSInput VSMain(uint vertexID : SV_VertexID)
{
	PSInput output;
	output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
	output.Position = float4(output.TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
	return output;
}

float4 PSMain(PSInput input) : SV_Target
{
	float3 color = SceneColorTex.Sample(LinearSampler, input.TexCoord).rgb;

#ifdef PASSTHROUGH
	// Post-process stack already tonemapped — just pass through.
	// BGRA8UnormSrgb target handles linear→sRGB.
	return float4(color, 1.0);
#else
	// Fallback tonemap (no PostProcessStack)
	float exposure = 1.0;
	color *= exposure;
	float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
	float3 x = color;
	color = saturate((x * (a * x + b)) / (x * (c * x + d) + e));
	color = pow(color, 1.0 / 2.2);
	return float4(color, 1.0);
#endif
}
