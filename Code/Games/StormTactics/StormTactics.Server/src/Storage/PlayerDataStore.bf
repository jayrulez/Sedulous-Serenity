namespace StormTactics.Server;

using System;
using System.IO;
using Sedulous.Serialization;
using Sedulous.Serialization.Xml;
using Sedulous.Xml;
using StormTactics.Core;

/// Handles per-player save data persistence on the server.
/// Each player has a separate XML file: {dataDir}/players/{playerId}.xml
class PlayerDataStore
{
	private String mPlayersDir = new .() ~ delete _;

	/// Initialize with the server data directory.
	public void Initialize(StringView dataDir)
	{
		Path.InternalCombine(mPlayersDir, dataDir, "players");
		Directory.CreateDirectory(mPlayersDir);
	}

	/// Load a player's save data from disk. Returns null if no file exists.
	public PlayerSaveData LoadPlayerData(StringView playerId)
	{
		let path = scope String();
		GetPlayerPath(playerId, path);

		let xmlText = scope String();
		if (File.ReadAllText(path, xmlText) case .Err)
			return null;

		let doc = scope XmlDocument();
		if (doc.Parse(xmlText) != .Ok)
		{
			Console.WriteLine("[DataStore] ERROR: Failed to parse player file for {}", playerId);
			return null;
		}

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		PlayerSaveData data = null;
		reader.Object("PlayerData", ref data);
		return data;
	}

	/// Save a player's data to disk.
	public Result<void> SavePlayerData(StringView playerId, PlayerSaveData data)
	{
		let path = scope String();
		GetPlayerPath(playerId, path);

		let xml = scope String();
		SerializeToXml(data, xml);

		if (File.WriteAllText(path, xml) case .Err)
		{
			Console.WriteLine("[DataStore] ERROR: Failed to write player file for {}", playerId);
			return .Err;
		}

		Console.WriteLine("[DataStore] Saved player {}", playerId);
		return .Ok;
	}

	/// Create a new player with generous starter data.
	/// Same defaults as SaveManager.CreateNewSave().
	public PlayerSaveData CreateNewPlayer(StringView playerId)
	{
		let data = new PlayerSaveData();

		// Generous starting resources
		data.mHeroLevel = 5;
		data.mGold = 50000;
		data.mGems = 10000;
		data.mStamina = 200;

		// Starter roster: 5 units at level 5, star 2
		int32[5] starterIds = .(1, 2, 3, 4, 5);
		for (let unitId in starterIds)
		{
			let unit = new OwnedUnitData();
			unit.mUnitId = unitId;
			unit.mStarLevel = 2;
			unit.mLevel = 5;
			data.mOwnedUnits.Add(unit);
		}

		// Starting equipment
		AddEquip(data, 301);
		AddEquip(data, 301);
		AddEquip(data, 302);
		AddEquip(data, 302);
		AddEquip(data, 303);
		AddEquip(data, 304);

		// Starting inventory
		AddItem(data, 1003, 50);
		AddItem(data, 1004, 30);
		AddItem(data, 1005, 20);
		AddItem(data, 1006, 30);
		AddItem(data, 1007, 30);
		AddItem(data, 1008, 30);
		AddItem(data, 1009, 20);
		AddItem(data, 1010, 10);
		AddItem(data, 1012, 50);

		// Default formation preset
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
		data.mFormationPresets.Add(preset);
		data.mActiveFormationIndex = 0;

		// Save to disk
		let path = scope String();
		GetPlayerPath(playerId, path);
		let xml = scope String();
		SerializeToXml(data, xml);
		File.WriteAllText(path, xml);

		Console.WriteLine("[DataStore] Created new player {}", playerId);
		return data;
	}

	/// Serialize PlayerSaveData to XML string.
	public static void SerializeToXml(PlayerSaveData data, String outXml)
	{
		let writer = XmlSerializer.CreateWriter();
		defer delete writer;
		var dataRef = data;
		writer.Object("PlayerData", ref dataRef);
		writer.GetOutput(outXml);
	}

	/// Deserialize PlayerSaveData from XML string.
	public static PlayerSaveData DeserializeFromXml(StringView xml)
	{
		let doc = scope XmlDocument();
		if (doc.Parse(xml) != .Ok)
			return null;

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		PlayerSaveData data = null;
		reader.Object("PlayerData", ref data);
		return data;
	}

	private void GetPlayerPath(StringView playerId, String outPath)
	{
		Path.InternalCombine(outPath, mPlayersDir, scope $"{playerId}.xml");
	}

	private static void AddEquip(PlayerSaveData data, int32 equipId)
	{
		let equip = new OwnedEquipData();
		equip.mInstanceId = data.mNextEquipInstanceId++;
		equip.mEquipId = equipId;
		data.mOwnedEquips.Add(equip);
	}

	private static void AddItem(PlayerSaveData data, int32 itemId, int32 quantity)
	{
		let slot = new InventorySlot();
		slot.mItemId = itemId;
		slot.mQuantity = quantity;
		data.mInventory.Add(slot);
	}
}
