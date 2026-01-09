namespace Sedulous.Engine.Renderer;

using Sedulous.Mathematics;

/// Shadow atlas slot for point/spot lights (CPU-side tracking).
struct ShadowAtlasSlot
{
	/// UV offset in atlas (xy) and size (zw).
	public Vector4 UVOffsetSize;
	/// Light index this slot belongs to.
	public int32 LightIndex;
	/// Face index for point lights (0-5).
	public int32 FaceIndex;
	public int32 _pad0;
	public int32 _pad1;
}
