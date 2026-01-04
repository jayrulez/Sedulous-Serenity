// Lighting Sample - Vertex Shader
// Supports instancing for multiple objects

struct VSInput
{
    // Per-vertex data (location 0-2)
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;

    // Per-instance data (location 3-7)
    float4 instanceRow0 : TEXCOORD1;     // Model matrix row 0
    float4 instanceRow1 : TEXCOORD2;     // Model matrix row 1
    float4 instanceRow2 : TEXCOORD3;     // Model matrix row 2
    float4 instanceRow3 : TEXCOORD4;     // Model matrix row 3
    float4 instanceMaterial : TEXCOORD5; // x=metallic, y=roughness
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float2 material : TEXCOORD3;  // x=metallic, y=roughness
    float viewZ : TEXCOORD4;      // View-space Z for shadow cascade selection
};

// Camera uniform buffer
cbuffer CameraUniforms : register(b0)
{
    column_major float4x4 viewProjection;
    column_major float4x4 view;
    column_major float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Reconstruct model matrix from instance data rows
    float4x4 model = float4x4(
        input.instanceRow0,
        input.instanceRow1,
        input.instanceRow2,
        input.instanceRow3
    );

    float4 localPos = float4(input.position, 1.0);

    // Transform to world space
    float4 worldPos = mul(model, localPos);
    output.worldPos = worldPos.xyz;

    // Transform normal (using upper 3x3 of model matrix)
    float3x3 normalMatrix = (float3x3)model;
    output.worldNormal = normalize(mul(normalMatrix, input.normal));

    output.uv = input.uv;

    // Pass material parameters to fragment shader
    output.material = input.instanceMaterial.xy;

    // Compute view-space Z for shadow cascade selection
    float4 viewPos = mul(view, worldPos);
    output.viewZ = viewPos.z;

    // Transform to clip space
    output.position = mul(viewProjection, worldPos);

    return output;
}
