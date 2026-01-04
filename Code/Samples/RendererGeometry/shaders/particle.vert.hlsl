// Particle Vertex Shader for Sample
// Uses instancing: particle data in instance buffer, vertex ID for quad corners

struct VSInput
{
    // Per-instance data (from instance buffer)
    float3 position : POSITION;     // Particle world position
    float2 size : TEXCOORD0;        // Width, height
    float4 color : COLOR;           // RGBA
    float rotation : TEXCOORD1;     // Rotation in radians
    uint vertexId : SV_VertexID;    // 0-3 for quad corners
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

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

    // Quad corner offsets (0=BL, 1=BR, 2=TL, 3=TR)
    static const float2 corners[4] = {
        float2(-0.5, -0.5),
        float2( 0.5, -0.5),
        float2(-0.5,  0.5),
        float2( 0.5,  0.5)
    };

    static const float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    // Get camera right and up vectors from view matrix
    float3 right = float3(view[0][0], view[1][0], view[2][0]);
    float3 up = float3(view[0][1], view[1][1], view[2][1]);

    // Compute corner position with rotation
    uint cornerIndex = input.vertexId % 4;
    float2 corner = corners[cornerIndex];

    // Apply rotation
    float cosR = cos(input.rotation);
    float sinR = sin(input.rotation);
    float2 rotatedCorner = float2(
        corner.x * cosR - corner.y * sinR,
        corner.x * sinR + corner.y * cosR
    );

    float3 worldPos = input.position
        + right * rotatedCorner.x * input.size.x
        + up * rotatedCorner.y * input.size.y;

    output.position = mul(viewProjection, float4(worldPos, 1.0));
    output.uv = uvs[cornerIndex];
    output.color = input.color;

    return output;
}
