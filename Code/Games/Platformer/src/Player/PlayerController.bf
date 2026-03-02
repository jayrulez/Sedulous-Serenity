namespace Platformer.Player;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Core.Logging.Abstractions;
using Sedulous.Runtime;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Physics;
using Sedulous.Engine.Input;
using Platformer.Components;
using Platformer.Data;

/// Handles player physics movement, jumping, and collision response.
class PlayerController
{
	// Movement constants
	public const float MOVE_SPEED = 6.0f;
	public const float ACCELERATION = 30.0f;
	public const float DECELERATION = 20.0f;
	public const float JUMP_VELOCITY = 12.0f;
	public const float JUMP_HOLD_TIME = 0.2f;
	public const float GRAVITY = -30.0f;
	public const float MAX_FALL_SPEED = -20.0f;
	public const float INVINCIBLE_TIME = 1.5f;
	public const float BOUNCE_VELOCITY = 16.0f;
	public const float STOMP_BOUNCE = 8.0f;

	// Collision dimensions (center-origin: entity position = character center)
	public const float CHARACTER_HALF_HEIGHT = 0.5f;
	public const float CHARACTER_HALF_WIDTH = 0.3f;

	private Scene mScene;
	private PhysicsSceneModule mPhysicsModule;
	private ILogger mLogger;

	// Character skill multipliers (set from CharacterDefinition)
	public float MoveSpeedMultiplier = 1.0f;
	public float JumpMultiplier = 1.0f;
	public int32 MaxHealth = 3;
	public float InvincibilityMultiplier = 1.0f;
	public int32 CoinMultiplier = 1;

	// Input state (set externally each frame)
	public float MoveInput;
	public bool JumpPressed;
	public bool JumpHeld;

	public this(Scene scene, PhysicsSceneModule physicsModule, ILogger logger)
	{
		mScene = scene;
		mPhysicsModule = physicsModule;
		mLogger = logger;
	}

	/// Apply character skill modifiers and set initial health on the player entity.
	public void ApplyCharacterSkills(EntityId playerEntity, CharacterDefinition charDef)
	{
		MoveSpeedMultiplier = charDef.MoveSpeedMultiplier;
		JumpMultiplier = charDef.JumpMultiplier;
		MaxHealth = charDef.MaxHealth;
		InvincibilityMultiplier = charDef.InvincibilityMultiplier;
		CoinMultiplier = charDef.CoinMultiplier;

		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player != null)
		{
			player.Health = MaxHealth;
			mScene.SetComponent<PlayerComponent>(playerEntity, *player);
		}

		mLogger?.LogInformation("Character skills: speed={}x, jump={}x, hp={}, invincibility={}x, coins={}x",
			MoveSpeedMultiplier, JumpMultiplier, MaxHealth, InvincibilityMultiplier, CoinMultiplier);
	}

	/// Update player physics for one fixed timestep.
	public void FixedUpdate(EntityId playerEntity, float dt, LevelDefinition level)
	{
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player == null || !player.Alive)
			return;

		var transform = mScene.GetTransform(playerEntity);
		var pos = transform.Position;
		var vel = player.Velocity;

		// Invincibility timer
		if (player.InvincibleTimer > 0)
			player.InvincibleTimer -= dt;

		// Horizontal movement with acceleration
		float targetVelX = MoveInput * MOVE_SPEED * MoveSpeedMultiplier;
		if (Math.Abs(targetVelX) > 0.01f)
		{
			vel.X = MoveTowards(vel.X, targetVelX, ACCELERATION * dt);
			player.FacingRight = MoveInput > 0;
		}
		else
		{
			vel.X = MoveTowards(vel.X, 0, DECELERATION * dt);
		}

		// Jump initiation
		if (player.Grounded && JumpPressed)
		{
			vel.Y = JUMP_VELOCITY * JumpMultiplier;
			player.JumpTimer = JUMP_HOLD_TIME;
			player.Grounded = false;
			player.JumpHeld = true;
		}

		// Variable height jump (hold for higher)
		if (player.JumpHeld && JumpHeld && player.JumpTimer > 0)
		{
			player.JumpTimer -= dt;
			// Sustain upward velocity slightly
		}
		else
		{
			player.JumpHeld = false;
			player.JumpTimer = 0;
			// Cut jump short if released early
			if (!player.Grounded && vel.Y > 0 && !JumpHeld)
				vel.Y *= 0.5f;
		}

		// Gravity
		if (!player.Grounded)
		{
			vel.Y += GRAVITY * dt;
			if (vel.Y < MAX_FALL_SPEED)
				vel.Y = MAX_FALL_SPEED;
		}

		// Move position
		pos.X += vel.X * dt;
		pos.Y += vel.Y * dt;

		// Simple tile-based collision resolution
		ResolveTileCollisions(ref pos, ref vel, player, level);

		// Update facing direction via rotation
		// Rotate +90° Y for right (+X), -90° Y for left (-X)
		if (player.FacingRight)
			transform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), Math.PI_f / 2.0f);
		else
			transform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), -Math.PI_f / 2.0f);

		// Fall death
		if (pos.Y < -5.0f)
		{
			mLogger?.LogInformation("Player fell to death at Y={}", pos.Y);
			player.Alive = false;
			player.Health = 0;
		}

		// Clamp to level bounds horizontally
		if (pos.X < 0.5f)
		{
			pos.X = 0.5f;
			vel.X = 0;
		}
		if (pos.X > (level.Width - 0.5f) * level.TileSize)
		{
			pos.X = (level.Width - 0.5f) * level.TileSize;
			vel.X = 0;
		}

		// Store back
		player.Velocity = vel;
		transform.Position = pos;
		mScene.SetTransform(playerEntity, transform);
		mScene.SetComponent<PlayerComponent>(playerEntity, *player);
	}

	/// Apply damage to the player.
	public void TakeDamage(EntityId playerEntity, int32 damage)
	{
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player == null || !player.Alive || player.InvincibleTimer > 0)
			return;

		player.Health -= damage;
		player.InvincibleTimer = INVINCIBLE_TIME * InvincibilityMultiplier;
		mLogger?.LogInformation("Player took {} damage, health now {}", damage, player.Health);

		if (player.Health <= 0)
		{
			player.Alive = false;
			player.Health = 0;
			mLogger?.LogInformation("Player killed by damage");
		}

		mScene.SetComponent<PlayerComponent>(playerEntity, *player);
	}

	/// Apply bounce upward (from bouncer or enemy stomp).
	public void ApplyBounce(EntityId playerEntity, float velocity)
	{
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player == null) return;

		player.Velocity.Y = velocity;
		player.Grounded = false;
		mScene.SetComponent<PlayerComponent>(playerEntity, *player);
	}

	/// Collect a pickup.
	public void CollectPickup(EntityId playerEntity, PickupType type, int32 value)
	{
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player == null) return;

		switch (type)
		{
		case .Coin, .GemBlue, .GemGreen, .GemPink, .Star:
			player.Coins += value * CoinMultiplier;
		case .Heart:
			player.Health = Math.Min(player.Health + 1, MaxHealth);
			mLogger?.LogDebug("Player healed to {}", player.Health);
		case .Key:
			player.Keys++;
			mLogger?.LogInformation("Player collected key (total: {})", player.Keys);
		}

		mScene.SetComponent<PlayerComponent>(playerEntity, *player);
	}

	/// Use a key to open a door. Returns true if successful.
	public bool TryOpenDoor(EntityId playerEntity)
	{
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player == null || player.Keys <= 0)
		{
			mLogger?.LogDebug("Cannot open door: no keys available");
			return false;
		}

		player.Keys--;
		mScene.SetComponent<PlayerComponent>(playerEntity, *player);
		mLogger?.LogInformation("Used key to open door (remaining: {})", player.Keys);
		return true;
	}

	private void ResolveTileCollisions(ref Vector3 pos, ref Vector3 vel, PlayerComponent* player, LevelDefinition level)
	{
		// Center-origin collision: entity position = character center
		float halfW = CHARACTER_HALF_WIDTH;
		float halfH = CHARACTER_HALF_HEIGHT;
		float footY = pos.Y - halfH;
		float headY = pos.Y + halfH;

		// Ground check (below feet)
		player.Grounded = false;
		{
			int32 leftTile = (int32)Math.Floor((pos.X - halfW) / level.TileSize);
			int32 rightTile = (int32)Math.Floor((pos.X + halfW - 0.01f) / level.TileSize);
			int32 belowTile = (int32)Math.Floor((footY - 0.05f) / level.TileSize);

			for (int32 tx = leftTile; tx <= rightTile; tx++)
			{
				if (level.GetTile(tx, belowTile).IsSolid)
				{
					float tileTop = (belowTile + 1) * level.TileSize;
					if (footY <= tileTop && footY > tileTop - 0.5f)
					{
						pos.Y = tileTop + halfH;
						vel.Y = 0;
						player.Grounded = true;
					}
				}
			}
		}

		// Ceiling check (above head)
		if (vel.Y > 0)
		{
			headY = pos.Y + halfH; // Recalculate after ground snap
			int32 leftTile = (int32)Math.Floor((pos.X - halfW) / level.TileSize);
			int32 rightTile = (int32)Math.Floor((pos.X + halfW - 0.01f) / level.TileSize);
			int32 aboveTile = (int32)Math.Floor(headY / level.TileSize);

			for (int32 tx = leftTile; tx <= rightTile; tx++)
			{
				if (level.GetTile(tx, aboveTile).IsSolid)
				{
					float tileBottom = aboveTile * level.TileSize;
					if (headY >= tileBottom)
					{
						pos.Y = tileBottom - halfH;
						vel.Y = 0;
					}
				}
			}
		}

		// Left wall check
		{
			int32 leftTile = (int32)Math.Floor((pos.X - halfW) / level.TileSize);
			int32 bottomTile = (int32)Math.Floor((pos.Y - halfH + 0.1f) / level.TileSize);
			int32 topTile = (int32)Math.Floor((pos.Y + halfH - 0.1f) / level.TileSize);

			for (int32 ty = bottomTile; ty <= topTile; ty++)
			{
				if (level.GetTile(leftTile, ty).IsSolid)
				{
					float tileRight = (leftTile + 1) * level.TileSize;
					if (pos.X - halfW < tileRight)
					{
						pos.X = tileRight + halfW;
						vel.X = 0;
					}
				}
			}
		}

		// Right wall check
		{
			int32 rightTile = (int32)Math.Floor((pos.X + halfW) / level.TileSize);
			int32 bottomTile = (int32)Math.Floor((pos.Y - halfH + 0.1f) / level.TileSize);
			int32 topTile = (int32)Math.Floor((pos.Y + halfH - 0.1f) / level.TileSize);

			for (int32 ty = bottomTile; ty <= topTile; ty++)
			{
				if (level.GetTile(rightTile, ty).IsSolid)
				{
					float tileLeft = rightTile * level.TileSize;
					if (pos.X + halfW > tileLeft)
					{
						pos.X = tileLeft - halfW;
						vel.X = 0;
					}
				}
			}
		}
	}

	private static float MoveTowards(float current, float target, float maxDelta)
	{
		if (Math.Abs(target - current) <= maxDelta)
			return target;
		return current + Math.Sign(target - current) * maxDelta;
	}
}
