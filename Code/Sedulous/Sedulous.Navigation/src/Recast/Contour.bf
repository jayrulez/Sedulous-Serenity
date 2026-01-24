using System;
using System.Collections;

namespace Sedulous.Navigation.Recast;

/// A simplified contour representing the boundary of a region.
class Contour
{
	/// Simplified contour vertices.
	public List<ContourVertex> Vertices ~ delete _;
	/// Raw (unsimplified) contour vertices.
	public List<ContourVertex> RawVertices ~ delete _;
	/// Region ID this contour belongs to.
	public uint16 RegionId;
	/// Area type of this contour.
	public uint8 Area;

	public this()
	{
		Vertices = new List<ContourVertex>();
		RawVertices = new List<ContourVertex>();
	}
}
