namespace Platformer.Components;

using System;
using Sedulous.Foundation.Mathematics;
using Sedulous.Engine.Scenes;

enum HazardType
{
	/// Static spikes on a tile.
	Spike,
	/// Saw blade moving between two points.
	Saw,
	/// Spiked ball on patrol path.
	SpikyBall,
	/// Cannon that fires cannonballs periodically.
	Cannon
}

struct HazardComponent : IComponent
{
	public void Dispose() mut { }

	/// Type of hazard.
	public HazardType Type;
	/// Damage dealt to the player.
	public int32 Damage = 1;
	/// Whether this hazard is currently active.
	public bool Active = true;
	/// Movement direction for moving hazards (+1/-1).
	public float Direction = 1.0f;
	/// Movement speed for moving hazards.
	public float Speed = 3.0f;
	/// Start position for moving hazards.
	public Vector3 StartPos;
	/// End position for moving hazards.
	public Vector3 EndPos;
	/// Timer for periodic hazards (cannons).
	public float Timer = 0;
	/// Fire interval for cannons.
	public float FireInterval = 3.0f;

	public static HazardComponent CreateSpike()
	{
		return .()
		{
			Type = .Spike,
			Damage = 1,
			Active = true
		};
	}

	public static HazardComponent CreateSaw(Vector3 start, Vector3 end, float speed)
	{
		return .()
		{
			Type = .Saw,
			Damage = 1,
			Active = true,
			Direction = 1.0f,
			Speed = speed,
			StartPos = start,
			EndPos = end
		};
	}

	public static HazardComponent CreateSpikyBall(Vector3 start, Vector3 end, float speed)
	{
		return .()
		{
			Type = .SpikyBall,
			Damage = 1,
			Active = true,
			Direction = 1.0f,
			Speed = speed,
			StartPos = start,
			EndPos = end
		};
	}

	public static HazardComponent CreateCannon(float fireInterval)
	{
		return .()
		{
			Type = .Cannon,
			Damage = 1,
			Active = true,
			Timer = 0,
			FireInterval = fireInterval
		};
	}
}
