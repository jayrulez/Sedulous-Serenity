namespace StormTactics.Core;

using System;
using System.IO;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Serialization.Xml;
using Sedulous.Xml;

/// Central registry holding all loaded game configs.
/// Owns all config objects and provides lookup by ID.
class ConfigDatabase
{
	private Dictionary<int32, UnitConfig> mUnits = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<int32, SkillConfig> mSkills = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<int32, BuffConfig> mBuffs = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<int32, StageConfig> mStages = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<int32, ItemConfig> mItems = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<int32, EquipConfig> mEquips = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<int32, ShopItemConfig> mShopItems = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<int32, HeroLevelConfig> mHeroLevels = new .() ~ DeleteDictionaryAndValues!(_);
	private List<StarLevelConfig> mStarLevels = new .() ~ DeleteContainerAndItems!(_);

	// --- Accessors ---

	public UnitConfig GetUnit(int32 id) => mUnits.GetValueOrDefault(id);
	public SkillConfig GetSkill(int32 id) => mSkills.GetValueOrDefault(id);
	public BuffConfig GetBuff(int32 id) => mBuffs.GetValueOrDefault(id);
	public StageConfig GetStage(int32 id) => mStages.GetValueOrDefault(id);
	public ItemConfig GetItem(int32 id) => mItems.GetValueOrDefault(id);
	public EquipConfig GetEquip(int32 id) => mEquips.GetValueOrDefault(id);
	public ShopItemConfig GetShopItem(int32 id) => mShopItems.GetValueOrDefault(id);
	public HeroLevelConfig GetHeroLevel(int32 level) => mHeroLevels.GetValueOrDefault(level);

	public Dictionary<int32, UnitConfig>.ValueEnumerator Units => mUnits.Values;
	public Dictionary<int32, SkillConfig>.ValueEnumerator Skills => mSkills.Values;
	public Dictionary<int32, BuffConfig>.ValueEnumerator Buffs => mBuffs.Values;
	public Dictionary<int32, StageConfig>.ValueEnumerator Stages => mStages.Values;
	public Dictionary<int32, ItemConfig>.ValueEnumerator Items => mItems.Values;
	public Dictionary<int32, EquipConfig>.ValueEnumerator Equips => mEquips.Values;

	public StarLevelConfig GetStarLevel(int32 unitId, int32 starLevel)
	{
		for (let config in mStarLevels)
		{
			if (config.mUnitId == unitId && config.mStarLevel == starLevel)
				return config;
		}
		return null;
	}

	// --- Registration (for programmatic/test use) ---

	/// Register a unit config. Takes ownership of the object.
	public void RegisterUnit(UnitConfig config) { mUnits[config.mId] = config; }
	public void RegisterSkill(SkillConfig config) { mSkills[config.mId] = config; }
	public void RegisterBuff(BuffConfig config) { mBuffs[config.mId] = config; }
	public void RegisterStage(StageConfig config) { mStages[config.mId] = config; }
	public void RegisterItem(ItemConfig config) { mItems[config.mId] = config; }
	public void RegisterEquip(EquipConfig config) { mEquips[config.mId] = config; }
	public void RegisterShopItem(ShopItemConfig config) { mShopItems[config.mId] = config; }
	public void RegisterHeroLevel(HeroLevelConfig config) { mHeroLevels[config.mLevel] = config; }
	public void RegisterStarLevel(StarLevelConfig config) { mStarLevels.Add(config); }

	// --- Loading ---

	public Result<void> LoadAll(StringView basePath)
	{
		Try!(LoadConfigList<UnitConfig>(basePath, "units.xml", mUnits, scope (c) => c.mId));
		Try!(LoadConfigList<SkillConfig>(basePath, "skills.xml", mSkills, scope (c) => c.mId));
		Try!(LoadConfigList<BuffConfig>(basePath, "buffs.xml", mBuffs, scope (c) => c.mId));
		Try!(LoadConfigList<StageConfig>(basePath, "stages.xml", mStages, scope (c) => c.mId));
		Try!(LoadConfigList<ItemConfig>(basePath, "items.xml", mItems, scope (c) => c.mId));
		Try!(LoadConfigList<EquipConfig>(basePath, "equips.xml", mEquips, scope (c) => c.mId));
		Try!(LoadConfigList<ShopItemConfig>(basePath, "shop.xml", mShopItems, scope (c) => c.mId));
		Try!(LoadConfigList<HeroLevelConfig>(basePath, "hero_levels.xml", mHeroLevels, scope (c) => c.mLevel));
		Try!(LoadObjectList<StarLevelConfig>(basePath, "star_levels.xml", mStarLevels));
		return .Ok;
	}

	private Result<void> LoadConfigList<T>(StringView basePath, StringView fileName,
		Dictionary<int32, T> dict, delegate int32(T) getId)
		where T : ISerializable, class, new, delete
	{
		let fullPath = scope String();
		Path.InternalCombine(fullPath, basePath, fileName);

		let xmlText = scope String();
		if (File.ReadAllText(fullPath, xmlText) case .Err)
			return .Ok; // File doesn't exist yet — not an error

		let doc = scope XmlDocument();
		if (doc.Parse(xmlText) != .Ok)
			return .Err;

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		let list = scope List<T>();
		reader.ObjectList("Items", list);

		for (let item in list)
		{
			let id = getId(item);
			dict[id] = item;
		}
		list.Clear(); // Don't delete items — ownership transferred to dict

		return .Ok;
	}

	private Result<void> LoadObjectList<T>(StringView basePath, StringView fileName, List<T> list)
		where T : ISerializable, class, new, delete
	{
		let fullPath = scope String();
		Path.InternalCombine(fullPath, basePath, fileName);

		let xmlText = scope String();
		if (File.ReadAllText(fullPath, xmlText) case .Err)
			return .Ok;

		let doc = scope XmlDocument();
		if (doc.Parse(xmlText) != .Ok)
			return .Err;

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		reader.ObjectList("Items", list);
		return .Ok;
	}

	// --- Validation ---

	public void Validate()
	{
		// Check skill references in units
		for (let unit in mUnits.Values)
		{
			for (let skillId in unit.mSkillIds)
			{
				if (GetSkill(skillId) == null)
					Console.WriteLine($"[ConfigDB] Unit {unit.mId} references missing skill {skillId}");
			}
		}

		// Check buff references in skills
		for (let skill in mSkills.Values)
		{
			for (let effect in skill.mEffects)
			{
				if (effect.mType == .ApplyBuff && effect.mBuffId != 0 && GetBuff(effect.mBuffId) == null)
					Console.WriteLine($"[ConfigDB] Skill {skill.mId} references missing buff {effect.mBuffId}");
			}
		}

		// Check item references in stages
		for (let stage in mStages.Values)
		{
			for (let reward in stage.mRewards)
			{
				if (GetItem(reward.mItemId) == null)
					Console.WriteLine($"[ConfigDB] Stage {stage.mId} references missing item {reward.mItemId}");
			}
			for (let slot in stage.mEnemyFormation)
			{
				if (GetUnit(slot.mUnitId) == null)
					Console.WriteLine($"[ConfigDB] Stage {stage.mId} references missing unit {slot.mUnitId}");
			}
		}

		// Check item references in shop
		for (let shopItem in mShopItems.Values)
		{
			if (GetItem(shopItem.mItemId) == null)
				Console.WriteLine($"[ConfigDB] Shop item {shopItem.mId} references missing item {shopItem.mItemId}");
		}
	}
}
