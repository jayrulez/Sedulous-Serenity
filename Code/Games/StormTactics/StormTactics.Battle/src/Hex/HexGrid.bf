namespace StormTactics.Battle;

using System;
using System.Collections;
using StormTactics.Core;

/// A hex grid battlefield with configurable dimensions.
/// Uses offset coordinates (col, row) for storage, axial (HexCoord) for logic.
class HexGrid
{
	private int32 mColumns;
	private int32 mRows;
	private GridState[] mStates ~ delete _;
	private int32[] mOccupants ~ delete _;  // Unit index per cell (-1 = empty)

	public int32 Columns => mColumns;
	public int32 Rows => mRows;

	public this(int32 columns, int32 rows)
	{
		mColumns = columns;
		mRows = rows;
		let count = columns * rows;
		mStates = new GridState[count];
		mOccupants = new int32[count];

		for (int i = 0; i < count; i++)
		{
			mStates[i] = .Walkable;
			mOccupants[i] = -1;
		}
	}

	// --- Bounds & index ---

	public bool InBounds(int32 col, int32 row)
	{
		return col >= 0 && col < mColumns && row >= 0 && row < mRows;
	}

	public bool InBounds(HexCoord hex)
	{
		let (col, row) = hex.ToOffset();
		return InBounds(col, row);
	}

	private int Index(int32 col, int32 row) => row * mColumns + col;

	// --- State access ---

	public GridState GetState(int32 col, int32 row)
	{
		if (!InBounds(col, row)) return .Invalid;
		return mStates[Index(col, row)];
	}

	public GridState GetState(HexCoord hex)
	{
		let (col, row) = hex.ToOffset();
		return GetState(col, row);
	}

	public void SetState(int32 col, int32 row, GridState state)
	{
		if (!InBounds(col, row)) return;
		mStates[Index(col, row)] = state;
	}

	public void SetState(HexCoord hex, GridState state)
	{
		let (col, row) = hex.ToOffset();
		SetState(col, row, state);
	}

	// --- Occupant access ---

	public int32 GetOccupant(HexCoord hex)
	{
		let (col, row) = hex.ToOffset();
		if (!InBounds(col, row)) return -1;
		return mOccupants[Index(col, row)];
	}

	public void SetOccupant(HexCoord hex, int32 unitIndex)
	{
		let (col, row) = hex.ToOffset();
		if (!InBounds(col, row)) return;
		let idx = Index(col, row);

		// Debug: detect double-occupancy
		if (unitIndex >= 0 && mOccupants[idx] >= 0 && mOccupants[idx] != unitIndex)
		{
			Console.WriteLine("[GRID-COLLISION] Hex ({},{}) already has unit {}, trying to place unit {}!",
				hex.Q, hex.R, mOccupants[idx], unitIndex);
		}

		mOccupants[idx] = unitIndex;
		mStates[idx] = unitIndex >= 0 ? .Occupied : .Walkable;
	}

	public void ClearOccupant(HexCoord hex)
	{
		SetOccupant(hex, -1);
	}

	// --- Queries ---

	/// Is this cell walkable and unoccupied?
	public bool IsPassable(HexCoord hex)
	{
		return GetState(hex) == .Walkable;
	}

	/// Is this cell passable for a flying unit? (blocked terrain is still blocked, but occupied cells are passable)
	public bool IsPassableFlying(HexCoord hex)
	{
		let state = GetState(hex);
		return state == .Walkable || state == .Occupied;
	}

	/// Get all valid hex coords on the grid.
	public void GetAllHexes(List<HexCoord> outList)
	{
		for (int32 row = 0; row < mRows; row++)
			for (int32 col = 0; col < mColumns; col++)
				outList.Add(HexCoord.FromOffset(col, row));
	}

	/// Get all hexes within `range` steps of `center` that are on the grid.
	public void GetHexesInRange(HexCoord center, int32 range, List<HexCoord> outList)
	{
		for (int32 dq = -range; dq <= range; dq++)
		{
			let minR = Math.Max(-range, -dq - range);
			let maxR = Math.Min(range, -dq + range);
			for (int32 dr = (int32)minR; dr <= maxR; dr++)
			{
				let hex = HexCoord(center.Q + dq, center.R + dr);
				if (InBounds(hex))
					outList.Add(hex);
			}
		}
	}

	/// Get cells affected by an attack pattern from `attacker` toward `target`.
	public void GetAttackPatternCells(HexCoord attacker, HexCoord target, AttackPattern pattern, List<HexCoord> outList)
	{
		switch (pattern)
		{
		case .Point:
			if (InBounds(target))
				outList.Add(target);

		case .Line2:
			// Target + 1 hex behind target (away from attacker)
			if (InBounds(target))
				outList.Add(target);
			let dir2 = target - attacker;
			let behind1 = target + HexCoord((int32)Math.Sign(dir2.Q), (int32)Math.Sign(dir2.R));
			if (InBounds(behind1))
				outList.Add(behind1);

		case .Line3:
			// Target + 2 hexes behind target
			if (InBounds(target))
				outList.Add(target);
			let dir3 = target - attacker;
			let normDir = HexCoord((int32)Math.Sign(dir3.Q), (int32)Math.Sign(dir3.R));
			let b1 = target + normDir;
			let b2 = target + normDir * 2;
			if (InBounds(b1)) outList.Add(b1);
			if (InBounds(b2)) outList.Add(b2);

		case .AroundSelf3:
			// 3 nearest neighbors around self
			for (int i = 0; i < 6; i++)
			{
				let n = attacker.Neighbor(i);
				if (InBounds(n))
					outList.Add(n);
				if (outList.Count >= 3) break;
			}

		case .AroundSelfAll:
			// All 6 neighbors around self
			for (int i = 0; i < 6; i++)
			{
				let n = attacker.Neighbor(i);
				if (InBounds(n))
					outList.Add(n);
			}

		case .AroundTarget:
			// All 6 neighbors around target
			if (InBounds(target))
				outList.Add(target);
			for (int i = 0; i < 6; i++)
			{
				let n = target.Neighbor(i);
				if (InBounds(n))
					outList.Add(n);
			}

		case .AllEnemies:
			// Caller should pass all enemy hexes; just return target as placeholder
			// This is handled at a higher level by the battle system
			break;
		}
	}
}
