namespace StormTactics.Battle;

using System;
using System.Collections;
using StormTactics.Core;

enum BattleState
{
	NotStarted,
	InProgress,
	AttackerWins,
	DefenderWins,
	Draw
}

enum AIDifficulty
{
	Easy,    // Random target, no skill usage
	Normal,  // Focus fire, basic skill usage
	Hard     // Optimal target selection, full skill/heal/buff priority
}

/// Result of a completed battle.
class BattleResult
{
	public BattleState mOutcome;
	public Force mWinner;
	public int32 mTotalTurns;
	public List<int32> mSurvivingAttackers = new .() ~ delete _;
	public List<int32> mSurvivingDefenders = new .() ~ delete _;
	public int32 mTotalDamageDealt;
	public int32 mTotalHealingDone;
	public int32 mUnitsKilled;
}

/// Pure-logic battle simulation with no rendering dependencies.
/// Deterministic given the same inputs.
class BattleSimulation
{
	private HexGrid mGrid ~ delete _;
	private HexPathfinder mPathfinder ~ delete _;
	private List<BattleUnit> mUnits = new .() ~ DeleteContainerAndItems!(_);
	private List<BattleEvent> mEventQueue = new .() ~ DeleteContainerAndItems!(_);
	private ConfigDatabase mConfigs;

	private BattleState mState = .NotStarted;
	private int32 mTurnCount;
	private int32 mCurrentUnitIndex = -1;
	private Random mRng ~ delete _;
	private AIDifficulty mDifficulty = .Normal;

	// --- Replay ---
	private List<BattleAction> mActionLog = new .() ~ delete _;
	private List<FormationSlot> mInitAttackers ~ { if (_ != null) DeleteContainerAndItems!(_); }
	private List<FormationSlot> mInitDefenders ~ { if (_ != null) DeleteContainerAndItems!(_); }
	private int32 mInitColumns;
	private int32 mInitRows;
	private int64 mInitSeed;

	// --- Stats tracking ---
	private int32 mTotalDamageDealt;
	private int32 mTotalHealingDone;
	private int32 mUnitsKilled;

	public BattleState State => mState;
	public int32 TurnCount => mTurnCount;
	public HexGrid Grid => mGrid;
	public int32 CurrentUnitIndex => mCurrentUnitIndex;
	public AIDifficulty Difficulty { get => mDifficulty; set => mDifficulty = value; }
	public ConfigDatabase Configs => mConfigs;
	public Random Rng => mRng;

	public this(ConfigDatabase configs)
	{
		mConfigs = configs;
	}

	// --- Initialization ---

	public void Initialize(List<FormationSlot> attackers, List<FormationSlot> defenders,
		int32 columns = BattleConstants.DEFAULT_COLUMNS, int32 rows = BattleConstants.DEFAULT_ROWS, int64 seed = 0)
	{
		mGrid = new HexGrid(columns, rows);
		mPathfinder = new HexPathfinder(mGrid);
		mRng = new Random(seed);
		mTurnCount = 0;
		mState = .InProgress;
		mTotalDamageDealt = 0;
		mTotalHealingDone = 0;
		mUnitsKilled = 0;

		// Store initial state for replay
		mInitColumns = columns;
		mInitRows = rows;
		mInitSeed = seed;
		mInitAttackers = new List<FormationSlot>();
		for (let slot in attackers)
		{
			let copy = new FormationSlot();
			copy.mUnitId = slot.mUnitId;
			copy.mStarLevel = slot.mStarLevel;
			copy.mGridX = slot.mGridX;
			copy.mGridY = slot.mGridY;
			mInitAttackers.Add(copy);
		}
		mInitDefenders = new List<FormationSlot>();
		for (let slot in defenders)
		{
			let copy = new FormationSlot();
			copy.mUnitId = slot.mUnitId;
			copy.mStarLevel = slot.mStarLevel;
			copy.mGridX = slot.mGridX;
			copy.mGridY = slot.mGridY;
			mInitDefenders.Add(copy);
		}

		// Place attackers on left side
		for (let slot in attackers)
		{
			let config = mConfigs.GetUnit(slot.mUnitId);
			if (config == null) continue;
			let hex = HexCoord.FromOffset(slot.mGridX, slot.mGridY);
			if (!mGrid.InBounds(hex)) continue;

			let unit = new BattleUnit();
			let idx = (int32)mUnits.Count;
			unit.Initialize(idx, config, .Attacker, hex, slot.mGridX);
			mUnits.Add(unit);
			mGrid.SetOccupant(hex, idx);
		}

		// Place defenders on right side
		for (let slot in defenders)
		{
			let config = mConfigs.GetUnit(slot.mUnitId);
			if (config == null) continue;
			let hex = HexCoord.FromOffset(slot.mGridX, slot.mGridY);
			if (!mGrid.InBounds(hex)) continue;

			let unit = new BattleUnit();
			let idx = (int32)mUnits.Count;
			unit.Initialize(idx, config, .Defender, hex, slot.mGridX);
			mUnits.Add(unit);
			mGrid.SetOccupant(hex, idx);
		}

		EmitEvent(.BattleStarted);
	}

	// --- Queries ---

	public BattleUnit GetUnit(int32 index)
	{
		if (index >= 0 && index < mUnits.Count) return mUnits[index];
		return null;
	}

	public int32 UnitCount => (int32)mUnits.Count;

	public void GetAliveUnits(Force force, List<BattleUnit> outList)
	{
		for (let unit in mUnits)
			if (unit.mAlive && unit.mForce == force)
				outList.Add(unit);
	}

	public bool IsFinished => mState != .InProgress;

	/// Get all hexes a unit can move to from their current position.
	public void GetReachableCells(int32 unitIdx, List<HexCoord> outList)
	{
		outList.Clear();
		let unit = mUnits[unitIdx];
		if (!unit.mAlive) return;
		let flying = unit.mConfig.mMoveType == .Flying;
		mPathfinder.GetReachableCells(unit.mPosition, unit.mModifiedMoveRange, flying, outList);
	}

	/// Get indices of enemy units within attack range of the given unit.
	public void GetAttackableUnits(int32 unitIdx, List<int32> outList)
	{
		outList.Clear();
		let unit = mUnits[unitIdx];
		if (!unit.mAlive) return;
		for (int32 i = 0; i < (int32)mUnits.Count; i++)
		{
			let target = mUnits[i];
			if (!target.mAlive || target.mForce == unit.mForce) continue;
			if (unit.mPosition.DistanceTo(target.mPosition) <= unit.mModifiedAttackRange)
				outList.Add(i);
		}
	}

	/// Get IDs of skills the unit can actively use this turn (OnActionBegin, not on cooldown, not silenced).
	public void GetUsableSkills(int32 unitIdx, List<int32> outSkillIds)
	{
		outSkillIds.Clear();
		let unit = mUnits[unitIdx];
		if (!unit.mAlive || unit.IsSilenced) return;
		for (let skillId in unit.mConfig.mSkillIds)
		{
			let skill = mConfigs.GetSkill(skillId);
			if (skill == null) continue;
			if (skill.mMoment != .OnActionBegin) continue;
			if (unit.IsSkillOnCooldown(skillId)) continue;
			if (unit.IsSkillUsesExhausted(skillId, skill)) continue;
			outSkillIds.Add(skillId);
		}
	}

	/// Get indices of valid targets for a specific skill.
	public void GetSkillTargets(int32 unitIdx, int32 skillId, List<int32> outTargets)
	{
		outTargets.Clear();
		let unit = mUnits[unitIdx];
		let skill = mConfigs.GetSkill(skillId);
		if (skill == null || !unit.mAlive) return;

		for (int32 i = 0; i < (int32)mUnits.Count; i++)
		{
			let target = mUnits[i];
			if (!target.mAlive) continue;

			switch (skill.mTarget)
			{
			case .SingleEnemy, .RandomEnemy:
				if (target.mForce != unit.mForce)
					outTargets.Add(i);
			case .SingleAlly, .RandomAlly, .MostWoundedAlly:
				if (target.mForce == unit.mForce)
					outTargets.Add(i);
			case .Self:
				if (i == unitIdx)
					outTargets.Add(i);
			case .AllEnemies:
				if (target.mForce != unit.mForce)
					outTargets.Add(i);
			case .AllAllies:
				if (target.mForce == unit.mForce)
					outTargets.Add(i);
			}
		}
	}

	// --- Turn order ---

	/// Get the next unit to act (lowest action timer).
	public int32 GetNextUnit()
	{
		int32 bestIdx = -1;
		float bestTime = float.MaxValue;

		for (int32 i = 0; i < mUnits.Count; i++)
		{
			let unit = mUnits[i];
			if (!unit.mAlive) continue;
			if (unit.mActionTimer < bestTime ||
				(unit.mActionTimer == bestTime && unit.mForce == .Defender)) // Defender wins ties
			{
				bestTime = unit.mActionTimer;
				bestIdx = i;
			}
		}
		return bestIdx;
	}

	/// Predict the next N unit turns without modifying simulation state.
	/// Returns unit indices in predicted turn order.
	public void PredictTurnOrder(int32 count, List<int32> outUnitIndices)
	{
		outUnitIndices.Clear();

		// Snapshot current timers
		var timers = scope float[mUnits.Count];
		for (int32 i = 0; i < (int32)mUnits.Count; i++)
			timers[i] = mUnits[i].mActionTimer;

		for (int32 turn = 0; turn < count; turn++)
		{
			// Find unit with lowest timer
			int32 nextIdx = -1;
			float bestTime = float.MaxValue;
			for (int32 i = 0; i < (int32)mUnits.Count; i++)
			{
				if (!mUnits[i].mAlive) continue;
				if (timers[i] < bestTime ||
					(timers[i] == bestTime && mUnits[i].mForce == .Defender))
				{
					bestTime = timers[i];
					nextIdx = i;
				}
			}
			if (nextIdx < 0) break;

			outUnitIndices.Add(nextIdx);

			// Advance all timers
			for (int32 i = 0; i < (int32)mUnits.Count; i++)
				if (mUnits[i].mAlive)
					timers[i] -= bestTime;

			// Reset acted unit's timer
			timers[nextIdx] = (float)BattleConstants.TIME_UNIT / (float)mUnits[nextIdx].mModifiedActionSpeed;
		}
	}

	/// Advance time to the next unit's turn and return that unit's index.
	public int32 AdvanceToNextTurn()
	{
		let nextIdx = GetNextUnit();
		if (nextIdx < 0) return -1;

		let advanceTime = mUnits[nextIdx].mActionTimer;

		// Subtract elapsed time from all units
		for (let unit in mUnits)
		{
			if (unit.mAlive)
				unit.mActionTimer -= advanceTime;
		}

		mCurrentUnitIndex = nextIdx;
		mTurnCount++;

		let unit = mUnits[nextIdx];
		unit.OnTurnStart();

		// Tick cooldowns
		unit.TickCooldowns();

		// Tick buffs (DoT/HoT + duration)
		TickBuffs(nextIdx);

		// Check if unit died from DoT
		if (!unit.mAlive)
			return AdvanceToNextTurn();

		EmitEvent(.TurnStarted, nextIdx);
		return nextIdx;
	}

	// --- Stepping ---

	/// Begin a turn: advance to the next unit, tick buffs/cooldowns.
	/// Returns the unit index that should act, or -1 if the turn was auto-handled
	/// (stunned, draw, or battle already finished).
	/// Events in outEvents include TurnStarted (caller owns them).
	public int32 BeginTurn(List<BattleEvent> outEvents)
	{
		outEvents.Clear();
		if (mState != .InProgress) return -1;

		// Check max turns
		if (mTurnCount >= BattleConstants.MAX_TURNS)
		{
			mState = .Draw;
			EmitEvent(.BattleEnded);
			FlushEvents(outEvents);
			return -1;
		}

		let unitIdx = AdvanceToNextTurn();
		if (unitIdx < 0)
		{
			mState = .Draw;
			EmitEvent(.BattleEnded);
			FlushEvents(outEvents);
			return -1;
		}

		let unit = mUnits[unitIdx];

		// Stunned units skip their turn
		if (unit.IsStunned)
		{
			unit.ResetActionTimer();
			CheckBattleEnd();
			FlushEvents(outEvents);
			return -1;
		}

		FlushEvents(outEvents); // Contains TurnStarted event
		return unitIdx;
	}

	/// Submit an action for the current unit. Call after BeginTurn() returns a valid unit index.
	/// Executes the action, resets the timer, checks win/loss.
	/// Events in outEvents include action results (caller owns them).
	public void SubmitAction(BattleAction action, List<BattleEvent> outEvents)
	{
		outEvents.Clear();
		let unit = mUnits[action.mUnitIndex];

		Console.WriteLine("[STEP T{}] Unit {} '{}' at ({},{}) -> action={}",
			mTurnCount, action.mUnitIndex, unit.mConfig.mName, unit.mPosition.Q, unit.mPosition.R, action.mType);

		mActionLog.Add(action);
		ExecuteAction(action);
		unit.ResetActionTimer();
		CheckBattleEnd();
		ValidateGridConsistency();
		FlushEvents(outEvents);
	}

	/// Run one full turn: advance to next unit, get AI action, execute it.
	/// Convenience method that calls BeginTurn + AI + SubmitAction.
	/// Returns the events generated this step (caller owns them).
	public void Step(List<BattleEvent> outEvents)
	{
		let unitIdx = BeginTurn(outEvents);
		if (unitIdx < 0) return;

		let action = BattleAI.DecideAction(this, unitIdx, mDifficulty);

		var actionEvents = scope List<BattleEvent>();
		SubmitAction(action, actionEvents);
		outEvents.AddRange(actionEvents);
	}

	/// Debug: validate that unit positions and grid occupancy are in sync.
	private void ValidateGridConsistency()
	{
		// Check that every alive unit's position is marked as occupied by that unit
		for (int32 i = 0; i < mUnits.Count; i++)
		{
			let unit = mUnits[i];
			if (!unit.mAlive) continue;

			let occupant = mGrid.GetOccupant(unit.mPosition);
			if (occupant != i)
			{
				Console.WriteLine("[VALIDATE-ERR] Unit {} '{}' at ({},{}) but grid says occupant={}!",
					i, unit.mConfig.mName, unit.mPosition.Q, unit.mPosition.R, occupant);
			}
		}

		// Check that every occupied cell has a corresponding alive unit
		for (int32 row = 0; row < mGrid.Rows; row++)
		{
			for (int32 col = 0; col < mGrid.Columns; col++)
			{
				let hex = HexCoord.FromOffset(col, row);
				let occupant = mGrid.GetOccupant(hex);
				if (occupant >= 0)
				{
					if (occupant >= mUnits.Count)
					{
						Console.WriteLine("[VALIDATE-ERR] Grid ({},{}) has occupant {} but only {} units exist!",
							hex.Q, hex.R, occupant, mUnits.Count);
					}
					else
					{
						let unit = mUnits[occupant];
						if (!unit.mAlive)
						{
							Console.WriteLine("[VALIDATE-ERR] Grid ({},{}) occupied by dead unit {} '{}'!",
								hex.Q, hex.R, occupant, unit.mConfig.mName);
						}
						else if (unit.mPosition != hex)
						{
							Console.WriteLine("[VALIDATE-ERR] Grid ({},{}) says unit {} '{}' but unit says ({},{})!",
								hex.Q, hex.R, occupant, unit.mConfig.mName, unit.mPosition.Q, unit.mPosition.R);
						}
					}
				}
			}
		}

		// Check for duplicate positions among alive units
		for (int32 i = 0; i < mUnits.Count; i++)
		{
			let a = mUnits[i];
			if (!a.mAlive) continue;
			for (int32 j = i + 1; j < mUnits.Count; j++)
			{
				let b = mUnits[j];
				if (!b.mAlive) continue;
				if (a.mPosition == b.mPosition)
				{
					Console.WriteLine("[VALIDATE-ERR] DOUBLE OCCUPANCY! Unit {} '{}' and unit {} '{}' both at ({},{})!",
						i, a.mConfig.mName, j, b.mConfig.mName, a.mPosition.Q, a.mPosition.R);
				}
			}
		}
	}

	// --- Action execution ---

	public void ExecuteAction(BattleAction action)
	{
		switch (action.mType)
		{
		case .Move:
			ExecuteMove(action.mUnitIndex, action.mTargetHex);
		case .Attack:
			ExecuteAttack(action.mUnitIndex, action.mTargetUnit);
		case .UseSkill:
			ExecuteSkill(action.mUnitIndex, action.mSkillId, action.mTargetUnit);
		case .Wait:
			// Do nothing
		}
	}

	private void ExecuteMove(int32 unitIdx, HexCoord dest)
	{
		let unit = mUnits[unitIdx];
		let from = unit.mPosition;

		// Debug: check destination occupancy before pathfinding
		let existingOccupant = mGrid.GetOccupant(dest);
		if (existingOccupant >= 0 && existingOccupant != unitIdx)
		{
			Console.WriteLine("[MOVE-BLOCKED] Unit {} '{}' at ({},{}) wants ({},{}) but unit {} already there!",
				unitIdx, unit.mConfig.mName, from.Q, from.R, dest.Q, dest.R, existingOccupant);
			return;
		}

		let path = scope List<HexCoord>();
		let flying = unit.mConfig.mMoveType == .Flying;
		if (!mPathfinder.FindPath(from, dest, flying, path))
		{
			Console.WriteLine("[MOVE-NOPATH] Unit {} '{}' at ({},{}) no path to ({},{})",
				unitIdx, unit.mConfig.mName, from.Q, from.R, dest.Q, dest.R);
			return;
		}

		// Validate path length against move range
		if (path.Count - 1 > unit.mModifiedMoveRange)
		{
			Console.WriteLine("[MOVE-RANGE] Unit {} '{}' path length {} > move range {}",
				unitIdx, unit.mConfig.mName, path.Count - 1, unit.mModifiedMoveRange);
			return;
		}

		Console.WriteLine("[MOVE] Unit {} '{}' ({},{}) -> ({},{})",
			unitIdx, unit.mConfig.mName, from.Q, from.R, dest.Q, dest.R);

		// Move unit
		mGrid.ClearOccupant(from);
		unit.mPosition = dest;
		mGrid.SetOccupant(dest, unitIdx);

		let evt = EmitEvent(.UnitMoved, unitIdx);
		evt.mFromHex = from;
		evt.mToHex = dest;
	}

	private void ExecuteAttack(int32 attackerIdx, int32 defenderIdx)
	{
		let attacker = mUnits[attackerIdx];
		let defender = mUnits[defenderIdx];

		if (!defender.mAlive) return;

		// Check range
		let dist = attacker.mPosition.DistanceTo(defender.mPosition);
		if (dist > attacker.mModifiedAttackRange) return;

		EmitEvent(.UnitAttacked, attackerIdx).mTargetUnit = defenderIdx;

		// Trigger OnAttack skills
		TriggerSkills(attackerIdx, .OnAttack, defenderIdx);

		// Get targets from attack pattern
		let targets = scope List<HexCoord>();
		mGrid.GetAttackPatternCells(attacker.mPosition, defender.mPosition, attacker.mConfig.mAttackPattern, targets);

		// Apply damage to all units in pattern
		for (let hex in targets)
		{
			let occupant = mGrid.GetOccupant(hex);
			if (occupant < 0) continue;
			let target = mUnits[occupant];
			if (!target.mAlive) continue;
			if (target.mForce == attacker.mForce) continue; // Don't hit allies

			let damage = CalculateDamage(attacker, target);
			ApplyDamage(attackerIdx, occupant, damage, attacker.mConfig.mDamageType);
		}

		// Trigger OnHit skills on attacker
		TriggerSkills(attackerIdx, .OnHit, defenderIdx);

		// Counter-attack check
		if (defender.mAlive && !defender.IsStunned)
		{
			TriggerSkills(defenderIdx, .OnDamaged, attackerIdx);
		}
	}

	public void ExecuteSkill(int32 userIdx, int32 skillId, int32 targetIdx)
	{
		let user = mUnits[userIdx];
		let skillConfig = mConfigs.GetSkill(skillId);
		if (skillConfig == null) return;

		if (user.IsSkillOnCooldown(skillId)) return;
		if (user.IsSkillUsesExhausted(skillId, skillConfig)) return;

		let evt = EmitEvent(.SkillUsed, userIdx);
		evt.mSkillId = skillId;
		evt.mTargetUnit = targetIdx;

		for (let effect in skillConfig.mEffects)
		{
			switch (effect.mType)
			{
			case .Damage:
				if (targetIdx >= 0 && targetIdx < mUnits.Count)
				{
					let target = mUnits[targetIdx];
					if (target.mAlive)
					{
						let baseDmg = (int32)((float)(user.SoldierCount * user.mModifiedDamage) * effect.mValue);
						ApplyDamage(userIdx, targetIdx, baseDmg, user.mConfig.mDamageType);
					}
				}

			case .Heal:
				let healTarget = targetIdx >= 0 ? targetIdx : userIdx;
				if (healTarget < mUnits.Count)
				{
					let target = mUnits[healTarget];
					if (target.mAlive)
					{
						let healed = target.Heal((int32)effect.mValue);
						if (healed > 0)
						{
							mTotalHealingDone += healed;
							let healEvt = EmitEvent(.HealApplied, userIdx);
							healEvt.mTargetUnit = (.)healTarget;
							healEvt.mValue = healed;
						}
					}
				}

			case .ApplyBuff:
				if (effect.mBuffId != 0)
				{
					let buffTarget = targetIdx >= 0 ? targetIdx : userIdx;
					ApplyBuff(buffTarget, effect.mBuffId, userIdx);
				}

			case .Dispel:
				if (targetIdx >= 0 && targetIdx < mUnits.Count)
					DispelBuffs(targetIdx, effect.mDispelCount, userIdx);

			case .Summon:
				// TODO: implement summon
			case .Counter:
				// Counter is handled passively via OnDamaged trigger
			}
		}

		user.PutSkillOnCooldown(skillId, skillConfig.mCooldown);
		user.RecordSkillUse(skillId);
	}

	// --- Damage calculation ---

	public int32 CalculateDamage(BattleUnit attacker, BattleUnit defender)
	{
		// Raw damage based on soldier count
		let rawDamage = (float)(attacker.SoldierCount * attacker.mModifiedDamage);

		// Defense reduction based on damage type
		float effectiveDefense = (float)defender.mModifiedDefense;

		switch (attacker.mConfig.mDamageType)
		{
		case .Physical:
			// Full defense applies
		case .Piercing:
			effectiveDefense *= (1.0f - BattleConstants.PIERCING_ARMOR_IGNORE);
		case .Magic:
			effectiveDefense *= (1.0f - BattleConstants.MAGIC_DEFENSE_IGNORE);
		}

		let defenseReduction = Math.Min(
			effectiveDefense / (effectiveDefense + BattleConstants.DEFENSE_SCALE),
			BattleConstants.MAX_DEFENSE_REDUCTION
		);

		let finalDamage = (int32)(rawDamage * (1.0f - defenseReduction));
		return Math.Max(1, finalDamage); // Minimum 1 damage
	}

	private void ApplyDamage(int32 attackerIdx, int32 targetIdx, int32 damage, DamageType damageType)
	{
		let target = mUnits[targetIdx];
		let actual = target.TakeDamage(damage);
		mTotalDamageDealt += actual;

		let evt = EmitEvent(.DamageDealt, attackerIdx);
		evt.mTargetUnit = targetIdx;
		evt.mValue = actual;
		evt.mDamageType = damageType;

		if (!target.mAlive)
		{
			mGrid.ClearOccupant(target.mPosition);
			EmitEvent(.UnitDied, targetIdx);
			mUnitsKilled++;
			TriggerSkills(attackerIdx, .OnKill, targetIdx);
			TriggerSkills(targetIdx, .OnDeath, attackerIdx);
		}
	}

	// --- Buff system ---

	public void ApplyBuff(int32 targetIdx, int32 buffId, int32 sourceIdx)
	{
		let target = mUnits[targetIdx];
		let buffConfig = mConfigs.GetBuff(buffId);
		if (buffConfig == null) return;
		if (!target.mAlive) return;

		// Immunity check
		if (buffConfig.mFlag == .Negative && target.HasImmunity(buffConfig.mTag))
			return;

		// Stacking: same buff refreshes duration
		for (let existing in target.mBuffs)
		{
			if (existing.mConfig.mId == buffId)
			{
				existing.mRemainingDuration = buffConfig.mDuration;
				return;
			}
		}

		let instance = new BuffInstance(buffConfig, sourceIdx);
		target.mBuffs.Add(instance);
		target.RecalculateStats();

		let evt = EmitEvent(.BuffApplied, sourceIdx);
		evt.mTargetUnit = targetIdx;
		evt.mBuffId = buffId;
	}

	public void RemoveBuff(int32 targetIdx, BuffInstance buff)
	{
		let target = mUnits[targetIdx];
		target.mBuffs.Remove(buff);
		target.RecalculateStats();

		let evt = EmitEvent(.BuffRemoved, targetIdx);
		evt.mBuffId = buff.mConfig.mId;

		delete buff;
	}

	private void DispelBuffs(int32 targetIdx, int32 count, int32 sourceIdx)
	{
		let target = mUnits[targetIdx];
		var remaining = count;
		let toRemove = scope List<BuffInstance>();

		for (let buff in target.mBuffs)
		{
			if (remaining <= 0) break;
			if (!buff.mConfig.mCanDispel) continue;

			// Dispel positive buffs from enemies, negative buffs from allies
			let sourceUnit = mUnits[sourceIdx];
			if (target.mForce != sourceUnit.mForce && buff.mConfig.mFlag == .Positive)
			{
				toRemove.Add(buff);
				remaining--;
			}
			else if (target.mForce == sourceUnit.mForce && buff.mConfig.mFlag == .Negative)
			{
				toRemove.Add(buff);
				remaining--;
			}
		}

		for (let buff in toRemove)
			RemoveBuff(targetIdx, buff);
	}

	private void TickBuffs(int32 unitIdx)
	{
		let unit = mUnits[unitIdx];
		let toRemove = scope List<BuffInstance>();

		for (let buff in unit.mBuffs)
		{
			// Apply DoT
			if (buff.mConfig.mDotDamage > 0 && unit.mAlive)
			{
				let dmg = (int32)buff.mConfig.mDotDamage;
				let actual = unit.TakeDamage(dmg);
				let evt = EmitEvent(.BuffTicked, unitIdx);
				evt.mBuffId = buff.mConfig.mId;
				evt.mValue = -actual;

				if (!unit.mAlive)
				{
					mGrid.ClearOccupant(unit.mPosition);
					EmitEvent(.UnitDied, unitIdx);
				}
			}

			// Apply HoT
			if (buff.mConfig.mHotHeal > 0 && unit.mAlive)
			{
				let healed = unit.Heal((int32)buff.mConfig.mHotHeal);
				if (healed > 0)
				{
					let evt = EmitEvent(.BuffTicked, unitIdx);
					evt.mBuffId = buff.mConfig.mId;
					evt.mValue = healed;
				}
			}

			// Tick duration
			if (!buff.Tick())
				toRemove.Add(buff);
		}

		for (let buff in toRemove)
			RemoveBuff(unitIdx, buff);
	}

	// --- Skill triggers ---

	private void TriggerSkills(int32 unitIdx, SkillMoment moment, int32 targetIdx)
	{
		let unit = mUnits[unitIdx];
		if (!unit.mAlive) return;
		if (unit.IsSilenced && moment != .Passive) return;

		for (let skillId in unit.mConfig.mSkillIds)
		{
			let skillConfig = mConfigs.GetSkill(skillId);
			if (skillConfig == null) continue;
			if (skillConfig.mMoment != moment) continue;
			if (unit.IsSkillOnCooldown(skillId)) continue;
			if (unit.IsSkillUsesExhausted(skillId, skillConfig)) continue;

			// Proc chance
			if (skillConfig.mChance < 1.0f)
			{
				if (mRng.NextDouble() > skillConfig.mChance)
					continue;
			}

			ExecuteSkill(unitIdx, skillId, targetIdx);
		}
	}

	// --- Battle end check ---

	private void CheckBattleEnd()
	{
		bool attackersAlive = false;
		bool defendersAlive = false;

		for (let unit in mUnits)
		{
			if (!unit.mAlive) continue;
			if (unit.mForce == .Attacker) attackersAlive = true;
			if (unit.mForce == .Defender) defendersAlive = true;
			if (attackersAlive && defendersAlive) return; // Both alive, continue
		}

		if (!attackersAlive && !defendersAlive)
			mState = .Draw;
		else if (!attackersAlive)
			mState = .DefenderWins;
		else
			mState = .AttackerWins;

		let evt = EmitEvent(.BattleEnded);
		evt.mWinner = mState == .AttackerWins ? .Attacker : .Defender;
	}

	// --- Event emission ---

	private BattleEvent EmitEvent(BattleEventType type, int32 sourceUnit = -1)
	{
		let evt = new BattleEvent();
		evt.mType = type;
		evt.mSourceUnit = sourceUnit;
		mEventQueue.Add(evt);
		return evt;
	}

	private void FlushEvents(List<BattleEvent> outEvents)
	{
		for (let evt in mEventQueue)
			outEvents.Add(evt);
		mEventQueue.Clear(); // Ownership transferred to caller
	}

	// --- Result ---

	/// Get the battle result. Only valid after IsFinished == true.
	/// Caller owns the returned BattleResult.
	public BattleResult GetResult()
	{
		let result = new BattleResult();
		result.mOutcome = mState;
		result.mWinner = mState == .AttackerWins ? .Attacker : .Defender;
		result.mTotalTurns = mTurnCount;
		result.mTotalDamageDealt = mTotalDamageDealt;
		result.mTotalHealingDone = mTotalHealingDone;
		result.mUnitsKilled = mUnitsKilled;

		for (let unit in mUnits)
		{
			if (!unit.mAlive) continue;
			if (unit.mForce == .Attacker)
				result.mSurvivingAttackers.Add(unit.mIndex);
			else
				result.mSurvivingDefenders.Add(unit.mIndex);
		}

		return result;
	}

	// --- Replay ---

	/// Get the recorded action log (for replay serialization).
	public List<BattleAction> ActionLog => mActionLog;

	/// Get initial setup parameters for replay reproduction.
	public void GetReplaySetup(List<FormationSlot> outAttackers, List<FormationSlot> outDefenders,
		out int32 columns, out int32 rows, out int64 seed)
	{
		columns = mInitColumns;
		rows = mInitRows;
		seed = mInitSeed;
		if (mInitAttackers != null)
			for (let s in mInitAttackers) outAttackers.Add(s);
		if (mInitDefenders != null)
			for (let s in mInitDefenders) outDefenders.Add(s);
	}

	/// Replay a battle from initial state + recorded actions.
	/// Creates a new simulation, replays all actions, returns events.
	public static BattleSimulation Replay(ConfigDatabase configs,
		List<FormationSlot> attackers, List<FormationSlot> defenders,
		int32 columns, int32 rows, int64 seed,
		List<BattleAction> actions, List<BattleEvent> outAllEvents)
	{
		let sim = new BattleSimulation(configs);
		sim.Initialize(attackers, defenders, columns, rows, seed);

		let stepEvents = scope List<BattleEvent>();
		for (let action in actions)
		{
			if (sim.IsFinished) break;

			// Advance turn (same as Step but using recorded action)
			if (sim.mTurnCount >= BattleConstants.MAX_TURNS)
			{
				sim.mState = .Draw;
				sim.EmitEvent(.BattleEnded);
				sim.FlushEvents(stepEvents);
				for (let e in stepEvents) outAllEvents.Add(e);
				stepEvents.Clear();
				break;
			}

			let unitIdx = sim.AdvanceToNextTurn();
			if (unitIdx < 0) break;

			let unit = sim.GetUnit(unitIdx);
			if (unit.IsStunned)
			{
				unit.ResetActionTimer();
				sim.CheckBattleEnd();
				sim.FlushEvents(stepEvents);
				for (let e in stepEvents) outAllEvents.Add(e);
				stepEvents.Clear();
				continue;
			}

			sim.ExecuteAction(action);
			unit.ResetActionTimer();
			sim.CheckBattleEnd();
			sim.FlushEvents(stepEvents);
			for (let e in stepEvents) outAllEvents.Add(e);
			stepEvents.Clear();
		}

		return sim;
	}
}
