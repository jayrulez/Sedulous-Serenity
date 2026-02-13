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

	/// Create a fresh save with starter units: Footman (1), Archer (3), Priest (5).
	public void CreateNewSave()
	{
		delete mSaveData;
		mSaveData = new PlayerSaveData();

		// Starter roster
		int32[3] starterIds = .(1, 3, 5);
		for (let unitId in starterIds)
		{
			let unit = new OwnedUnitData();
			unit.mUnitId = unitId;
			unit.mStarLevel = 1;
			unit.mLevel = 1;
			mSaveData.mOwnedUnits.Add(unit);
		}

		// Default formation preset with starters
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
