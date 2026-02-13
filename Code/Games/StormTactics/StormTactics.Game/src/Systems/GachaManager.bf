namespace StormTactics.Game;

using System;
using System.Collections;
using StormTactics.Core;

/// Result of a single gacha pull.
class GachaResult
{
	public int32 mUnitId;
	public String mUnitName = new .() ~ delete _;
	public Rarity mRarity;
	public bool mIsNew;
	public int32 mShardsGained;
}

/// Manages gacha/summoning: roll rarity, select unit, pity system, duplicate→shards.
class GachaManager
{
	public const int32 SINGLE_PULL_COST = 300;
	public const int32 MULTI_PULL_COST = 2700; // 10x at 10% discount
	public const int32 PITY_THRESHOLD = 90;

	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private PlayerManager mPlayerMgr;
	private RosterManager mRosterMgr;
	private Random mRng ~ delete _;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs, PlayerManager playerMgr, RosterManager rosterMgr)
	{
		mSave = save;
		mConfigs = configs;
		mPlayerMgr = playerMgr;
		mRosterMgr = rosterMgr;
		mRng = new Random(DateTime.Now.Ticks);
	}

	/// Check if the player can afford a single pull.
	public bool CanPullSingle() => mSave.mGems >= SINGLE_PULL_COST;

	/// Check if the player can afford a 10x multi-pull.
	public bool CanPullMulti() => mSave.mGems >= MULTI_PULL_COST;

	/// Perform a single gacha pull. Returns null if can't afford.
	public GachaResult PullSingle()
	{
		if (!mPlayerMgr.TrySpendGems(SINGLE_PULL_COST))
			return null;

		return DoSinglePull();
	}

	/// Perform a 10x gacha pull. Returns empty list if can't afford.
	public List<GachaResult> PullMulti()
	{
		let results = new List<GachaResult>();

		if (!mPlayerMgr.TrySpendGems(MULTI_PULL_COST))
			return results;

		for (int i = 0; i < 10; i++)
			results.Add(DoSinglePull());

		return results;
	}

	private GachaResult DoSinglePull()
	{
		mSave.mGachaPityCounter++;

		// Roll rarity
		Rarity rarity;
		if (mSave.mGachaPityCounter >= PITY_THRESHOLD)
		{
			rarity = .Legendary;
			mSave.mGachaPityCounter = 0;
		}
		else
		{
			let roll = (float)mRng.NextDouble();
			if (roll < 0.03f)
			{
				rarity = .Legendary;
				mSave.mGachaPityCounter = 0; // Reset pity on natural legendary
			}
			else if (roll < 0.15f)
				rarity = .Epic;
			else if (roll < 0.50f)
				rarity = .Rare;
			else
				rarity = .Common;
		}

		// Pick a random unit of this rarity
		let candidates = scope List<UnitConfig>();
		for (let unit in mConfigs.Units)
		{
			if (unit.mRarity == rarity)
				candidates.Add(unit);
		}

		// Fallback: if no units of this rarity, pick any unit
		if (candidates.Count == 0)
		{
			for (let unit in mConfigs.Units)
				candidates.Add(unit);
		}

		if (candidates.Count == 0)
		{
			// No units at all — shouldn't happen
			let result = new GachaResult();
			result.mUnitId = 0;
			result.mRarity = rarity;
			return result;
		}

		let selected = candidates[mRng.Next((int32)candidates.Count)];
		let result = new GachaResult();
		result.mUnitId = selected.mId;
		result.mUnitName.Set(selected.mName);
		result.mRarity = selected.mRarity;

		// Check if new or duplicate
		if (mRosterMgr.HasUnit(selected.mId))
		{
			// Duplicate → convert to shards
			result.mIsNew = false;
			result.mShardsGained = GetDuplicateShards(rarity);
			mRosterMgr.AddShards(selected.mId, result.mShardsGained);
		}
		else
		{
			// New unit
			result.mIsNew = true;
			result.mShardsGained = 0;
			mRosterMgr.AddUnit(selected.mId);
		}

		Console.WriteLine("[Gacha] Pulled {} ({}) — {}", selected.mName, rarity, result.mIsNew ? "NEW!" : scope String()..AppendF("+{} shards", result.mShardsGained));
		return result;
	}

	private int32 GetDuplicateShards(Rarity rarity)
	{
		switch (rarity)
		{
		case .Common:    return 5;
		case .Uncommon:  return 10;
		case .Rare:      return 15;
		case .Epic:      return 30;
		case .Legendary: return 50;
		default:         return 5;
		}
	}
}
