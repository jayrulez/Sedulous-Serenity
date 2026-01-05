namespace Sedulous.Framework.Renderer;

using Sedulous.Mathematics;
using System;

/// GPU-packed shadow tile data for shader consumption.
/// Used for point/spot light shadows in the atlas.
[CRepr]
struct GPUShadowTileData
{
	/// View-projection matrix for this shadow tile.
	public Matrix ViewProjection;
	/// UV offset (xy) and scale (zw) in atlas.
	public Vector4 UVOffsetScale;
	/// Light index this tile belongs to.
	public int32 LightIndex;
	/// Face index for point lights (0-5), -1 for spot.
	public int32 FaceIndex;
	public int32 _pad0;
	public int32 _pad1;
}
