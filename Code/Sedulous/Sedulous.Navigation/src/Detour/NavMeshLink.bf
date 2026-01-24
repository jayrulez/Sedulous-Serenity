using System;

namespace Sedulous.Navigation.Detour;

/// A link connecting polygons (within a tile or across tiles).
[CRepr]
struct NavMeshLink
{
	/// Reference to the connected polygon.
	public PolyRef Reference;
	/// Index of the next link in the linked list (-1 = end).
	public int32 Next;
	/// Index of the edge on the source polygon.
	public uint8 Edge;
	/// Side indicator for off-mesh or cross-tile connections.
	public uint8 Side;
	/// Min/max extent along the edge for partial connections.
	public uint8 BMin;
	public uint8 BMax;
}
