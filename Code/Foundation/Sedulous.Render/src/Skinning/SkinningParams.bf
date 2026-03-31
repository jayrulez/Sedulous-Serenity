using System;
namespace Sedulous.Render;

/// Skinning parameters uniform buffer (must match skinning.comp.hlsl SkinningParams).
[CRepr]
struct SkinningParams
{
	public uint32 VertexCount;
	public uint32 BoneCount;
	public uint32[2] _Padding;

	public const uint32 Size = 16;
}