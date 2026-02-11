namespace Platformer.Components;

using Sedulous.Mathematics;

struct PlayerComponent
{
	/// Current health (max 3).
	public int32 Health = 3;
	/// Total coins collected.
	public int32 Coins = 0;
	/// Number of keys held.
	public int32 Keys = 0;
	/// Current velocity.
	public Vector3 Velocity = .Zero;
	/// Whether the player is on the ground.
	public bool Grounded = false;
	/// Whether the player is facing right.
	public bool FacingRight = true;
	/// Invincibility timer after taking damage (seconds remaining).
	public float InvincibleTimer = 0;
	/// Jump hold timer for variable-height jump.
	public float JumpTimer = 0;
	/// Whether jump button is being held.
	public bool JumpHeld = false;
	/// Whether the player is alive.
	public bool Alive = true;

	public static PlayerComponent Default => .()
	{
		Health = 3,
		Coins = 0,
		Keys = 0,
		Velocity = .Zero,
		Grounded = false,
		FacingRight = true,
		InvincibleTimer = 0,
		JumpTimer = 0,
		JumpHeld = false,
		Alive = true
	};
}
