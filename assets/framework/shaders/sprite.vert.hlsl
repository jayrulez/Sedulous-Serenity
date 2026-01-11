// Sprite/Billboard Vertex Shader
// Renders screen-aligned quads from point positions

struct VSInput
{
    float3 position : POSITION;     // World position of sprite center
    float2 size : TEXCOORD0;        // Width, height in world units
    float4 uvRect : TEXCOORD1;      // UV rectangle (minU, minV, maxU, maxV)
    float4 color : COLOR;           // Tint color
    uint vertexId : SV_VertexID;    // 0-3 for quad corners
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
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

VSOutput main(VSInput input)
{
    VSOutput output;

    // Quad corner offsets for 6 vertices (2 triangles)
    // Triangle 1: BL, BR, TL (0, 1, 2)
    // Triangle 2: TL, BR, TR (3, 4, 5)
    static const float2 corners[6] = {
        float2(-0.5, -0.5),  // 0: Bottom-left
        float2( 0.5, -0.5),  // 1: Bottom-right
        float2(-0.5,  0.5),  // 2: Top-left
        float2(-0.5,  0.5),  // 3: Top-left
        float2( 0.5, -0.5),  // 4: Bottom-right
        float2( 0.5,  0.5)   // 5: Top-right
    };

    // Get camera right and up vectors from view matrix (row-major layout)
    // Row 0 = right, Row 1 = up, Row 2 = forward
    float3 right = float3(view[0][0], view[0][1], view[0][2]);
    float3 up = float3(view[1][0], view[1][1], view[1][2]);

    // Compute corner position (6 vertices per quad)
    uint cornerIndex = input.vertexId % 6;
    float2 corner = corners[cornerIndex];
    float3 worldPos = input.position
        + right * corner.x * input.size.x
        + up * corner.y * input.size.y;

    output.position = mul(viewProjection, float4(worldPos, 1.0));

    // Compute UV from rect (6 vertices matching corner positions)
    float2 uvCorners[6] = {
        float2(input.uvRect.x, input.uvRect.w),  // 0: BL
        float2(input.uvRect.z, input.uvRect.w),  // 1: BR
        float2(input.uvRect.x, input.uvRect.y),  // 2: TL
        float2(input.uvRect.x, input.uvRect.y),  // 3: TL
        float2(input.uvRect.z, input.uvRect.w),  // 4: BR
        float2(input.uvRect.z, input.uvRect.y)   // 5: TR
    };
    output.uv = uvCorners[cornerIndex];

    output.color = input.color;

    return output;
}
