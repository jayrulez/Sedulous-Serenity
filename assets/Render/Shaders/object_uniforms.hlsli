// Per-object uniform buffer — must match ObjectUniforms in RenderWorld.bf
cbuffer ObjectUniforms : register(b1)
{
    float4x4 WorldMatrix;
    float4x4 PrevWorldMatrix;
    uint ObjectID;
    uint MaterialID;
    float2 _ObjPadding;
};
