// Grass Vertex Shader
// Instanced cross-blade mesh with wind animation
#pragma pack_matrix(row_major)

#include "scene_uniforms.hlsli"

cbuffer GrassUniforms : register(b0, space1)
{
    float3 GrassColor;
    float AlphaCutoff;
    float WindStrength;
    float WindFrequency;
    float2 WindDirection;
    float Roughness;
    float BladeWidth;
    float BladeHeight;
    float FadeStart;
    float FadeEnd;
    float3 _Pad;
};

struct VertexInput
{
    float3 LocalPos : POSITION;        // Blade-local position (0..1 height)
    float2 UV       : TEXCOORD0;       // UV (v=0 root, v=1 tip)
    float4 InstancePosScale : ATTRIB0; // Per-instance: xyz=world pos, w=scale
};

struct VertexOutput
{
    float4 Position      : SV_Position;
    float3 WorldPosition : TEXCOORD0;
    float2 UV            : TEXCOORD1;
    float  FadeAlpha     : TEXCOORD2;
};

// Deterministic hash from world position for per-blade Y rotation
float HashRotation(float2 pos)
{
    float h = dot(pos, float2(127.1, 311.7));
    return frac(sin(h) * 43758.5453) * 6.2831853; // 0..2*PI
}

VertexOutput main(VertexInput input)
{
    VertexOutput output;

    float3 instancePos = input.InstancePosScale.xyz;
    float instanceScale = input.InstancePosScale.w;

    // Scale blade mesh with taper (wider at root, narrow at tip)
    float taper = 1.0 - input.UV.y * 0.7; // 1.0 at root, 0.3 at tip
    float3 localPos = input.LocalPos;
    localPos.x *= BladeWidth * instanceScale * taper;
    localPos.z *= BladeWidth * instanceScale * taper;
    localPos.y *= BladeHeight * instanceScale;

    // Y-axis rotation derived from world position
    float angle = HashRotation(instancePos.xz);
    float sa = sin(angle);
    float ca = cos(angle);
    float3 rotated;
    rotated.x = localPos.x * ca - localPos.z * sa;
    rotated.y = localPos.y;
    rotated.z = localPos.x * sa + localPos.z * ca;

    // Wind displacement (tip only, weighted by UV.y)
    float windPhase = dot(instancePos.xz, WindDirection) * 0.3 + Time * WindFrequency;
    float windOffset = sin(windPhase) * WindStrength * input.UV.y * input.UV.y * instanceScale;
    rotated.x += windOffset * WindDirection.x;
    rotated.z += windOffset * WindDirection.y;

    // World position
    float3 worldPos = instancePos + rotated;

    // Distance fade
    float dist = length(worldPos.xz - CameraPosition.xz);
    float fadeAlpha = 1.0 - saturate((dist - FadeStart) / max(FadeEnd - FadeStart, 0.001));

    output.Position = mul(float4(worldPos, 1.0), ViewProjectionMatrix);
    output.WorldPosition = worldPos;
    output.UV = input.UV;
    output.FadeAlpha = fadeAlpha;

    return output;
}
