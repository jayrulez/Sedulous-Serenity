// Cluster AABB Building Compute Shader
// Builds view-space AABBs for each cluster in the frustum grid

// Cluster grid parameters
cbuffer ClusterUniforms : register(b0)
{
    uint ClustersX;
    uint ClustersY;
    uint ClustersZ;
    uint _Padding0;

    float ScreenWidth;
    float ScreenHeight;
    float NearPlane;
    float FarPlane;

    float LogDepthScale;
    float LogDepthBias;
    float TileSizeX;
    float TileSizeY;
};

// Camera matrices
cbuffer CameraUniforms : register(b1)
{
    float4x4 InverseProjection;
};

// Cluster AABB structure
struct ClusterAABB
{
    float3 Min;
    float _Pad0;
    float3 Max;
    float _Pad1;
};

// Output buffer
RWStructuredBuffer<ClusterAABB> ClusterAABBs : register(u0);

// Get linear cluster index from 3D coordinates
uint GetClusterIndex(uint3 clusterCoord)
{
    return clusterCoord.x + clusterCoord.y * ClustersX + clusterCoord.z * ClustersX * ClustersY;
}

// Convert screen position to NDC
float2 ScreenToNDC(float2 screenPos)
{
    return float2(
        (screenPos.x / ScreenWidth) * 2.0 - 1.0,
        (screenPos.y / ScreenHeight) * 2.0 - 1.0
    );
}

// Get depth at a given slice using logarithmic distribution
float GetSliceDepth(uint slice)
{
    return NearPlane * pow(FarPlane / NearPlane, float(slice) / float(ClustersZ));
}

// Unproject a point from NDC + depth to view space
float3 UnprojectToView(float2 ndc, float viewDepth)
{
    // Convert depth to NDC Z (D3D convention: 0 at near, 1 at far)
    float ndcZ = (viewDepth - NearPlane) / (FarPlane - NearPlane);

    float4 clipPos = float4(ndc.x, ndc.y, ndcZ, 1.0);
    float4 viewPos = mul(InverseProjection, clipPos);
    viewPos /= viewPos.w;

    return viewPos.xyz;
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    uint x = dispatchThreadId.x;
    uint y = dispatchThreadId.y;
    uint z = dispatchThreadId.z;

    if (x >= ClustersX || y >= ClustersY || z >= ClustersZ)
        return;

    uint clusterIndex = GetClusterIndex(dispatchThreadId);

    // Calculate screen-space tile bounds
    float minScreenX = float(x) * TileSizeX;
    float maxScreenX = float(x + 1) * TileSizeX;
    float minScreenY = float(y) * TileSizeY;
    float maxScreenY = float(y + 1) * TileSizeY;

    // Convert to NDC
    float2 ndcMin = ScreenToNDC(float2(minScreenX, minScreenY));
    float2 ndcMax = ScreenToNDC(float2(maxScreenX, maxScreenY));

    // Get depth slice bounds
    float zNear = GetSliceDepth(z);
    float zFar = GetSliceDepth(z + 1);

    // Build AABB from 8 corners
    float3 minBounds = float3(1e30, 1e30, 1e30);
    float3 maxBounds = float3(-1e30, -1e30, -1e30);

    // Transform all 8 corners to view space
    float2 ndcCorners[4] = {
        float2(ndcMin.x, ndcMin.y),
        float2(ndcMax.x, ndcMin.y),
        float2(ndcMin.x, ndcMax.y),
        float2(ndcMax.x, ndcMax.y)
    };

    float depths[2] = { zNear, zFar };

    [unroll]
    for (int i = 0; i < 4; i++)
    {
        [unroll]
        for (int j = 0; j < 2; j++)
        {
            float3 viewPos = UnprojectToView(ndcCorners[i], depths[j]);
            minBounds = min(minBounds, viewPos);
            maxBounds = max(maxBounds, viewPos);
        }
    }

    // Write cluster AABB
    ClusterAABB aabb;
    aabb.Min = minBounds;
    aabb.Max = maxBounds;
    aabb._Pad0 = 0;
    aabb._Pad1 = 0;

    ClusterAABBs[clusterIndex] = aabb;
}
