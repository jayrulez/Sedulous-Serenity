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

    // Quad corner offsets (0=BL, 1=BR, 2=TL, 3=TR)
    static const float2 corners[4] = {
        float2(-0.5, -0.5),  // Bottom-left
        float2( 0.5, -0.5),  // Bottom-right
        float2(-0.5,  0.5),  // Top-left
        float2( 0.5,  0.5)   // Top-right
    };

    // Get camera right and up vectors from view matrix
    float3 right = float3(view[0][0], view[1][0], view[2][0]);
    float3 up = float3(view[0][1], view[1][1], view[2][1]);

    // Compute corner position
    uint cornerIndex = input.vertexId % 4;
    float2 corner = corners[cornerIndex];
    float3 worldPos = input.position
        + right * corner.x * input.size.x
        + up * corner.y * input.size.y;

    output.position = mul(viewProjection, float4(worldPos, 1.0));

    // Compute UV from rect
    float2 uvCorners[4] = {
        float2(input.uvRect.x, input.uvRect.w),  // BL
        float2(input.uvRect.z, input.uvRect.w),  // BR
        float2(input.uvRect.x, input.uvRect.y),  // TL
        float2(input.uvRect.z, input.uvRect.y)   // TR
    };
    output.uv = uvCorners[cornerIndex];

    output.color = input.color;

    return output;
}
