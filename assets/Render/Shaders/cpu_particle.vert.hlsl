// CPU Particle Render Vertex Shader
// Billboard rendering of CPU-simulated particles via instance buffer
// Supports: Billboard, StretchedBillboard, HorizontalBillboard, VerticalBillboard
#pragma pack_matrix(row_major)

// Must match SceneUniforms in FrameContext.bf
cbuffer CameraUniforms : register(b0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 InvViewMatrix;
    float4x4 InvProjectionMatrix;
    float4x4 PrevViewProjectionMatrix;
    float3 CameraPosition;
    float Time;
    float3 CameraForward;
    float DeltaTime;
    float2 ScreenSize;
    float CameraNearPlane;
    float CameraFarPlane;
};

// Per-emitter params (shared with fragment shader, extended)
cbuffer EmitterParams : register(b1)
{
    float SoftDistance;
    float NearPlane;
    float FarPlane;
    float RenderMode;       // 0=Billboard, 1=Stretched, 2=Horizontal, 3=Vertical
    float StretchFactor;
    float Lit;              // 0 = unlit, 1 = lit (unused in vertex)
    float2 _padding;
};

// Per-instance data from vertex buffer (CPUParticleVertex layout)
struct InstanceInput
{
    float3 Position : ATTRIB0;       // World position
    float2 Size : ATTRIB1;           // Billboard size
    float4 Color : ATTRIB2;          // RGBA color (unorm8x4)
    float Rotation : ATTRIB3;        // Rotation angle
    float4 TexCoordOffsetScale : ATTRIB4; // xy=offset, zw=scale
    float2 Velocity2D : ATTRIB5;     // Screen-space velocity for stretched billboard
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
    float4 Color : TEXCOORD1;
    float3 WorldPosition : TEXCOORD2;
};

VertexOutput main(uint vertexID : SV_VertexID, InstanceInput inst)
{
    VertexOutput output;

    // Quad vertex positions (2 triangles, 6 vertices)
    static const float2 quadOffsets[6] = {
        float2(-0.5, -0.5), // 0
        float2(0.5, -0.5),  // 1
        float2(-0.5, 0.5),  // 2
        float2(-0.5, 0.5),  // 2
        float2(0.5, -0.5),  // 1
        float2(0.5, 0.5)    // 3
    };

    static const float2 quadUVs[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };

    float2 offset = quadOffsets[vertexID];
    float3 worldPos;

    int mode = (int)RenderMode;

    if (mode == 1)
    {
        // --- Stretched Billboard ---
        // Align quad along velocity direction in world space
        float3 velocity = float3(inst.Velocity2D, 0.0);
        float speed = length(inst.Velocity2D);

        // View-space right/up
        float3 camRight = InvViewMatrix[0].xyz;
        float3 camUp = InvViewMatrix[1].xyz;

        if (speed > 0.001)
        {
            // Project velocity into view plane to get stretch direction
            float3 worldVel = float3(inst.Velocity2D.x, inst.Velocity2D.y, 0.0);
            // Velocity2D is stored as world-space XZ or view-space - use as view-aligned direction
            float2 velDir = normalize(inst.Velocity2D);

            // Stretch axis (along velocity) and perpendicular
            float2 stretchAxis = velDir;
            float2 perpAxis = float2(-velDir.y, velDir.x);

            // Apply stretch: X maps to velocity direction (stretched), Y maps to perpendicular
            float stretchedX = offset.x * (1.0 + speed * StretchFactor);
            float normalY = offset.y;

            // Compose the 2D offset in camera-aligned space
            float2 finalOffset2D = stretchAxis * stretchedX + perpAxis * normalY;

            // Apply size
            finalOffset2D *= inst.Size;

            worldPos = inst.Position +
                       camRight * finalOffset2D.x +
                       camUp * finalOffset2D.y;
        }
        else
        {
            // No velocity: fall back to standard billboard
            float2 sizedOffset = offset * inst.Size;
            worldPos = inst.Position +
                       camRight * sizedOffset.x +
                       camUp * sizedOffset.y;
        }
    }
    else if (mode == 2)
    {
        // --- Horizontal Billboard ---
        // Quad faces up (Y-axis normal), lies flat in XZ plane
        float cosR = cos(inst.Rotation);
        float sinR = sin(inst.Rotation);
        float2 rotatedOffset = float2(
            offset.x * cosR - offset.y * sinR,
            offset.x * sinR + offset.y * cosR
        );
        rotatedOffset *= inst.Size;

        worldPos = inst.Position + float3(rotatedOffset.x, 0.0, rotatedOffset.y);
    }
    else if (mode == 3)
    {
        // --- Vertical Billboard ---
        // Faces camera horizontally but locked to world Y-up
        float3 toCamera = CameraPosition - inst.Position;
        toCamera.y = 0.0;
        float lenXZ = length(toCamera);

        float3 right;
        if (lenXZ > 0.001)
        {
            float3 forward = toCamera / lenXZ;
            right = cross(float3(0, 1, 0), forward);
        }
        else
        {
            right = float3(1, 0, 0);
        }

        float3 up = float3(0, 1, 0);

        // Apply rotation around the billboard normal (forward axis)
        float cosR = cos(inst.Rotation);
        float sinR = sin(inst.Rotation);
        float2 rotatedOffset = float2(
            offset.x * cosR - offset.y * sinR,
            offset.x * sinR + offset.y * cosR
        );
        rotatedOffset *= inst.Size;

        worldPos = inst.Position +
                   right * rotatedOffset.x +
                   up * rotatedOffset.y;
    }
    else
    {
        // --- Standard Billboard (mode == 0) ---
        // Camera-facing billboard
        float cosR = cos(inst.Rotation);
        float sinR = sin(inst.Rotation);
        float2 rotatedOffset = float2(
            offset.x * cosR - offset.y * sinR,
            offset.x * sinR + offset.y * cosR
        );
        rotatedOffset *= inst.Size;

        float3 camRight = InvViewMatrix[0].xyz;
        float3 camUp = InvViewMatrix[1].xyz;

        worldPos = inst.Position +
                   camRight * rotatedOffset.x +
                   camUp * rotatedOffset.y;
    }

    output.WorldPosition = worldPos;
    output.Position = mul(float4(worldPos, 1.0), ViewProjectionMatrix);

    // Apply texture atlas offset/scale
    float2 baseUV = quadUVs[vertexID];
    output.TexCoord = inst.TexCoordOffsetScale.xy + baseUV * inst.TexCoordOffsetScale.zw;

    output.Color = inst.Color;

    return output;
}
