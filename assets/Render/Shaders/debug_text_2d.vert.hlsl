// Debug 2D text vertex shader
// Uses orthographic projection for screen-space text rendering

#pragma pack_matrix(row_major)

cbuffer ScreenParams : register(b0)
{
    float2 screenSize;    // Screen width, height in pixels
    float flipY;          // 1.0 if Y needs flipping (Vulkan), 0.0 otherwise
    float padding;        // Padding for 16-byte alignment
};

struct VSInput
{
    float2 position : POSITION;   // Screen-space position (pixels)
    float2 texCoord : TEXCOORD0;
    float4 color : COLOR;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD0;
    float4 color : COLOR;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Convert from pixel coordinates to NDC (-1 to 1)
    // Origin is top-left, Y increases downward in screen space
    float2 ndc;
    ndc.x = (input.position.x / screenSize.x) * 2.0 - 1.0;

    // For OpenGL/DX: NDC Y up, so flip: ndc.y = 1.0 - (y/h)*2
    // For Vulkan: NDC Y down, so no flip: ndc.y = (y/h)*2 - 1.0
    float normalizedY = input.position.y / screenSize.y;
    ndc.y = lerp(1.0 - normalizedY * 2.0, normalizedY * 2.0 - 1.0, flipY);

    output.position = float4(ndc, 0.0, 1.0);
    output.texCoord = input.texCoord;
    output.color = input.color;
    return output;
}
