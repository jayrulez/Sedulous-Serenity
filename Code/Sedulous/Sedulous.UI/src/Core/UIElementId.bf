using System;

namespace Sedulous.UI;

/// Hash-based identifier for UI elements.
/// Uses FNV-1a hash for efficient string-to-ID conversion.
/// Similar to TBID in TurboBadger - enables fast lookups without string comparisons.
public struct UIElementId : IHashable, IEquatable<UIElementId>, IEquatable
{
	public const UIElementId Empty = .(0);

	private readonly uint32 mHash;

	/// Creates an ID from a pre-computed hash value.
	public this(uint32 hash)
	{
		mHash = hash;
	}

	/// Creates an ID by hashing a string.
	public this(StringView name)
	{
		mHash = ComputeHash(name);
	}

	/// The raw hash value.
	public uint32 Hash => mHash;

	/// Whether this ID is empty (hash == 0).
	public bool IsEmpty => mHash == 0;

	/// Computes FNV-1a hash of a string.
	/// FNV-1a is fast and has good distribution for short strings.
	public static uint32 ComputeHash(StringView str)
	{
		if (str.IsEmpty)
			return 0;

		// FNV-1a constants for 32-bit
		const uint32 FNV_PRIME = 0x01000193;
		const uint32 FNV_OFFSET = 0x811c9dc5;

		uint32 hash = FNV_OFFSET;
		for (let c in str)
		{
			hash ^= (uint32)c;
			hash *= FNV_PRIME;
		}
		return hash;
	}

	public int GetHashCode()
	{
		return (int)mHash;
	}

	public bool Equals(UIElementId other)
	{
		return mHash == other.mHash;
	}

	public bool Equals(Object other)
	{
		if (other is UIElementId)
			return Equals((UIElementId)other);
		return false;
	}

	public static bool operator ==(UIElementId lhs, UIElementId rhs)
	{
		return lhs.mHash == rhs.mHash;
	}

	public static bool operator !=(UIElementId lhs, UIElementId rhs)
	{
		return lhs.mHash != rhs.mHash;
	}

	/// Implicit conversion from string.
	public static implicit operator UIElementId(StringView name)
	{
		return .(name);
	}

	public override void ToString(String strBuffer)
	{
		strBuffer.AppendF("UIElementId(0x{0:X8})", mHash);
	}
}
