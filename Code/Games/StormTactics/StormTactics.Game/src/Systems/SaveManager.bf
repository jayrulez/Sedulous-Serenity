namespace StormTactics.Game;

using System;
using System.IO;
using Sedulous.Serialization;
using Sedulous.Serialization.Xml;
using Sedulous.Xml;
using StormTactics.Core;

/// Handles saving and loading PlayerSaveData to/from XML.
class SaveManager
{
	private String mSavePath = new .() ~ delete _;
	private PlayerSaveData mSaveData ~ delete _;

	public PlayerSaveData SaveData => mSaveData;

	/// Initialize save manager with the base asset directory.
	/// Save file goes to {basePath}/StormTactics/save/player_save.xml
	public void Initialize(StringView basePath)
	{
		Path.InternalCombine(mSavePath, basePath, "StormTactics/save/player_save.xml");

		if (Load() case .Err)
		{
			Console.WriteLine("[SaveManager] No existing save — creating new game");
			CreateNewSave();
		}
		else
		{
			Console.WriteLine("[SaveManager] Save loaded successfully");
		}
	}

	/// Create a fresh save with generous starting resources for testing.
	public void CreateNewSave()
	{
		delete mSaveData;
		mSaveData = new PlayerSaveData();

		// Generous starting resources
		mSaveData.mHeroLevel = 5;
		mSaveData.mGold = 50000;
		mSaveData.mGems = 10000;
		mSaveData.mStamina = 200;

		// Starter roster: 5 units at level 5, star 2
		int32[5] starterIds = .(1, 2, 3, 4, 5); // Footman, Knight, Archer, Wizard, Priest
		for (let unitId in starterIds)
		{
			let unit = new OwnedUnitData();
			unit.mUnitId = unitId;
			unit.mStarLevel = 2;
			unit.mLevel = 5;
			mSaveData.mOwnedUnits.Add(unit);
		}

		// Starting equipment
		AddStarterEquip(301); // Iron Sword
		AddStarterEquip(301); // Iron Sword (second)
		AddStarterEquip(302); // Steel Shield
		AddStarterEquip(302); // Steel Shield (second)
		AddStarterEquip(303); // Speed Ring
		AddStarterEquip(304); // War Hammer

		// Starting inventory
		AddStarterItem(1003, 50);   // Iron Ore
		AddStarterItem(1004, 30);   // Magic Crystal
		AddStarterItem(1005, 20);   // Stamina Potion
		AddStarterItem(1006, 30);   // Footman Shard
		AddStarterItem(1007, 30);   // Knight Shard
		AddStarterItem(1008, 30);   // Wizard Shard
		AddStarterItem(1009, 20);   // EXP Potion (Small)
		AddStarterItem(1010, 10);   // EXP Potion (Large)
		AddStarterItem(1012, 50);   // Enhancement Stone

		// Default formation preset with 5 starters
		let preset = new FormationPreset();
		preset.mName.Set("Default");

		int32 idx = 0;
		for (let unitId in starterIds)
		{
			let slot = new FormationUnitSlot();
			slot.mUnitId = unitId;
			slot.mGridX = (int32)(idx / 3);
			slot.mGridY = (int32)(idx % 3);
			preset.mSlots.Add(slot);
			idx++;
		}
		mSaveData.mFormationPresets.Add(preset);
		mSaveData.mActiveFormationIndex = 0;
	}

	private void AddStarterEquip(int32 equipId)
	{
		let equip = new OwnedEquipData();
		equip.mInstanceId = mSaveData.mNextEquipInstanceId++;
		equip.mEquipId = equipId;
		mSaveData.mOwnedEquips.Add(equip);
	}

	private void AddStarterItem(int32 itemId, int32 quantity)
	{
		let slot = new InventorySlot();
		slot.mItemId = itemId;
		slot.mQuantity = quantity;
		mSaveData.mInventory.Add(slot);
	}

	/// Save current data to disk.
	public Result<void> Save()
	{
		if (mSaveData == null)
			return .Err;

		// Ensure directory exists
		let dir = scope String();
		Path.GetDirectoryPath(mSavePath, dir);
		if (!dir.IsEmpty)
			Directory.CreateDirectory(dir);

		let writer = XmlSerializer.CreateWriter();
		defer delete writer;

		writer.Object("PlayerData", ref mSaveData);

		let output = scope String();
		writer.GetOutput(output);

		if (File.WriteAllText(mSavePath, output) case .Err)
		{
			Console.WriteLine("[SaveManager] ERROR: Failed to write save to {}", mSavePath);
			return .Err;
		}

		Console.WriteLine("[SaveManager] Save written to {}", mSavePath);
		return .Ok;
	}

	/// Load save data from disk.
	public Result<void> Load()
	{
		let xmlText = scope String();
		if (File.ReadAllText(mSavePath, xmlText) case .Err)
			return .Err;

		let doc = scope XmlDocument();
		if (doc.Parse(xmlText) != .Ok)
			return .Err;

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		delete mSaveData;
		mSaveData = null;
		reader.Object("PlayerData", ref mSaveData);

		return .Ok;
	}
}
