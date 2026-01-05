// Decal Fragment Shader
// Projects decal texture onto scene geometry using depth buffer

struct PSInput
{
    float4 position : SV_Position;
    float4 clipPos : TEXCOORD0;
    float4x4 invDecalMatrix : TEXCOORD1;
};

// Camera uniform buffer (binding 0)
cbuffer CameraUniforms : register(b0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

// Inverse view-projection for world reconstruction
cbuffer DecalParams : register(b1)
{
    float4x4 invViewProjection;
    float4 decalColor;
};

// Depth buffer for scene
Texture2D depthTexture : register(t0);

// Decal texture
Texture2D decalTexture : register(t1);
SamplerState decalSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    // Get screen UV
    float2 screenUV = input.clipPos.xy / input.clipPos.w * 0.5 + 0.5;
    screenUV.y = 1.0 - screenUV.y; // Flip Y for texture sampling

    // Sample depth
    float depth = depthTexture.Load(int3(input.position.xy, 0)).r;

    // Reconstruct world position from depth
    float4 clipPos = float4(screenUV * 2.0 - 1.0, depth, 1.0);
    clipPos.y = -clipPos.y;
    float4 worldPos = mul(invViewProjection, clipPos);
    worldPos /= worldPos.w;

    // Transform to decal local space
    float4 localPos = mul(input.invDecalMatrix, worldPos);

    // Check if point is inside decal box (-0.5 to 0.5)
    if (abs(localPos.x) > 0.5 || abs(localPos.y) > 0.5 || abs(localPos.z) > 0.5)
        discard;

    // Compute decal UVs from local XZ position
    float2 decalUV = localPos.xz + 0.5;

    // Sample decal texture
    float4 decalSample = decalTexture.Sample(decalSampler, decalUV);

    // Apply tint color
    float4 finalColor = decalSample * decalColor;

    return finalColor;
}
