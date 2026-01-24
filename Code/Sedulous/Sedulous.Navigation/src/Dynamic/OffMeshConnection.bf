using System;

namespace Sedulous.Navigation.Dynamic;

/// Defines an off-mesh connection between two points on the navigation mesh.
/// Off-mesh connections allow agents to traverse gaps, ladders, teleporters, etc.
[CRepr]
struct OffMeshConnection
{
	/// Start position of the connection (world space).
	public float[3] Start;
	/// End position of the connection (world space).
	public float[3] End;
	/// Radius within which an agent can use this connection.
	public float Radius;
	/// Navigation area type for filtering.
	public uint8 Area;
	/// User-defined flags for path filtering.
	public uint16 Flags;
	/// Whether the connection can be traversed in both directions.
	public bool Bidirectional;
	/// User-defined identifier for this connection.
	public uint32 UserId;

	public this()
	{
		Start = default;
		End = default;
		Radius = 0;
		Area = 0;
		Flags = 1; // Default walkable flag
		Bidirectional = true;
		UserId = 0;
	}

	public this(float[3] start, float[3] end, float radius, uint8 area = 0, bool bidirectional = true)
	{
		Start = start;
		End = end;
		Radius = radius;
		Area = area;
		Flags = 1;
		Bidirectional = bidirectional;
		UserId = 0;
	}
}
