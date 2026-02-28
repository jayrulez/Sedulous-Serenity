namespace Platformer.Components;

using System;
using Platformer.Data;
using Sedulous.Engine.Scenes;

struct PickupComponent : IComponent
{
	public void Dispose() mut { }

	/// What type of pickup this is.
	public PickupType Type;
	/// Whether this pickup has been collected.
	public bool Collected = false;
	/// Animation phase for bobbing motion.
	public float BobPhase = 0;
	/// Score value of this pickup.
	public int32 Value = 1;

	public static PickupComponent Create(PickupType type)
	{
		int32 value;
		switch (type)
		{
		case .Coin: value = 1;
		case .GemBlue: value = 5;
		case .GemGreen: value = 5;
		case .GemPink: value = 5;
		case .Heart: value = 0;
		case .Key: value = 0;
		case .Star: value = 10;
		}

		return .()
		{
			Type = type,
			Collected = false,
			BobPhase = 0,
			Value = value
		};
	}
}
