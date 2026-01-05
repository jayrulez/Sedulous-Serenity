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
    // For row-major view matrix, extract the 3x3 rotation part
    // Row 0 = right, Row 1 = up, Row 2 = forward
    float3 right = float3(view[0][0], view[0][1], view[0][2]);
    float3 up = float3(view[1][0], view[1][1], view[1][2]);
    float3 forward = float3(view[2][0], view[2][1], view[2][2]);

    // Unproject from clip space to view direction
    // projection[0][0] = 1/(aspect*tan(fov/2)), projection[1][1] = 1/tan(fov/2)
    float3 viewDir = normalize(float3(
        pos.x / projection[0][0],
        pos.y / projection[1][1],
        -1.0
    ));

    // Transform from view space to world space using inverse view rotation
    // Inverse of rotation matrix = transpose, so world = viewDir.x*right + viewDir.y*up + viewDir.z*forward
    output.texCoord = viewDir.x * right + viewDir.y * up + viewDir.z * forward;

    return output;
}
