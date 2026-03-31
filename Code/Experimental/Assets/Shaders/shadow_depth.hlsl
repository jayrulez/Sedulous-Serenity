#pragma pack_matrix(row_major)

cbuffer ShadowPassUniforms : register(b0, space0)
{
	float4x4 LightViewProjection;
	float    NormalBias;
	float3   LightDirection;
};

#ifdef GPU_DRIVEN
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
	uint ObjectIndex : TEXCOORD5;
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
	float4x4 normalMat = LoadObjectMatrix(input.ObjectIndex, 128);
#else
	float4x4 world = WorldMatrix;
	float4x4 normalMat = NormalMatrix;
#endif
	float4 worldPos = mul(float4(input.Position, 1.0), world);

	// Normal offset bias: push along world normal to reduce shadow acne
	float3 worldNormal = normalize(mul(float4(input.Normal, 0.0), normalMat).xyz);
	worldPos.xyz += worldNormal * NormalBias;

	output.Position = mul(worldPos, LightViewProjection);
	return output;
}
