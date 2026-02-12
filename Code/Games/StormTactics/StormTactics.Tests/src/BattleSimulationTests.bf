namespace StormTactics.Tests;

using System;
using System.Collections;
using StormTactics.Core;
using StormTactics.Battle;

class BattleSimulationTests
{
	// --- Helper to create a minimal ConfigDatabase with test configs ---

	private static ConfigDatabase CreateTestConfigs()
	{
		let db = new ConfigDatabase();
		return db;
	}

	private static UnitConfig MakeMeleeUnit(int32 id, StringView name, int32 soldierHP, int32 count, int32 damage, int32 defense, int32 speed)
	{
		let config = new UnitConfig();
		config.mId = id;
		config.mName.Set(name);
		config.mRarity = .Common;
		config.mUnitClass = .Infantry;
		config.mRace = .Human;
		config.mSoldierHP = soldierHP;
		config.mSoldierCount = count;
		config.mDefense = defense;
		config.mSoldierDamage = damage;
		config.mDamageType = .Physical;
		config.mIsRanged = false;
		config.mAttackRange = 1;
		config.mAttackPattern = .Point;
		config.mMoveType = .Land;
		config.mMoveRange = 2;
		config.mActionSpeed = speed;
		return config;
	}

	// --- BattleUnit tests ---

	[Test]
	public static void TestBattleUnitInitialize()
	{
		let config = MakeMeleeUnit(1, "Test", 100, 5, 10, 20, 80);
		defer delete config;

		let unit = scope BattleUnit();
		unit.Initialize(0, config, .Attacker, HexCoord(0, 0), 0);

		Test.Assert(unit.mMaxHP == 500); // 100 * 5
		Test.Assert(unit.mCurrentHP == 500);
		Test.Assert(unit.mAlive == true);
		Test.Assert(unit.SoldierCount == 5);
		Test.Assert(unit.mModifiedDamage == 10);
		Test.Assert(unit.mModifiedDefense == 20);
	}

	[Test]
	public static void TestSoldierCountDecreases()
	{
		let config = MakeMeleeUnit(1, "Test", 100, 5, 10, 20, 80);
		defer delete config;

		let unit = scope BattleUnit();
		unit.Initialize(0, config, .Attacker, HexCoord(0, 0), 0);

		// Take 150 damage — should lose 2 soldiers (350 HP / 100 HP per soldier = 4 soldiers)
		unit.TakeDamage(150);
		Test.Assert(unit.mCurrentHP == 350);
		Test.Assert(unit.SoldierCount == 4);

		// Take 250 more — should be at 100 HP = 1 soldier
		unit.TakeDamage(250);
		Test.Assert(unit.mCurrentHP == 100);
		Test.Assert(unit.SoldierCount == 1);
	}

	[Test]
	public static void TestUnitDeath()
	{
		let config = MakeMeleeUnit(1, "Test", 100, 3, 10, 20, 80);
		defer delete config;

		let unit = scope BattleUnit();
		unit.Initialize(0, config, .Attacker, HexCoord(0, 0), 0);

		let actual = unit.TakeDamage(999);
		Test.Assert(actual == 300); // Can only deal up to maxHP
		Test.Assert(unit.mCurrentHP == 0);
		Test.Assert(unit.mAlive == false);
		Test.Assert(unit.SoldierCount == 0);
	}

	[Test]
	public static void TestUnitHeal()
	{
		let config = MakeMeleeUnit(1, "Test", 100, 5, 10, 20, 80);
		defer delete config;

		let unit = scope BattleUnit();
		unit.Initialize(0, config, .Attacker, HexCoord(0, 0), 0);

		unit.TakeDamage(200);
		Test.Assert(unit.mCurrentHP == 300);

		let healed = unit.Heal(100);
		Test.Assert(healed == 100);
		Test.Assert(unit.mCurrentHP == 400);

		// Can't overheal
		let healed2 = unit.Heal(999);
		Test.Assert(healed2 == 100);
		Test.Assert(unit.mCurrentHP == 500);
	}

	// --- Damage calculation tests ---

	[Test]
	public static void TestDamageCalculationPhysical()
	{
		// Physical damage: full defense applies
		let attackerConfig = MakeMeleeUnit(1, "Attacker", 100, 5, 20, 10, 80);
		defer delete attackerConfig;
		let defenderConfig = MakeMeleeUnit(2, "Defender", 100, 5, 10, 50, 80);
		defer delete defenderConfig;

		let attacker = scope BattleUnit();
		attacker.Initialize(0, attackerConfig, .Attacker, HexCoord(0, 0), 0);
		let defender = scope BattleUnit();
		defender.Initialize(1, defenderConfig, .Defender, HexCoord(1, 0), 0);

		let db = scope ConfigDatabase();
		let sim = scope BattleSimulation(db);

		let damage = sim.CalculateDamage(attacker, defender);

		// rawDamage = 5 soldiers * 20 damage = 100
		// effectiveDefense = 50 (physical, full defense)
		// defenseReduction = 50 / (50 + 100) = 0.333
		// finalDamage = 100 * (1 - 0.333) = 66
		Test.Assert(damage == 66);
	}

	[Test]
	public static void TestDamageCalculationPiercing()
	{
		let attackerConfig = MakeMeleeUnit(1, "Attacker", 100, 5, 20, 10, 80);
		attackerConfig.mDamageType = .Piercing;
		defer delete attackerConfig;
		let defenderConfig = MakeMeleeUnit(2, "Defender", 100, 5, 10, 50, 80);
		defer delete defenderConfig;

		let attacker = scope BattleUnit();
		attacker.Initialize(0, attackerConfig, .Attacker, HexCoord(0, 0), 0);
		let defender = scope BattleUnit();
		defender.Initialize(1, defenderConfig, .Defender, HexCoord(1, 0), 0);

		let db = scope ConfigDatabase();
		let sim = scope BattleSimulation(db);

		let damage = sim.CalculateDamage(attacker, defender);

		// rawDamage = 100
		// effectiveDefense = 50 * (1 - 0.5) = 25 (piercing ignores 50% armor)
		// defenseReduction = 25 / (25 + 100) = 0.2
		// finalDamage = 100 * 0.8 = 80
		Test.Assert(damage == 80);
	}

	[Test]
	public static void TestDamageCalculationMagic()
	{
		let attackerConfig = MakeMeleeUnit(1, "Attacker", 100, 5, 20, 10, 80);
		attackerConfig.mDamageType = .Magic;
		defer delete attackerConfig;
		let defenderConfig = MakeMeleeUnit(2, "Defender", 100, 5, 10, 50, 80);
		defer delete defenderConfig;

		let attacker = scope BattleUnit();
		attacker.Initialize(0, attackerConfig, .Attacker, HexCoord(0, 0), 0);
		let defender = scope BattleUnit();
		defender.Initialize(1, defenderConfig, .Defender, HexCoord(1, 0), 0);

		let db = scope ConfigDatabase();
		let sim = scope BattleSimulation(db);

		let damage = sim.CalculateDamage(attacker, defender);

		// rawDamage = 100
		// effectiveDefense = 50 * (1 - 1.0) = 0 (magic ignores all physical defense)
		// defenseReduction = 0 / (0 + 100) = 0
		// finalDamage = 100 * 1.0 = 100
		Test.Assert(damage == 100);
	}

	// --- Turn order tests ---

	[Test]
	public static void TestTurnOrderFasterGoesFirst()
	{
		let slowConfig = MakeMeleeUnit(1, "Slow", 100, 5, 10, 10, 50);
		defer delete slowConfig;
		let fastConfig = MakeMeleeUnit(2, "Fast", 100, 5, 10, 10, 100);
		defer delete fastConfig;

		let slow = scope BattleUnit();
		slow.Initialize(0, slowConfig, .Attacker, HexCoord(0, 0), 0);
		let fast = scope BattleUnit();
		fast.Initialize(1, fastConfig, .Defender, HexCoord(1, 0), 0);

		// Slow: timer = 1000/50 = 20
		// Fast: timer = 1000/100 = 10
		Test.Assert(slow.mActionTimer > fast.mActionTimer);
	}

	// --- Buff tests ---

	[Test]
	public static void TestBuffApplication()
	{
		let config = MakeMeleeUnit(1, "Test", 100, 5, 10, 20, 80);
		defer delete config;

		let unit = scope BattleUnit();
		unit.Initialize(0, config, .Attacker, HexCoord(0, 0), 0);

		// Create a buff that adds 50% defense
		let buffConfig = new BuffConfig();
		defer delete buffConfig;
		buffConfig.mId = 100;
		buffConfig.mName.Set("Test Buff");
		buffConfig.mFlag = .Positive;
		buffConfig.mTag = .DefenseUp;
		buffConfig.mDuration = 3;
		let mod = new StatModifier();
		mod.mAttribute = .Defense;
		mod.mPercentValue = 0.5f;
		buffConfig.mStatModifiers.Add(mod);

		let buffInst = new BuffInstance(buffConfig, 0);
		unit.mBuffs.Add(buffInst);
		unit.RecalculateStats();

		// Defense: 20 * 1.5 = 30
		Test.Assert(unit.mModifiedDefense == 30);
	}

	[Test]
	public static void TestBuffExpiry()
	{
		let buffConfig = new BuffConfig();
		defer delete buffConfig;
		buffConfig.mId = 100;
		buffConfig.mName.Set("Test Buff");
		buffConfig.mDuration = 2;

		let buff = scope BuffInstance(buffConfig, 0);

		Test.Assert(!buff.IsExpired);
		Test.Assert(buff.Tick()); // 1 turn remaining
		Test.Assert(!buff.IsExpired);
		Test.Assert(!buff.Tick()); // 0 turns remaining
		Test.Assert(buff.IsExpired);
	}

	// --- Cooldown tests ---

	[Test]
	public static void TestSkillCooldown()
	{
		let config = MakeMeleeUnit(1, "Test", 100, 5, 10, 20, 80);
		defer delete config;

		let unit = scope BattleUnit();
		unit.Initialize(0, config, .Attacker, HexCoord(0, 0), 0);

		Test.Assert(!unit.IsSkillOnCooldown(1));
		unit.PutSkillOnCooldown(1, 3);
		Test.Assert(unit.IsSkillOnCooldown(1));
		unit.TickCooldowns(); // 2 remaining
		Test.Assert(unit.IsSkillOnCooldown(1));
		unit.TickCooldowns(); // 1 remaining
		Test.Assert(unit.IsSkillOnCooldown(1));
		unit.TickCooldowns(); // 0 remaining, removed
		Test.Assert(!unit.IsSkillOnCooldown(1));
	}

	// --- Win/loss detection ---

	[Test]
	public static void TestBattleEndsWhenOneSideEliminated()
	{
		// Set up a ConfigDatabase with two unit types
		let db = new ConfigDatabase();
		defer delete db;

		let weakConfig = MakeMeleeUnit(1, "Weak", 10, 1, 100, 0, 80);
		db.RegisterUnit(weakConfig); // db takes ownership

		let strongConfig = MakeMeleeUnit(2, "Strong", 1000, 1, 100, 0, 100);
		db.RegisterUnit(strongConfig);

		// Create formations — weak attacker vs strong defender, adjacent hexes
		let attackers = scope List<FormationSlot>();
		let aSlot = new FormationSlot();
		aSlot.mUnitId = 1;
		aSlot.mGridX = 0;
		aSlot.mGridY = 0;
		attackers.Add(aSlot);
		defer { for (let s in attackers) delete s; }

		let defenders = scope List<FormationSlot>();
		let dSlot = new FormationSlot();
		dSlot.mUnitId = 2;
		dSlot.mGridX = 1;
		dSlot.mGridY = 0;
		defenders.Add(dSlot);
		defer { for (let s in defenders) delete s; }

		// Run battle simulation to completion
		let sim = new BattleSimulation(db);
		defer delete sim;
		sim.Initialize(attackers, defenders, 7, 6, 42);

		Test.Assert(sim.State == .InProgress);

		let events = scope List<BattleEvent>();

		// Step until battle ends (should be fast — units are adjacent and one is very weak)
		var steps = 0;
		while (!sim.IsFinished && steps < 200)
		{
			sim.Step(events);
			// Delete events from this step (Step clears the list on next call, orphaning them)
			for (let e in events) delete e;
			events.Clear();
			steps++;
		}

		Test.Assert(sim.IsFinished);
		// Strong defender should win — weak attacker has only 10 HP
		Test.Assert(sim.State == .DefenderWins);
	}

	// --- BattleAction factory tests ---

	[Test]
	public static void TestBattleActionFactories()
	{
		let move = BattleAction.MakeMove(0, HexCoord(1, 2));
		Test.Assert(move.mType == .Move);
		Test.Assert(move.mUnitIndex == 0);
		Test.Assert(move.mTargetHex.Q == 1);
		Test.Assert(move.mTargetHex.R == 2);

		let attack = BattleAction.MakeAttack(1, 2);
		Test.Assert(attack.mType == .Attack);
		Test.Assert(attack.mUnitIndex == 1);
		Test.Assert(attack.mTargetUnit == 2);

		let skill = BattleAction.MakeSkill(0, 101, 3);
		Test.Assert(skill.mType == .UseSkill);
		Test.Assert(skill.mSkillId == 101);
		Test.Assert(skill.mTargetUnit == 3);

		let wait = BattleAction.MakeWait(0);
		Test.Assert(wait.mType == .Wait);
	}

	// --- Full battle simulation with fixed seed ---

	[Test]
	public static void TestFullBattleFixedSeed()
	{
		// Set up a proper 3v3 battle with known configs
		let db = new ConfigDatabase();
		defer delete db;

		// Attackers: 3 strong melee units
		let attackerConfig = MakeMeleeUnit(1, "Warrior", 100, 5, 20, 15, 90);
		db.RegisterUnit(attackerConfig);

		// Defenders: 3 weak melee units
		let defenderConfig = MakeMeleeUnit(2, "Militia", 80, 4, 12, 10, 70);
		db.RegisterUnit(defenderConfig);

		let attackers = scope List<FormationSlot>();
		for (int32 i = 0; i < 3; i++)
		{
			let slot = new FormationSlot();
			slot.mUnitId = 1;
			slot.mGridX = 0;
			slot.mGridY = (.)i;
			attackers.Add(slot);
		}
		defer { for (let s in attackers) delete s; }

		let defenders = scope List<FormationSlot>();
		for (int32 i = 0; i < 3; i++)
		{
			let slot = new FormationSlot();
			slot.mUnitId = 2;
			slot.mGridX = 2;
			slot.mGridY = (.)i;
			defenders.Add(slot);
		}
		defer { for (let s in defenders) delete s; }

		// Run battle with fixed seed
		let sim = new BattleSimulation(db);
		defer delete sim;
		sim.Initialize(attackers, defenders, 7, 6, 12345);

		Test.Assert(sim.UnitCount == 6);

		let events = scope List<BattleEvent>();

		var steps = 0;
		while (!sim.IsFinished && steps < 500)
		{
			sim.Step(events);
			for (let e in events) delete e;
			events.Clear();
			steps++;
		}

		Test.Assert(sim.IsFinished);
		// Attackers are stronger (5 soldiers × 20 dmg vs 4 × 12, more HP, faster)
		Test.Assert(sim.State == .AttackerWins);

		// Verify result
		let result = sim.GetResult();
		defer delete result;
		Test.Assert(result.mOutcome == .AttackerWins);
		Test.Assert(result.mSurvivingAttackers.Count > 0);
		Test.Assert(result.mSurvivingDefenders.Count == 0);
		Test.Assert(result.mTotalDamageDealt > 0);
		Test.Assert(result.mUnitsKilled >= 3); // At least the 3 defenders died
		Test.Assert(result.mTotalTurns > 0);

		// Verify replay produces same outcome
		let replayAttackers = scope List<FormationSlot>();
		let replayDefenders = scope List<FormationSlot>();
		int32 cols = 0, rows = 0;
		int64 seed = 0;
		sim.GetReplaySetup(replayAttackers, replayDefenders, out cols, out rows, out seed);

		let replayEvents = scope List<BattleEvent>();
		let replaySim = BattleSimulation.Replay(db, replayAttackers, replayDefenders,
			cols, rows, seed, sim.ActionLog, replayEvents);
		defer delete replaySim;
		defer { for (let e in replayEvents) delete e; }

		Test.Assert(replaySim.State == sim.State);
		Test.Assert(replaySim.TurnCount == sim.TurnCount);
	}

	// --- GetResult test ---

	[Test]
	public static void TestGetResult()
	{
		let db = new ConfigDatabase();
		defer delete db;

		let strongConfig = MakeMeleeUnit(1, "Strong", 500, 3, 50, 0, 100);
		db.RegisterUnit(strongConfig);
		let weakConfig = MakeMeleeUnit(2, "Weak", 10, 1, 5, 0, 50);
		db.RegisterUnit(weakConfig);

		let attackers = scope List<FormationSlot>();
		let aSlot = new FormationSlot();
		aSlot.mUnitId = 1;
		aSlot.mGridX = 0;
		aSlot.mGridY = 0;
		attackers.Add(aSlot);
		defer { for (let s in attackers) delete s; }

		let defenders = scope List<FormationSlot>();
		let dSlot = new FormationSlot();
		dSlot.mUnitId = 2;
		dSlot.mGridX = 1;
		dSlot.mGridY = 0;
		defenders.Add(dSlot);
		defer { for (let s in defenders) delete s; }

		let sim = new BattleSimulation(db);
		defer delete sim;
		sim.Initialize(attackers, defenders, 7, 6, 0);

		let events = scope List<BattleEvent>();

		while (!sim.IsFinished)
		{
			sim.Step(events);
			for (let e in events) delete e;
			events.Clear();
		}

		let result = sim.GetResult();
		defer delete result;

		Test.Assert(result.mOutcome == .AttackerWins);
		Test.Assert(result.mWinner == .Attacker);
		Test.Assert(result.mSurvivingAttackers.Count == 1);
		Test.Assert(result.mSurvivingDefenders.Count == 0);
		Test.Assert(result.mUnitsKilled >= 1);
		Test.Assert(result.mTotalDamageDealt > 0);
	}
}
