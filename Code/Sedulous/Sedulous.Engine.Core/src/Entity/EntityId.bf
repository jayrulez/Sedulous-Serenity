using System;

namespace Sedulous.Engine.Core;

/// Unique identifier for an entity.
/// Uses a 64-bit value with generation counter to detect stale references.
struct EntityId : IEquatable<EntityId>, IHashable
{
	/// Invalid entity ID constant.
	public static readonly EntityId Invalid = .(0, 0);

	/// The index portion of the ID.
	public readonly uint32 Index;

	/// The generation counter (incremented when index is reused).
	public readonly uint32 Generation;

	public this(uint32 index, uint32 generation)
	{
		Index = index;
		Generation = generation;
	}

	/// Returns true if this is a valid entity ID.
	public bool IsValid => Index != 0 || Generation != 0;

	public bool Equals(EntityId other) => Index == other.Index && Generation == other.Generation;

	public int GetHashCode() => (int)(Index ^ (Generation << 16));

	public override void ToString(String str) => str.AppendF("Entity({}, {})", Index, Generation);

	public static bool operator ==(EntityId lhs, EntityId rhs) => lhs.Equals(rhs);
	public static bool operator !=(EntityId lhs, EntityId rhs) => !lhs.Equals(rhs);
}
