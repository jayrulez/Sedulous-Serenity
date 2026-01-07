// Decal Vertex Shader
// Screen-space decal projection using deferred depth

struct VSInput
{
    float3 position : POSITION;
};

struct VSOutput
{
    float4 position : SV_Position;
    float4 clipPos : TEXCOORD0;
    float4x4 invDecalMatrix : TEXCOORD1; // Rows 1-4 in TEXCOORD1-4
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

// Decal uniform buffer (binding 2)
cbuffer DecalUniforms : register(b2)
{
    float4x4 decalMatrix;      // World transform of decal box
    float4x4 invDecalMatrix_;  // Inverse of decal matrix
    float4 decalColor;         // Tint color
    float2 decalSize;          // Size in XZ plane
    float decalDepth;          // Depth/thickness
    float _pad1;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Transform decal box vertex to clip space
    float4 worldPos = mul(decalMatrix, float4(input.position, 1.0));
    output.position = mul(viewProjection, worldPos);
    output.clipPos = output.position;

    // Pass inverse decal matrix to fragment shader
    output.invDecalMatrix = invDecalMatrix_;

    return output;
}
