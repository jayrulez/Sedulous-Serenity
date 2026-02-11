// Bone transform uniform buffer for skinned meshes
cbuffer BoneUniforms : register(b2)
{
    float4x4 BoneMatrices[256];
};
