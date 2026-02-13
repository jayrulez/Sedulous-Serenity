namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

/// Persistent game settings stored alongside save data.
class GameSettings : ISerializable
{
	public bool mInvertCameraPan;          // true = WASD moves the board, false = WASD moves the camera (default)
	public bool mAutoStepDefault = true;   // auto-advance enemy turns by default
	public int32 mDefaultBattleSpeed = 1;  // 1 = 1x, 2 = 2x, 4 = 4x

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Bool("InvertCameraPan", ref mInvertCameraPan);
		s.Bool("AutoStepDefault", ref mAutoStepDefault);
		s.Int32("DefaultBattleSpeed", ref mDefaultBattleSpeed);
		return .Ok;
	}
}
