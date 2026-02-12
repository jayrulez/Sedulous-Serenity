namespace StormTactics.Battle;

using System;

enum BattleActionType
{
	Move,
	Attack,
	UseSkill,
	Wait
}

/// An action a unit can take on their turn.
/// Supports optional pre-move: unit moves to mPreMoveHex first, then executes the main action.
struct BattleAction
{
	public BattleActionType mType;
	public int32 mUnitIndex;
	public HexCoord mTargetHex;    // For Move: destination. For Attack/Skill: target cell.
	public int32 mTargetUnit;      // For Attack/Skill: target unit index (-1 if area)
	public int32 mSkillId;         // For UseSkill
	public HexCoord mPreMoveHex;   // Optional: move here before executing action
	public bool mHasPreMove;       // True if mPreMoveHex is valid

	public static BattleAction MakeMove(int32 unit, HexCoord dest)
	{
		return .() { mType = .Move, mUnitIndex = unit, mTargetHex = dest, mTargetUnit = -1 };
	}

	public static BattleAction MakeAttack(int32 unit, int32 target)
	{
		return .() { mType = .Attack, mUnitIndex = unit, mTargetUnit = target };
	}

	public static BattleAction MakeSkill(int32 unit, int32 skillId, int32 target)
	{
		return .() { mType = .UseSkill, mUnitIndex = unit, mSkillId = skillId, mTargetUnit = target };
	}

	public static BattleAction MakeWait(int32 unit)
	{
		return .() { mType = .Wait, mUnitIndex = unit, mTargetUnit = -1 };
	}

	public static BattleAction MakeMoveAndAttack(int32 unit, HexCoord moveHex, int32 target)
	{
		return .() { mType = .Attack, mUnitIndex = unit, mTargetUnit = target, mPreMoveHex = moveHex, mHasPreMove = true };
	}

	public static BattleAction MakeMoveAndSkill(int32 unit, HexCoord moveHex, int32 skillId, int32 target)
	{
		return .() { mType = .UseSkill, mUnitIndex = unit, mSkillId = skillId, mTargetUnit = target, mPreMoveHex = moveHex, mHasPreMove = true };
	}

	public static BattleAction MakeMoveAndWait(int32 unit, HexCoord moveHex)
	{
		return .() { mType = .Wait, mUnitIndex = unit, mTargetUnit = -1, mPreMoveHex = moveHex, mHasPreMove = true };
	}
}
