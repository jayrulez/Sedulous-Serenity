using System;
namespace Sedulous.Engine.Renderer;

/// Light grid entry - stores offset and count into light index list.
[CRepr]
struct LightGridEntry
{
	/// Offset into light index buffer.
	public uint32 Offset;
	/// Number of lights in this cluster.
	public uint32 Count;
	public uint32 _pad0;
	public uint32 _pad1;
}
