namespace Platformer.Data;

enum EnemyType
{
	/// Walks back and forth on platforms. Defeated by jumping on top.
	Slime,
	/// Flies in a sine wave pattern. Harder to stomp.
	Bee,
	/// Faster ground patrol, reverses on walls/edges. Defeated by jumping on top.
	Crab,
	/// Floats and chases player when near. Cannot be defeated.
	Skull
}
