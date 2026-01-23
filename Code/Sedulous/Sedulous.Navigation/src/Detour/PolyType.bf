using System;

namespace Sedulous.Navigation.Detour;

/// The type of a navigation polygon.
enum PolyType : uint8
{
	/// A standard polygon forming the navmesh surface.
	Ground = 0,
	/// An off-mesh connection (link between disconnected surfaces).
	OffMeshConnection = 1
}
