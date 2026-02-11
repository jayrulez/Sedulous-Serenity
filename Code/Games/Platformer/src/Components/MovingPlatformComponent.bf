namespace Platformer.Components;

using Sedulous.Mathematics;

struct MovingPlatformComponent
{
	/// Start position.
	public Vector3 PointA;
	/// End position.
	public Vector3 PointB;
	/// Movement speed in units per second.
	public float Speed = 2.0f;
	/// Current interpolation parameter (0 to 1).
	public float T = 0;
	/// Direction of interpolation (+1 forward, -1 backward).
	public float Direction = 1.0f;
	/// Position at start of frame (for computing carry delta).
	public Vector3 PreviousPosition;
	/// Half-extents of the platform collision box.
	public Vector3 HalfExtents = .(0.75f, 0.15f, 0.5f);

	public static MovingPlatformComponent Create(Vector3 pointA, Vector3 pointB, float speed)
	{
		return .()
		{
			PointA = pointA,
			PointB = pointB,
			Speed = speed,
			T = 0,
			Direction = 1.0f,
			PreviousPosition = pointA,
			HalfExtents = .(0.75f, 0.15f, 0.5f)
		};
	}

	/// Gets the current world position.
	public Vector3 CurrentPosition => Vector3.Lerp(PointA, PointB, T);
}
