// Shadow map depth-only vertex shader for RendererNG
// Renders geometry from the light's perspective to generate shadow maps

// Use row-major matrix packing to match Beef's memory layout
#pragma pack_matrix(row_major)

// ============================================================================
// Light View-Projection Uniform
// ============================================================================

cbuffer ShadowUniforms : register(b0)
{
    float4x4 LightViewProjection;
};

// ============================================================================
// Instance Data (matches MeshInstanceData: WorldMatrix, NormalMatrix, CustomData)
// ============================================================================

// Instance attributes start at location 5 (after per-vertex: Position=0, Normal=1, UV=2, Color=3, Tangent=4)
// DXC maps TEXCOORD indices to SPIR-V locations automatically
struct InstanceInput
{
    float4 World0 : TEXCOORD5;   // WorldMatrix row 0
    float4 World1 : TEXCOORD6;   // WorldMatrix row 1
    float4 World2 : TEXCOORD7;   // WorldMatrix row 2
    float4 World3 : TEXCOORD8;   // WorldMatrix row 3
    float4 Normal0 : TEXCOORD9;  // NormalMatrix row 0 (unused in shadow)
    float4 Normal1 : TEXCOORD10; // NormalMatrix row 1 (unused in shadow)
    float4 Normal2 : TEXCOORD11; // NormalMatrix row 2 (unused in shadow)
    float4 Normal3 : TEXCOORD12; // NormalMatrix row 3 (unused in shadow)
    float4 CustomData : TEXCOORD13; // Custom data (unused in shadow)
};

// ============================================================================
// Vertex Input
// ============================================================================

struct VS_INPUT
{
    float3 Position : POSITION;
};

// ============================================================================
// Vertex Output
// ============================================================================

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
};

// ============================================================================
// Main Vertex Shader
// ============================================================================

VS_OUTPUT main(VS_INPUT input, InstanceInput instance)
{
    VS_OUTPUT output;

    // Reconstruct world matrix from instance data
    float4x4 worldMatrix = float4x4(
        instance.World0,
        instance.World1,
        instance.World2,
        instance.World3
    );

    // Transform to world space
    float4 worldPos = mul(float4(input.Position, 1.0), worldMatrix);

    // Transform to light clip space
    output.Position = mul(worldPos, LightViewProjection);

    return output;
}
