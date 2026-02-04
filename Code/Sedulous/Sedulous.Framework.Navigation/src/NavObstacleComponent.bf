namespace Sedulous.Framework.Navigation;

/// Component for entities that represent dynamic navigation obstacles.
/// The ObstacleId references the obstacle in the TileCache owned by NavWorld.
struct NavObstacleComponent
{
	/// ID of this obstacle in the TileCache.
	public int32 ObstacleId;
	/// Obstacle cylinder radius.
	public float Radius;
	/// Obstacle cylinder height.
	public float Height;

	public static NavObstacleComponent Default => .() {
		ObstacleId = -1,
		Radius = 0,
		Height = 0
	};
}
