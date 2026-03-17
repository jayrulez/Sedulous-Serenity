using System;
using System.Collections;
using Sedulous.Core.Mathematics;

namespace Sedulous.VG;

/// Flattens a Path into polyline sub-paths by converting curves to line segments
public static class PathFlattener
{
	/// Flatten a path into a list of polyline sub-paths
	public static void Flatten(Path path, float tolerance, List<FlattenedSubPath> output)
	{
		var iter = path.GetIterator();
		PathSegment seg = ?;
		FlattenedSubPath current = null;

		while (iter.GetNext(out seg))
		{
			switch (seg.Command)
			{
			case .MoveTo:
				current = new FlattenedSubPath();
				output.Add(current);
				current.Points.Add(seg.Points[0]);

			case .LineTo:
				if (current != null)
					current.Points.Add(seg.Points[0]);

			case .QuadTo:
				if (current != null)
					CurveUtils.FlattenQuadratic(seg.StartPoint, seg.Points[0], seg.Points[1], tolerance, current.Points);

			case .CubicTo:
				if (current != null)
					CurveUtils.FlattenCubic(seg.StartPoint, seg.Points[0], seg.Points[1], seg.Points[2], tolerance, current.Points);

			case .Close:
				if (current != null)
				{
					current.IsClosed = true;
					// Close by connecting back if needed
					if (current.Points.Count > 1)
					{
						let first = current.Points[0];
						let last = current.Points[current.Points.Count - 1];
						if (Vector2.Distance(first, last) > 0.0001f)
							current.Points.Add(first);
					}
				}
			}
		}
	}
}
