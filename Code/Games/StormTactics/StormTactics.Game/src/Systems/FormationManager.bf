namespace StormTactics.Game;

using System;
using System.Collections;
using StormTactics.Core;
using StormTactics.Battle;

/// Manages formation presets: create, edit, activate, and convert to battle-ready format.
class FormationManager
{
	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;

		// Ensure all preset slots exist up to the maximum
		while (mSave.mFormationPresets.Count < BattleConstants.MAX_FORMATION_PRESETS)
		{
			let preset = new FormationPreset();
			let name = scope String();
			name.AppendF("Preset {}", mSave.mFormationPresets.Count + 1);
			preset.mName.Set(name);
			mSave.mFormationPresets.Add(preset);
		}
	}

	/// Get the currently active formation preset. Returns null if none.
	public FormationPreset GetActivePreset()
	{
		if (mSave.mFormationPresets.Count == 0) return null;
		let idx = Math.Clamp(mSave.mActiveFormationIndex, 0, (int32)mSave.mFormationPresets.Count - 1);
		return mSave.mFormationPresets[idx];
	}

	/// Set the active formation preset index.
	public void SetActivePreset(int32 index)
	{
		if (index >= 0 && index < (int32)mSave.mFormationPresets.Count)
			mSave.mActiveFormationIndex = index;
	}

	/// Get the number of formation presets.
	public int32 PresetCount => (int32)mSave.mFormationPresets.Count;

	/// Get a preset by index.
	public FormationPreset GetPreset(int32 index)
	{
		if (index >= 0 && index < (int32)mSave.mFormationPresets.Count)
			return mSave.mFormationPresets[index];
		return null;
	}

	/// Create a new empty formation preset. Returns false if at max limit.
	public bool CreatePreset(StringView name)
	{
		if (PresetCount >= BattleConstants.MAX_FORMATION_PRESETS)
			return false;

		let preset = new FormationPreset();
		preset.mName.Set(name);
		mSave.mFormationPresets.Add(preset);
		Console.WriteLine("[Formation] Created preset '{}'", name);
		return true;
	}

	/// Overwrite an existing preset's slots with the given formation slots.
	/// Copies data from the source slots (caller retains ownership of originals).
	public void OverwritePreset(int32 presetIndex, List<FormationSlot> slots)
	{
		let preset = GetPreset(presetIndex);
		if (preset == null) return;

		// Clear existing slots
		for (let slot in preset.mSlots)
			delete slot;
		preset.mSlots.Clear();

		// Copy new slots
		for (let src in slots)
		{
			let dst = new FormationUnitSlot();
			dst.mUnitId = src.mUnitId;
			dst.mGridX = src.mGridX;
			dst.mGridY = src.mGridY;
			preset.mSlots.Add(dst);
		}

		Console.WriteLine("[Formation] Overwritten preset {} with {} units", presetIndex, slots.Count);
	}

	/// Add a unit to the active formation at a grid position.
	/// Returns false if unit already in formation or position taken.
	public bool AddUnitToPreset(int32 presetIndex, int32 unitId, int32 gridX, int32 gridY)
	{
		let preset = GetPreset(presetIndex);
		if (preset == null) return false;

		// Check if unit already in this formation
		for (let slot in preset.mSlots)
		{
			if (slot.mUnitId == unitId) return false;
		}

		// Check if position is occupied
		for (let slot in preset.mSlots)
		{
			if (slot.mGridX == gridX && slot.mGridY == gridY) return false;
		}

		let slot = new FormationUnitSlot();
		slot.mUnitId = unitId;
		slot.mGridX = gridX;
		slot.mGridY = gridY;
		preset.mSlots.Add(slot);
		return true;
	}

	/// Remove a unit from a preset.
	public bool RemoveUnitFromPreset(int32 presetIndex, int32 unitId)
	{
		let preset = GetPreset(presetIndex);
		if (preset == null) return false;

		for (int i = 0; i < preset.mSlots.Count; i++)
		{
			if (preset.mSlots[i].mUnitId == unitId)
			{
				let removed = preset.mSlots[i];
				preset.mSlots.RemoveAt(i);
				delete removed;
				return true;
			}
		}
		return false;
	}

	/// Move a unit within a preset to a new grid position.
	public bool MoveUnitInPreset(int32 presetIndex, int32 unitId, int32 newGridX, int32 newGridY)
	{
		let preset = GetPreset(presetIndex);
		if (preset == null) return false;

		// Check position not occupied by another unit
		for (let slot in preset.mSlots)
		{
			if (slot.mUnitId != unitId && slot.mGridX == newGridX && slot.mGridY == newGridY)
				return false;
		}

		for (let slot in preset.mSlots)
		{
			if (slot.mUnitId == unitId)
			{
				slot.mGridX = newGridX;
				slot.mGridY = newGridY;
				return true;
			}
		}
		return false;
	}

	/// Check if a unit is in a preset.
	public bool IsUnitInPreset(int32 presetIndex, int32 unitId)
	{
		let preset = GetPreset(presetIndex);
		if (preset == null) return false;

		for (let slot in preset.mSlots)
			if (slot.mUnitId == unitId) return true;
		return false;
	}

	/// Clear all units from a preset.
	public void ClearPreset(int32 presetIndex)
	{
		let preset = GetPreset(presetIndex);
		if (preset == null) return;

		for (let slot in preset.mSlots)
			delete slot;
		preset.mSlots.Clear();
	}
}
