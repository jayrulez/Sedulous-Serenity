#pragma pack_matrix(row_major)

// HDRI Sky rendering — full-screen pass
// Converts view direction to equirectangular UV, samples HDR environment texture.
// Renders only where depth == 1.0 (sky pixels, nothing drawn by geometry).

static const float PI = 3.14159265359;

cbuffer SceneUniforms : register(b0, space0)
{
	float4x4 ViewMatrix;
	float4x4 ProjectionMatrix;
	float4x4 ViewProjectionMatrix;
	float4x4 InverseViewMatrix;
	float4x4 InverseProjectionMatrix;
	float4x4 PrevViewProjectionMatrix;
	float3 CameraPosition; float Time;
	float3 CameraForward;  float DeltaTime;
	float2 ScreenSize;     float NearPlane; float FarPlane;
	uint FrameNumber;      uint LightCount; uint ShadowCascadeCount; float Exposure;
	float AmbientIntensity; float SkyExposure; float _scenePad2; float _scenePad3;
};

// Sky resources (Set 1)
Texture2D HdriTexture : register(t0, space1);
SamplerState HdriSampler : register(s1, space1);

// Depth from prepass (Set 1)
Texture2D DepthTexture : register(t2, space1);

struct VSOutput
{
	float4 Position : SV_Position;
	float2 TexCoord : TEXCOORD0;
};

// Full-screen triangle from vertex ID
VSOutput VSMain(uint vertexID : SV_VertexID)
{
	VSOutput output;
	output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
	output.Position = float4(output.TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
	return output;
}

float4 PSMain(VSOutput input) : SV_Target
{
	// Check depth — only render sky where nothing was drawn (depth == 1.0)
	float depth = DepthTexture.Load(int3(input.Position.xy, 0)).r;
	if (depth < 1.0)
		discard;

	// Reconstruct view direction from screen UV
	float2 ndc = input.TexCoord * 2.0 - 1.0;
	ndc.y = -ndc.y; // UV Y=0 top, NDC Y=+1 top

	// Unproject to view space, then to world space
	float4 viewDir = mul(float4(ndc, 0.0, 1.0), InverseProjectionMatrix);
	viewDir.xyz /= viewDir.w;
	float3 worldDir = normalize(mul(float4(viewDir.xyz, 0.0), InverseViewMatrix).xyz);

	// Convert world direction to equirectangular UV
	// U = atan2(z, x) / (2*PI) + 0.5
	// V = asin(y) / PI + 0.5
	float2 hdriUV;
	hdriUV.x = atan2(worldDir.z, worldDir.x) / (2.0 * PI) + 0.5;
	hdriUV.y = asin(clamp(worldDir.y, -1.0, 1.0)) / PI + 0.5;
	// Flip V so north pole (Y+) is at the top of the texture
	hdriUV.y = 1.0 - hdriUV.y;

	float3 color = HdriTexture.Sample(HdriSampler, hdriUV).rgb * SkyExposure;

	return float4(color, 1.0);
}
