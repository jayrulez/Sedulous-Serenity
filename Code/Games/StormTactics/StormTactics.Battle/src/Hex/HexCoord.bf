namespace StormTactics.Battle;

using System;
using System.Collections;

/// Axial hex coordinate (q, r). Uses flat-top hex orientation.
/// The implicit third cube coordinate s = -q - r.
struct HexCoord : IHashable, IEquatable<HexCoord>
{
	public int32 Q;
	public int32 R;

	public int32 S => -Q - R;

	public this(int32 q, int32 r)
	{
		Q = q;
		R = r;
	}

	public static readonly HexCoord Zero = .(0, 0);

	// --- Hex directions (flat-top) ---
	// Direction 0 = East, going counter-clockwise

	public static readonly HexCoord[6] Directions = .(
		.(1, 0),   // E
		.(1, -1),  // NE
		.(0, -1),  // NW
		.(-1, 0),  // W
		.(-1, 1),  // SW
		.(0, 1)    // SE
	);

	public static HexCoord Direction(int dir) => Directions[((dir % 6) + 6) % 6];

	public HexCoord Neighbor(int dir) => this + Direction(dir);

	// --- Arithmetic ---

	public static HexCoord operator+(HexCoord a, HexCoord b) => .(a.Q + b.Q, a.R + b.R);
	public static HexCoord operator-(HexCoord a, HexCoord b) => .(a.Q - b.Q, a.R - b.R);
	public static HexCoord operator*(HexCoord h, int32 k) => .(h.Q * k, h.R * k);
	public static bool operator==(HexCoord a, HexCoord b) => a.Q == b.Q && a.R == b.R;
	public static bool operator!=(HexCoord a, HexCoord b) => !(a == b);

	// --- Distance ---

	/// Manhattan distance in cube coordinates.
	public int32 DistanceTo(HexCoord other)
	{
		let dq = Math.Abs(Q - other.Q);
		let dr = Math.Abs(R - other.R);
		let ds = Math.Abs(S - other.S);
		return (int32)((dq + dr + ds) / 2);
	}

	public static int32 Distance(HexCoord a, HexCoord b) => a.DistanceTo(b);

	// --- Neighbors ---

	/// Appends all 6 neighbors to the list.
	public void GetNeighbors(List<HexCoord> outList)
	{
		for (int i = 0; i < 6; i++)
			outList.Add(Neighbor(i));
	}

	// --- Ring & spiral ---

	/// Appends all hexes at exactly `radius` distance to the list.
	public void GetRing(int32 radius, List<HexCoord> outList)
	{
		if (radius <= 0)
		{
			outList.Add(this);
			return;
		}

		var current = this + Direction(4) * radius; // Start at SW corner
		for (int dir = 0; dir < 6; dir++)
		{
			for (int32 step = 0; step < radius; step++)
			{
				outList.Add(current);
				current = current.Neighbor(dir);
			}
		}
	}

	/// Appends all hexes within `radius` distance (inclusive) in spiral order.
	public void GetSpiral(int32 radius, List<HexCoord> outList)
	{
		outList.Add(this);
		for (int32 r = 1; r <= radius; r++)
			GetRing(r, outList);
	}

	// --- Line drawing ---

	/// Draws a line from this hex to `target`, appending all hexes along the way.
	/// Uses cube-coordinate linear interpolation with rounding.
	public void LineTo(HexCoord target, List<HexCoord> outList)
	{
		let dist = DistanceTo(target);
		if (dist == 0)
		{
			outList.Add(this);
			return;
		}

		for (int32 i = 0; i <= dist; i++)
		{
			let t = (float)i / (float)dist;
			outList.Add(CubeLerp(this, target, t));
		}
	}

	private static HexCoord CubeLerp(HexCoord a, HexCoord b, float t)
	{
		let fq = Lerp((float)a.Q, (float)b.Q, t);
		let fr = Lerp((float)a.R, (float)b.R, t);
		let fs = Lerp((float)a.S, (float)b.S, t);
		return CubeRound(fq, fr, fs);
	}

	private static float Lerp(float a, float b, float t) => a + (b - a) * t;

	private static HexCoord CubeRound(float fq, float fr, float fs)
	{
		var rq = (int32)Math.Round(fq);
		var rr = (int32)Math.Round(fr);
		var rs = (int32)Math.Round(fs);

		let dq = Math.Abs(fq - (float)rq);
		let dr = Math.Abs(fr - (float)rr);
		let ds = Math.Abs(fs - (float)rs);

		if (dq > dr && dq > ds)
			rq = -rr - rs;
		else if (dr > ds)
			rr = -rq - rs;
		// else rs = -rq - rr (implicit, we don't store s)

		return .(rq, rr);
	}

	// --- Offset coordinate conversion (even-r offset for flat-top) ---

	/// Convert axial (q, r) → offset column/row.
	/// Uses even-r: even rows are not shifted, odd rows shift right.
	public (int32 col, int32 row) ToOffset()
	{
		let col = Q + (R + (R & 1)) / 2;
		let row = R;
		return (col, row);
	}

	/// Convert offset column/row → axial (q, r).
	public static HexCoord FromOffset(int32 col, int32 row)
	{
		let q = col - (row + (row & 1)) / 2;
		let r = row;
		return .(q, r);
	}

	// --- World-space conversion ---

	/// Convert hex coordinate to world-space center position (flat-top).
	/// Returns (x, z) in world space. Y is up.
	public (float x, float z) ToWorld(float hexSize)
	{
		let x = hexSize * (3.0f / 2.0f * (float)Q);
		let z = hexSize * (Math.Sqrt(3.0f) * ((float)R + (float)Q / 2.0f));
		return (x, z);
	}

	/// Convert world-space position to the nearest hex coordinate (flat-top).
	public static HexCoord FromWorld(float worldX, float worldZ, float hexSize)
	{
		let fq = (2.0f / 3.0f * worldX) / hexSize;
		let fr = (-1.0f / 3.0f * worldX + Math.Sqrt(3.0f) / 3.0f * worldZ) / hexSize;
		return CubeRound(fq, fr, -fq - fr);
	}

	// --- IHashable / IEquatable ---

	public int GetHashCode()
	{
		return (int)(Q * 31 + R);
	}

	public bool Equals(HexCoord other)
	{
		return Q == other.Q && R == other.R;
	}

	public override void ToString(String strBuffer)
	{
		strBuffer.AppendF("({},{})", Q, R);
	}
}
