#pragma pack_matrix(row_major)

static const float PI = 3.14159265359;

// === Scene Data (Set 0) ===

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
	float AmbientIntensity; float SkyExposure; uint ProbeCount; float _scenePad3;
};

struct GPULightData
{
	float4 PositionAndRange;       // xyz=pos, w=range
	float4 DirectionAndSpotInner;  // xyz=dir, w=innerConeAngle
	float4 ColorAndIntensity;      // xyz=color, w=intensity
	uint   Type;                   // 0=directional, 1=point, 2=spot
	float  SpotOuterAngle;
	float  AreaWidth;
	float  AreaHeight;
	uint   ShadowIndex;
	uint   Flags;
	float2 _pad;
};

StructuredBuffer<GPULightData> LightBuffer : register(t1, space0);

struct ClusterData
{
	uint offset;
	uint count;
};

StructuredBuffer<ClusterData> ClusterGrid    : register(t2, space0);
StructuredBuffer<uint>        LightIndexList : register(t3, space0);

cbuffer ShadowUniforms : register(b4, space0)
{
	float4x4 CascadeViewProjection[4];
	float4   CascadeDistances;    // view-space far Z per cascade
	float4   ShadowParams;        // x=depthBias, y=normalBias, z=blendRange, w=cascadeCount
};

Texture2DArray         CascadeShadowMap : register(t5, space0);
SamplerComparisonState ShadowSampler    : register(s6, space0);

// Shadow atlas (point/spot lights)
Texture2D              ShadowAtlas      : register(t7, space0);

struct GPUShadowData
{
	float4x4 ViewProjection;
	float4   UVOffsetScale;  // xy=offset, zw=scale
	float4   Params;         // x=bias, y=nearPlane, z=farPlane, w=lightType (0=spot, 1=point)
};

StructuredBuffer<GPUShadowData> ShadowData : register(t8, space0);

// IBL (Image-Based Lighting)
TextureCube IrradianceMap   : register(t9, space0);
TextureCube PrefilteredMap  : register(t10, space0);
Texture2D   BRDFLutTexture  : register(t11, space0);

// Reflection probes
TextureCubeArray ProbeArray : register(t12, space0);

struct GPUProbeData
{
	float3 Position;
	float  _pad1;
	float3 BoxMin;
	float  _pad2;
	float3 BoxMax;
	uint   LayerIndex;
};

cbuffer ProbeUniforms : register(b13, space0)
{
	uint ProbeDataCount;
	float3 _probeUniformsPad;
	GPUProbeData ProbeDataArray[16];
};

static const uint CLUSTER_X = 16;
static const uint CLUSTER_Y = 9;
static const uint CLUSTER_Z = 24;

// === Material Data (Set 1) ===

cbuffer MaterialProperties : register(b0, space1)
{
	float4 AlbedoColor;
	float  Metallic;
	float  Roughness;
	float  AO;
	float  EmissiveStrength;
	float4 EmissiveColor;
};

Texture2D    AlbedoTex      : register(t1, space1);
Texture2D    NormalTex       : register(t2, space1);
Texture2D    MetRoughTex    : register(t3, space1);
SamplerState MaterialSampler : register(s4, space1);

// === Object Data (Set 2) ===

#ifdef GPU_DRIVEN
ByteAddressBuffer ObjectData : register(t0, space2);

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
cbuffer ObjectUniforms : register(b0, space2)
{
	float4x4 WorldMatrix;
	float4x4 PrevWorldMatrix;
	float4x4 NormalMatrix;
	uint ObjectID;
	uint MaterialID;
};
#endif

// === Vertex Shader ===

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

struct PSInput
{
	float4 ClipPos     : SV_Position;
	float3 WorldPos    : TEXCOORD0;
	float3 WorldNormal : TEXCOORD1;
	float2 TexCoord    : TEXCOORD2;
	float4 Color       : TEXCOORD3;
	float3 WorldTangent: TEXCOORD4;
};

PSInput VSMain(VSInput input)
{
	PSInput output;
#ifdef GPU_DRIVEN
	float4x4 world = LoadObjectMatrix(input.ObjectIndex, 0);
	float4x4 normalMat = LoadObjectMatrix(input.ObjectIndex, 128);
#else
	float4x4 world = WorldMatrix;
	float4x4 normalMat = NormalMatrix;
#endif
	float4 worldPos = mul(float4(input.Position, 1.0), world);
	output.ClipPos = mul(worldPos, ViewProjectionMatrix);
	output.WorldPos = worldPos.xyz;
	output.WorldNormal = normalize(mul(float4(input.Normal, 0.0), normalMat).xyz);
	output.TexCoord = input.TexCoord;
	output.Color = input.Color;
	output.WorldTangent = normalize(mul(float4(input.Tangent, 0.0), world).xyz);
	return output;
}

// === PBR Functions ===

float DistributionGGX(float3 N, float3 H, float roughness)
{
	float a = roughness * roughness;
	float a2 = a * a;
	float NdotH = max(dot(N, H), 0.0);
	float NdotH2 = NdotH * NdotH;
	float denom = NdotH2 * (a2 - 1.0) + 1.0;
	return a2 / (PI * denom * denom);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
	float r = roughness + 1.0;
	float k = (r * r) / 8.0;
	return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
	float NdotV = max(dot(N, V), 0.0);
	float NdotL = max(dot(N, L), 0.0);
	return GeometrySchlickGGX(NdotV, roughness) * GeometrySchlickGGX(NdotL, roughness);
}

float3 FresnelSchlick(float cosTheta, float3 F0)
{
	return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
	float3 maxF0 = max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0);
	return F0 + (maxF0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// === Lighting Helpers ===

float DistanceAttenuation(float distance, float range)
{
	float ratio = distance / range;
	float ratio2 = ratio * ratio;
	float ratio4 = ratio2 * ratio2;
	float falloff = saturate(1.0 - ratio4);
	return (falloff * falloff) / (distance * distance + 1.0);
}

float SpotAttenuation(float3 toLight, float3 spotDir, float innerAngle, float outerAngle)
{
	float cosAngle = dot(normalize(-toLight), spotDir);
	return smoothstep(cos(outerAngle), cos(innerAngle), cosAngle);
}

float3 EvaluateBRDF(float3 N, float3 V, float3 L, float3 F0, float3 albedo, float metallic, float roughness)
{
	float3 H = normalize(V + L);
	float NdotL = max(dot(N, L), 0.0);

	float  D = DistributionGGX(N, H, roughness);
	float  G = GeometrySmith(N, V, L, roughness);
	float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

	float3 numerator = D * G * F;
	float denominator = 4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001;
	float3 specular = numerator / denominator;

	float3 kD = (1.0 - F) * (1.0 - metallic);
	return (kD * albedo / PI + specular) * NdotL;
}

// === Shadow Sampling ===

static const float SHADOW_MAP_SIZE = 2048.0;

float SampleShadowCascade(float3 worldPos, uint cascade)
{
	float4 shadowCoord = mul(float4(worldPos, 1.0), CascadeViewProjection[cascade]);
	shadowCoord.xyz /= shadowCoord.w;
	// NDC to UV: [-1,1] → [0,1], flip Y
	float2 shadowUV = shadowCoord.xy * float2(0.5, -0.5) + 0.5;
	float depth = saturate(shadowCoord.z) - ShadowParams.x;

	// 5x5 PCF for smooth shadow edges
	float shadow = 0.0;
	float2 texelSizeUV = 1.0 / float2(SHADOW_MAP_SIZE, SHADOW_MAP_SIZE);
	for (int x = -2; x <= 2; x++)
	{
		for (int y = -2; y <= 2; y++)
		{
			float2 offset = float2(x, y) * texelSizeUV;
			shadow += CascadeShadowMap.SampleCmpLevelZero(
				ShadowSampler, float3(shadowUV + offset, cascade), depth);
		}
	}
	return shadow / 25.0;
}

/// Returns 0..1 fade factor based on how close the UV is to the shadow map edge.
/// 1.0 = fully inside, 0.0 = at or beyond the edge.
float ShadowEdgeFade(float3 worldPos, uint cascade)
{
	float4 shadowCoord = mul(float4(worldPos, 1.0), CascadeViewProjection[cascade]);
	shadowCoord.xyz /= shadowCoord.w;
	float2 shadowUV = shadowCoord.xy * float2(0.5, -0.5) + 0.5;
	// Distance from nearest edge (0 at edge, 0.5 at center)
	float2 distFromEdge = min(shadowUV, 1.0 - shadowUV);
	float fade = saturate(min(distFromEdge.x, distFromEdge.y) * 20.0); // 5% border fade
	// Also fade based on depth range
	fade *= saturate(shadowCoord.z * 20.0) * saturate((1.0 - shadowCoord.z) * 20.0);
	return fade;
}

float SampleCascadedShadow(float3 worldPos, float viewZ)
{
	if (ShadowCascadeCount == 0)
		return 1.0;

	// Find cascade
	uint cascade = ShadowCascadeCount - 1;
	for (uint i = 0; i < ShadowCascadeCount; i++)
	{
		if (viewZ < CascadeDistances[i])
		{
			cascade = i;
			break;
		}
	}

	float shadow = SampleShadowCascade(worldPos, cascade);

	// Fade out at the edge of the outermost cascade to avoid hard cutoff
	if (cascade == ShadowCascadeCount - 1)
	{
		float edgeFade = ShadowEdgeFade(worldPos, cascade);
		shadow = lerp(1.0, shadow, edgeFade);
	}

	return shadow;
}

// === Atlas Shadow Sampling (Point/Spot) ===

static const float SHADOW_ATLAS_SIZE = 4096.0;
static const float SHADOW_ATLAS_TILE_SIZE = 512.0;

float SampleShadowAtlasTile(float3 worldPos, uint shadowIndex)
{
	GPUShadowData sd = ShadowData[shadowIndex];
	float4 shadowCoord = mul(float4(worldPos, 1.0), sd.ViewProjection);
	shadowCoord.xyz /= shadowCoord.w;
	// NDC to UV within tile: [-1,1] → [0,1]
	float2 ndcUV = shadowCoord.xy * float2(0.5, -0.5) + 0.5;

	// Out of tile bounds → lit
	if (any(ndcUV < 0.0) || any(ndcUV > 1.0))
		return 1.0;

	// Map to atlas UV via offset/scale
	float2 atlasUV = ndcUV * sd.UVOffsetScale.zw + sd.UVOffsetScale.xy;
	float depth = saturate(shadowCoord.z) - sd.Params.x;

	// 3x3 PCF — texel size in atlas UV space
	float2 atlasTexelSize = 1.0 / float2(SHADOW_ATLAS_SIZE, SHADOW_ATLAS_SIZE);
	float shadow = 0.0;
	for (int x = -1; x <= 1; x++)
	{
		for (int y = -1; y <= 1; y++)
		{
			float2 offset = float2(x, y) * atlasTexelSize;
			shadow += ShadowAtlas.SampleCmpLevelZero(ShadowSampler, atlasUV + offset, depth);
		}
	}
	return shadow / 9.0;
}

float SampleSpotLightShadow(float3 worldPos, uint shadowIndex)
{
	return SampleShadowAtlasTile(worldPos, shadowIndex);
}

float SamplePointLightShadow(float3 worldPos, float3 lightPos, uint shadowIndex)
{
	// Determine cubemap face from light-to-fragment direction
	float3 lightToFrag = worldPos - lightPos;
	float3 absDir = abs(lightToFrag);

	uint faceIndex;
	if (absDir.x >= absDir.y && absDir.x >= absDir.z)
		faceIndex = (lightToFrag.x > 0.0) ? 0 : 1; // +X or -X
	else if (absDir.y >= absDir.x && absDir.y >= absDir.z)
		faceIndex = (lightToFrag.y > 0.0) ? 2 : 3; // +Y or -Y
	else
		faceIndex = (lightToFrag.z > 0.0) ? 4 : 5; // +Z or -Z

	return SampleShadowAtlasTile(worldPos, shadowIndex + faceIndex);
}

// === Fragment Shader ===

// Octahedral normal encoding: maps unit sphere normal to [0,1]x[0,1]
float2 OctahedralEncode(float3 n)
{
	n /= (abs(n.x) + abs(n.y) + abs(n.z));
	if (n.z < 0)
		n.xy = (1.0 - abs(n.yx)) * select(n.xy >= 0, 1.0, -1.0);
	return n.xy * 0.5 + 0.5;
}

struct PSOutput
{
	float4 Color  : SV_Target0;  // HDR scene color
	float4 GBuffer : SV_Target1; // RG: octahedral normal, B: roughness, A: metallic
};

PSOutput PSMain(PSInput input)
{
	PSOutput output;
	// Sample textures
	float4 albedoSample = AlbedoTex.Sample(MaterialSampler, input.TexCoord);
	float4 albedo = albedoSample * AlbedoColor * input.Color;

	float3 metRough = MetRoughTex.Sample(MaterialSampler, input.TexCoord).rgb;
	float metallic = metRough.b * Metallic;
	float roughness = max(metRough.g * Roughness, 0.04);

	float3 N = normalize(input.WorldNormal);
	float3 V = normalize(CameraPosition - input.WorldPos);

	// Fresnel reflectance at normal incidence
	float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo.rgb, metallic);

	// Cluster-based light lookup (Forward+)
	float3 Lo = float3(0, 0, 0);

	// Compute cluster index from screen position and depth
	// abs() because RH view space has negative Z for visible objects;
	// log(negative) is NaN which breaks cluster lookup
	float viewZ = abs(mul(float4(input.WorldPos, 1.0), ViewMatrix).z);
	uint clusterX = min((uint)(input.ClipPos.x / ScreenSize.x * CLUSTER_X), CLUSTER_X - 1);
	uint clusterY = min((uint)(input.ClipPos.y / ScreenSize.y * CLUSTER_Y), CLUSTER_Y - 1);
	// Exponential depth slice: inverse of depth(z) = near * pow(far/near, z/CLUSTER_Z)
	float logRatio = log(viewZ / NearPlane) / log(FarPlane / NearPlane);
	uint clusterZ = min((uint)(logRatio * CLUSTER_Z), CLUSTER_Z - 1);

	uint flatCluster = clusterX + clusterY * CLUSTER_X + clusterZ * CLUSTER_X * CLUSTER_Y;
	ClusterData cluster = ClusterGrid[flatCluster];

	for (uint ci = 0; ci < cluster.count; ci++)
	{
		uint lightIdx = LightIndexList[cluster.offset + ci];
		GPULightData light = LightBuffer[lightIdx];
		float3 lightColor = light.ColorAndIntensity.xyz;
		float lightIntensity = light.ColorAndIntensity.w;
		float3 L;
		float attenuation = 1.0;

		if (light.Type == 0) // Directional
		{
			L = normalize(-light.DirectionAndSpotInner.xyz);
		}
		else // Point or Spot
		{
			float3 toLight = light.PositionAndRange.xyz - input.WorldPos;
			float dist = length(toLight);
			L = toLight / max(dist, 0.0001);
			attenuation = DistanceAttenuation(dist, light.PositionAndRange.w);

			if (light.Type == 2) // Spot
			{
				float3 spotDir = normalize(light.DirectionAndSpotInner.xyz);
				attenuation *= SpotAttenuation(toLight, spotDir, light.DirectionAndSpotInner.w, light.SpotOuterAngle);
			}
		}

		float3 radiance = lightColor * lightIntensity * attenuation;

		// Apply shadows
		if (light.ShadowIndex != 0xFFFFFFFF)
		{
			float shadow = 1.0;
			if (light.Type == 0) // Directional → cascaded shadow maps
				shadow = SampleCascadedShadow(input.WorldPos, viewZ);
			else if (light.Type == 1) // Point → atlas (6-face cubemap)
				shadow = SamplePointLightShadow(input.WorldPos, light.PositionAndRange.xyz, light.ShadowIndex);
			else if (light.Type == 2) // Spot → atlas (single tile)
				shadow = SampleSpotLightShadow(input.WorldPos, light.ShadowIndex);
			radiance *= shadow;
		}

		Lo += EvaluateBRDF(N, V, L, F0, albedo.rgb, metallic, roughness) * radiance;
	}

	// IBL ambient lighting
	float NdotV_ibl = max(dot(N, V), 0.0);
	float3 F_ibl = FresnelSchlickRoughness(NdotV_ibl, F0, roughness);
	float3 kD_ibl = (1.0 - F_ibl) * (1.0 - metallic);

	// Diffuse IBL: sample irradiance cubemap (use material sampler — linear, clamp)
	float3 diffuseIBL = IrradianceMap.Sample(MaterialSampler, N).rgb * albedo.rgb;

	// Specular IBL: sample prefiltered environment map + BRDF LUT
	float3 R = reflect(-V, N);
	float3 prefilteredColor = PrefilteredMap.SampleLevel(MaterialSampler, R, roughness * 4.0).rgb;
	float2 envBRDF = BRDFLutTexture.Sample(MaterialSampler, float2(NdotV_ibl, roughness)).rg;
	float3 specularIBL = prefilteredColor * (F0 * envBRDF.x + envBRDF.y);

	// Reflection probes: override specular IBL with local probe reflections
	if (ProbeDataCount > 0)
	{
		float3 probeContrib = float3(0, 0, 0);
		float totalWeight = 0.0;

		for (uint pi = 0; pi < ProbeDataCount; pi++)
		{
			GPUProbeData probe = ProbeDataArray[pi];

			// Check if fragment is inside probe's influence box
			if (all(input.WorldPos >= probe.BoxMin) && all(input.WorldPos <= probe.BoxMax))
			{
				// Box parallax correction: re-project reflection vector to hit the box
				float3 firstPlane  = (probe.BoxMax - input.WorldPos) / R;
				float3 secondPlane = (probe.BoxMin - input.WorldPos) / R;
				float3 furthest = max(firstPlane, secondPlane);
				float hitDist = min(min(furthest.x, furthest.y), furthest.z);
				float3 hitPoint = input.WorldPos + R * hitDist;
				float3 correctedR = normalize(hitPoint - probe.Position);

				// Sample probe cubemap at the corrected reflection direction
				float3 probeColor = ProbeArray.SampleLevel(MaterialSampler,
					float4(correctedR, (float)probe.LayerIndex), roughness * 4.0).rgb;

				// Weight by distance to probe center (quadratic falloff)
				float dist = length(input.WorldPos - probe.Position);
				float boxSize = length(probe.BoxMax - probe.BoxMin);
				float weight = saturate(1.0 - dist / (boxSize * 0.5));
				weight *= weight;

				probeContrib += probeColor * weight;
				totalWeight += weight;
			}
		}

		if (totalWeight > 0.0)
		{
			probeContrib /= totalWeight;
			// Apply same BRDF weighting as global IBL specular
			float3 probeSpecular = probeContrib * (F0 * envBRDF.x + envBRDF.y);
			// Blend probe reflections over global IBL specular
			specularIBL = lerp(specularIBL, probeSpecular, saturate(totalWeight));
		}
	}

	float3 ambient = (kD_ibl * diffuseIBL + specularIBL) * AO * AmbientIntensity;

	// Emissive
	float3 emissive = EmissiveColor.rgb * EmissiveStrength;

	// Apply scene exposure
	float3 finalColor = (Lo + ambient + emissive) * Exposure;

	output.Color = float4(finalColor, albedo.a);

	// G-Buffer: octahedral normal + roughness + metallic
	float2 encodedNormal = OctahedralEncode(N);
	output.GBuffer = float4(encodedNormal, roughness, metallic);

	return output;
}
