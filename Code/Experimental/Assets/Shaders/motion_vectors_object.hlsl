// Per-object motion vector shader
// Renders geometry and outputs per-pixel velocity from current vs previous frame positions.
// Used for both static meshes (PrevWorldMatrix) and skinned meshes (PrevPosition vertex buffer).
//
// Static meshes: prevWorldPos = PrevWorldMatrix * position (vertex slot 0 only)
// Skinned meshes: prevWorldPos = PrevWorldMatrix * prevPosition (prevPosition from vertex slot 1)
//
// The SKINNED define controls which path is used. Both compile from the same file.
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
    uint FrameNumber;      uint LightCount; uint ShadowCascadeCount; float Exposure;
    float AmbientIntensity; float SkyExposure; float _scenePad2; float _scenePad3;
};

// Object bind group at Set 1 (no material set — empty material layout)
cbuffer ObjectUniforms : register(b0, space1)
{
    float4x4 WorldMatrix;
    float4x4 PrevWorldMatrix;
    float4x4 NormalMatrix;
    uint ObjectID;
    uint MaterialID;
};

struct VSInput
{
    float3 Position : TEXCOORD0;
    float3 Normal   : TEXCOORD1;
    float2 TexCoord : TEXCOORD2;
    float4 Color    : TEXCOORD3;
    float3 Tangent  : TEXCOORD4;
#ifdef SKINNED
    // Previous-frame skinned position from vertex slot 1
    float3 PrevPosition : TEXCOORD5;
#endif
};

struct VSOutput
{
    float4 Position     : SV_Position;
    float4 CurrentClip  : TEXCOORD0;
    float4 PrevClip     : TEXCOORD1;
};

VSOutput VSMain(VSInput input)
{
    VSOutput output;

    // Current frame: position * WorldMatrix * ViewProjectionMatrix
    float4 worldPos = mul(float4(input.Position, 1.0), WorldMatrix);
    output.CurrentClip = mul(worldPos, ViewProjectionMatrix);
    output.Position = output.CurrentClip;

    // Previous frame position
#ifdef SKINNED
    // Skinned: use previous-frame skinned position from compute shader output
    float4 prevWorldPos = mul(float4(input.PrevPosition, 1.0), PrevWorldMatrix);
#else
    // Static: same local position, different world matrix
    float4 prevWorldPos = mul(float4(input.Position, 1.0), PrevWorldMatrix);
#endif
    output.PrevClip = mul(prevWorldPos, PrevViewProjectionMatrix);

    return output;
}

float4 PSMain(VSOutput input) : SV_Target
{
    // Convert clip → NDC
    float2 currentNDC = input.CurrentClip.xy / input.CurrentClip.w;
    float2 prevNDC    = input.PrevClip.xy / input.PrevClip.w;

    // Motion vector in pixel space
    float2 velocity = (currentNDC - prevNDC) * 0.5 * ScreenSize;

    return float4(velocity, 0.0, 1.0);
}
