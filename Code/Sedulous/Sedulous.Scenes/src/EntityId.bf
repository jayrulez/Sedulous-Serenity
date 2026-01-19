namespace Sedulous.Scenes;

using System;

/// Unique identifier for an entity using index + generation scheme for safe ID reuse.
/// When an entity is destroyed, its slot can be reused but with an incremented generation,
/// allowing detection of stale handles.
public struct EntityId : IEquatable<EntityId>, IHashable
{
	/// The index portion of the ID (slot in entity storage).
	public readonly uint32 Index;

	/// The generation counter (incremented each time the index is reused).
	public readonly uint32 Generation;

	/// Invalid entity ID constant.
	public static readonly EntityId Invalid = .(uint32.MaxValue, 0);

	/// Creates a new entity ID.
	public this(uint32 index, uint32 generation)
	{
		Index = index;
		Generation = generation;
	}

	/// Returns true if this is a potentially valid entity ID (index is not MaxValue).
	/// Note: This does not guarantee the entity still exists - use Scene.IsValid() for that.
	public bool IsValid => Index != uint32.MaxValue;

	/// Checks equality with another entity ID.
	public bool Equals(EntityId other)
	{
		return Index == other.Index && Generation == other.Generation;
	}

	/// Gets a hash code for use in dictionaries and hash sets.
	public int GetHashCode()
	{
		return (int)(Index ^ (Generation << 16));
	}

	/// Formats the entity ID as a string.
	public override void ToString(String str)
	{
		str.AppendF("Entity({}, gen={})", Index, Generation);
	}

	public static bool operator ==(EntityId lhs, EntityId rhs)
	{
		return lhs.Equals(rhs);
	}

	public static bool operator !=(EntityId lhs, EntityId rhs)
	{
		return !lhs.Equals(rhs);
	}
}
