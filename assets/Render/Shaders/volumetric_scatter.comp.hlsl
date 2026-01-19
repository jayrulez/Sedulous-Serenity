// Volumetric Fog - Scattering Integration Compute Shader
// Accumulates scattering along view rays using ray marching
#pragma pack_matrix(row_major)

cbuffer VolumetricParams : register(b0)
{
    uint3 FroxelDimensions;
    uint _Padding;
    float NearPlane;
    float FarPlane;
    float2 _Padding2;
};

Texture3D<float4> ScatteringVolume : register(t0); // Input: injected scattering (read-only)
RWTexture3D<float4> IntegratedVolume : register(u0); // Output: accumulated scattering

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= FroxelDimensions.x || DTid.y >= FroxelDimensions.y)
        return;

    // March from near to far, accumulating scattering
    float4 accumulated = float4(0.0, 0.0, 0.0, 1.0); // RGB = color, A = transmittance

    for (uint z = 0; z < FroxelDimensions.z; z++)
    {
        uint3 coord = uint3(DTid.xy, z);
        float4 scatteringExtinction = ScatteringVolume[coord];

        float3 inscattering = scatteringExtinction.rgb;
        float extinction = scatteringExtinction.a;

        // Calculate step transmittance
        // Froxel depth increases exponentially
        float z0 = float(z) / float(FroxelDimensions.z);
        float z1 = float(z + 1) / float(FroxelDimensions.z);
        float d0 = lerp(NearPlane, FarPlane, z0 * z0);
        float d1 = lerp(NearPlane, FarPlane, z1 * z1);
        float stepLength = d1 - d0;

        float stepTransmittance = exp(-extinction * stepLength);

        // Integrate inscattering
        // Using the standard volumetric rendering integral
        float3 S = inscattering * stepLength;

        // Apply transmittance so far
        accumulated.rgb += accumulated.a * S;
        accumulated.a *= stepTransmittance;

        // Store accumulated result
        IntegratedVolume[coord] = accumulated;
    }
}
