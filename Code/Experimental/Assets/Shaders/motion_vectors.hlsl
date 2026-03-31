#pragma pack_matrix(row_major)

// Motion vector generation — full-screen pass
// Reconstructs world position from depth, reprojects with PrevViewProjectionMatrix,
// outputs pixel-space velocity as RG16Float.

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

// Depth buffer from prepass (Set 1)
Texture2D DepthTexture : register(t0, space1);
SamplerState PointSampler : register(s1, space1);

struct VSOutput
{
	float4 Position : SV_Position;
	float2 TexCoord : TEXCOORD0;
};

// Full-screen triangle (no vertex buffer needed)
VSOutput VSMain(uint vertexID : SV_VertexID)
{
	VSOutput output;
	output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
	output.Position = float4(output.TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
	return output;
}

float4 PSMain(VSOutput input) : SV_Target
{
	// Sample depth
	float depth = DepthTexture.Sample(PointSampler, input.TexCoord).r;

	// Skip sky (depth == 1.0 = cleared far plane)
	if (depth >= 1.0)
		return float4(0.0, 0.0, 0.0, 0.0);

	// Reconstruct clip-space position from UV + depth
	float2 ndc = input.TexCoord * 2.0 - 1.0;
	ndc.y = -ndc.y; // UV Y=0 is top, NDC Y=+1 is top
	float4 clipPos = float4(ndc, depth, 1.0);

	// Clip → view → world (two-step using provided inverse matrices)
	float4 viewPos = mul(clipPos, InverseProjectionMatrix);
	viewPos /= viewPos.w;
	float4 worldPos = mul(viewPos, InverseViewMatrix);

	// Reproject to previous frame's clip space
	float4 prevClip = mul(float4(worldPos.xyz, 1.0), PrevViewProjectionMatrix);
	float2 prevNDC = prevClip.xy / prevClip.w;

	// Motion vector: current NDC - previous NDC, scaled to pixel space
	float2 velocity = (ndc - prevNDC) * 0.5 * ScreenSize;

	return float4(velocity, 0.0, 1.0);
}
