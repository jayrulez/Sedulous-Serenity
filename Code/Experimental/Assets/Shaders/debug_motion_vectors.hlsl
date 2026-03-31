// Debug visualization for motion vectors
// Composites motion vectors as a color overlay on the scene.
// Direction → hue (red=right, green=up, blue=left, yellow=down)
// Magnitude → brightness
#pragma pack_matrix(row_major)

struct PSInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

Texture2D    SceneColorTex    : register(t0, space0);
Texture2D    MotionVectorTex  : register(t1, space0);
SamplerState LinearSampler    : register(s2, space0);

PSInput VSMain(uint vertexID : SV_VertexID)
{
    PSInput output;
    output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(output.TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return output;
}

float4 PSMain(PSInput input) : SV_Target
{
    float3 scene = SceneColorTex.Sample(LinearSampler, input.TexCoord).rgb;

    // ACES tonemap + gamma (same as blit_tonemap)
    float3 x = scene;
    float a = 2.51; float b = 0.03; float c = 2.43; float d = 0.59; float e = 0.14;
    float3 tonemapped = saturate((x * (a * x + b)) / (x * (c * x + d) + e));
    tonemapped = pow(tonemapped, 1.0 / 2.2);

    // Sample motion vector (pixel-space velocity in RG)
    float2 mv = MotionVectorTex.Sample(LinearSampler, input.TexCoord).rg;

    // Visualize: map velocity to color
    float magnitude = length(mv);
    float2 dir = (magnitude > 0.001) ? mv / magnitude : float2(0, 0);

    // Color: positive X = red, negative X = cyan, positive Y = green, negative Y = magenta
    float3 mvColor = float3(
        saturate(dir.x) + saturate(-dir.y) * 0.5,   // R
        saturate(-dir.x) * 0.5 + saturate(dir.y),   // G
        saturate(-dir.x) + saturate(-dir.y) * 0.5    // B
    );

    // Scale brightness by magnitude (log scale for visibility)
    float brightness = saturate(log2(1.0 + magnitude) * 0.3);

    // Composite: blend motion vector color over tonemapped scene
    float3 result = lerp(tonemapped, mvColor, brightness);

    return float4(result, 1.0);
}
