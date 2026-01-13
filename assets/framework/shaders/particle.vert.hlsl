// Particle Vertex Shader
// CPU-driven particle system with per-particle data
// Supports texture atlases, rotation, and stretched billboards

struct VSInput
{
    float3 position : POSITION;         // World position
    float2 size : TEXCOORD0;            // Width, height
    float4 color : COLOR;               // RGBA color with alpha
    float rotation : TEXCOORD1;         // Rotation angle in radians
    float2 texCoordOffset : TEXCOORD2;  // Atlas UV offset
    float2 texCoordScale : TEXCOORD3;   // Atlas UV scale (frame size)
    float2 velocity2D : TEXCOORD4;      // Velocity for stretched billboards
    uint vertexId : SV_VertexID;        // 0-3 for quad corners
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

// Particle uniform buffer (binding 1)
cbuffer ParticleUniforms : register(b1)
{
    // Render mode: 0=Billboard, 1=StretchedBillboard, 2=HorizontalBillboard, 3=VerticalBillboard
    uint renderMode;
    float stretchFactor;     // For stretched billboards
    float minStretchLength;  // Minimum length for stretched billboards
    uint useTexture;         // 1 = sample texture, 0 = procedural
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

    // Get camera right and up vectors from view matrix (row-major layout)
    float3 right = float3(view[0][0], view[0][1], view[0][2]);
    float3 up = float3(view[1][0], view[1][1], view[1][2]);

    uint cornerIndex = input.vertexId % 4;
    float2 corner = corners[cornerIndex];

    float3 worldPos;

    if (renderMode == 1) // Stretched Billboard
    {
        // Stretch along velocity direction
        float2 velocity = input.velocity2D;
        float speed = length(velocity);

        if (speed > 0.001)
        {
            float2 velDir = velocity / speed;

            // Calculate stretch length
            float stretchLen = max(speed * stretchFactor, minStretchLength);

            // Create local coordinate system: X along velocity, Y perpendicular
            float2 localX = velDir;
            float2 localY = float2(-velDir.y, velDir.x);

            // Scale corner: X is stretched, Y is width
            float2 scaledCorner = float2(
                corner.x * stretchLen,
                corner.y * input.size.y
            );

            // Transform to view-space offset
            float2 viewOffset = localX * scaledCorner.x + localY * scaledCorner.y;

            worldPos = input.position
                + right * viewOffset.x
                + up * viewOffset.y;
        }
        else
        {
            // No velocity - fall back to regular billboard
            worldPos = input.position
                + right * corner.x * input.size.x
                + up * corner.y * input.size.y;
        }
    }
    else if (renderMode == 2) // Horizontal Billboard (face up)
    {
        // Particles lie flat on XZ plane
        float cosR = cos(input.rotation);
        float sinR = sin(input.rotation);
        float2 rotatedCorner = float2(
            corner.x * cosR - corner.y * sinR,
            corner.x * sinR + corner.y * cosR
        );

        worldPos = input.position
            + float3(rotatedCorner.x * input.size.x, 0, rotatedCorner.y * input.size.y);
    }
    else if (renderMode == 3) // Vertical Billboard (face camera but stay upright)
    {
        // Use world up, billboard only horizontally
        float3 toCamera = normalize(cameraPosition - input.position);
        float3 worldUp = float3(0, 1, 0);
        float3 localRight = normalize(cross(worldUp, toCamera));

        float cosR = cos(input.rotation);
        float sinR = sin(input.rotation);
        float2 rotatedCorner = float2(
            corner.x * cosR - corner.y * sinR,
            corner.x * sinR + corner.y * cosR
        );

        worldPos = input.position
            + localRight * rotatedCorner.x * input.size.x
            + worldUp * rotatedCorner.y * input.size.y;
    }
    else // Default Billboard (face camera)
    {
        // Apply rotation
        float cosR = cos(input.rotation);
        float sinR = sin(input.rotation);
        float2 rotatedCorner = float2(
            corner.x * cosR - corner.y * sinR,
            corner.x * sinR + corner.y * cosR
        );

        worldPos = input.position
            + right * rotatedCorner.x * input.size.x
            + up * rotatedCorner.y * input.size.y;
    }

    output.position = mul(viewProjection, float4(worldPos, 1.0));

    // Apply atlas UV transformation
    float2 baseUV = uvs[cornerIndex];
    output.uv = input.texCoordOffset + baseUV * input.texCoordScale;

    output.color = input.color;

    return output;
}
