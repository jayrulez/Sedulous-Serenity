#pragma pack_matrix(row_major)

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
	uint FrameNumber;      uint LightCount; uint ShadowCascadeCount; float _scenePad;
};

#ifdef GPU_DRIVEN
// GPU-driven path: per-object data in a storage buffer, indexed by ObjectIndex.
// ObjectIndex comes from an instance-rate vertex attribute (slot 1).
ByteAddressBuffer ObjectData : register(t0, space1);

float4x4 LoadObjectMatrix(uint objectIndex, uint fieldOffset)
{
	uint base = objectIndex * 256 + fieldOffset;
	float4 r0 = asfloat(ObjectData.Load4(base +  0));
	float4 r1 = asfloat(ObjectData.Load4(base + 16));
	float4 r2 = asfloat(ObjectData.Load4(base + 32));
	float4 r3 = asfloat(ObjectData.Load4(base + 48));
	return float4x4(r0, r1, r2, r3);
}
#else
// CPU path: per-object data via dynamic-offset uniform buffer.
cbuffer ObjectUniforms : register(b0, space1)
{
	float4x4 WorldMatrix;
	float4x4 PrevWorldMatrix;
	float4x4 NormalMatrix;
	uint ObjectID;
	uint MaterialID;
};
#endif

struct VSInput
{
	float3 Position : TEXCOORD0;
	float3 Normal   : TEXCOORD1;
	float2 TexCoord : TEXCOORD2;
	float4 Color    : TEXCOORD3;
	float3 Tangent  : TEXCOORD4;
#ifdef GPU_DRIVEN
	uint ObjectIndex : TEXCOORD5; // from instance buffer (slot 1, per-instance)
#endif
};

struct VSOutput
{
	float4 Position : SV_Position;
};

VSOutput VSMain(VSInput input)
{
	VSOutput output;
#ifdef GPU_DRIVEN
	float4x4 world = LoadObjectMatrix(input.ObjectIndex, 0);
#else
	float4x4 world = WorldMatrix;
#endif
	float4 worldPos = mul(float4(input.Position, 1.0), world);
	output.Position = mul(worldPos, ViewProjectionMatrix);
	return output;
}
