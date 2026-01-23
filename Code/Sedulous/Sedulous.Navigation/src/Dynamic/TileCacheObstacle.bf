using System;

namespace Sedulous.Navigation.Dynamic;

/// Type of obstacle shape.
enum ObstacleType : uint8
{
	/// Cylindrical obstacle defined by center, radius, and height.
	Cylinder,
	/// Axis-aligned box obstacle defined by min and max corners.
	Box
}

/// State of an obstacle in the tile cache.
enum ObstacleState : uint8
{
	/// Obstacle not yet processed.
	Pending,
	/// Obstacle is active and carved into the navmesh.
	Active,
	/// Obstacle is pending removal.
	Removing
}

/// Represents a dynamic obstacle that can be added to or removed from the navigation mesh.
class TileCacheObstacle
{
	/// Unique identifier for this obstacle.
	public int32 Id;
	/// Type of obstacle shape.
	public ObstacleType Type;
	/// Current processing state.
	public ObstacleState State;

	// Cylinder parameters
	/// Center position (X, Y base, Z).
	public float[3] Position;
	/// Radius of the cylinder.
	public float Radius;
	/// Height of the cylinder.
	public float Height;

	// Box parameters
	/// Minimum corner of the box.
	public float[3] BMin;
	/// Maximum corner of the box.
	public float[3] BMax;

	/// Computes the axis-aligned bounding box of this obstacle.
	public void GetBounds(out float[3] obstBMin, out float[3] obstBMax)
	{
		switch (Type)
		{
		case .Cylinder:
			obstBMin[0] = Position[0] - Radius;
			obstBMin[1] = Position[1];
			obstBMin[2] = Position[2] - Radius;
			obstBMax[0] = Position[0] + Radius;
			obstBMax[1] = Position[1] + Height;
			obstBMax[2] = Position[2] + Radius;
		case .Box:
			obstBMin = BMin;
			obstBMax = BMax;
		}
	}
}
