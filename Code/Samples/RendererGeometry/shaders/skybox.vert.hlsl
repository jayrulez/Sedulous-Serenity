// Skybox Vertex Shader
// Fullscreen triangle that samples cubemap based on view direction

struct VSInput
{
    uint vertexId : SV_VertexID;
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 texCoord : TEXCOORD0;
};

cbuffer CameraUniforms : register(b0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Fullscreen triangle vertices
    static const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    float2 pos = positions[input.vertexId];

    // Output position at far plane (z = 1 for standard depth)
    output.position = float4(pos, 1.0, 1.0);

    // Compute view direction from clip space position
    // Remove translation from view matrix to get rotation-only view
    float4x4 viewRotation = view;
    viewRotation[3] = float4(0, 0, 0, 1);
    viewRotation[0][3] = 0;
    viewRotation[1][3] = 0;
    viewRotation[2][3] = 0;

    // Transform to view space then to world space
    float4x4 invViewRotation = transpose(viewRotation); // Rotation inverse = transpose
    float4 viewDir = float4(pos.x / projection[0][0], pos.y / projection[1][1], -1.0, 0.0);
    output.texCoord = mul(invViewRotation, viewDir).xyz;

    return output;
}
