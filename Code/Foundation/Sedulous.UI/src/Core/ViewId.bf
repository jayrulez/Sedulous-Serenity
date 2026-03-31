namespace Sedulous.UI;

using System;
using System.Threading;

/// Unique identifier for a View instance.
/// Generated via an atomic counter to ensure uniqueness.
public struct ViewId : IHashable, IEquatable<ViewId>
{
	private static int sNextId = 1;

	public readonly int Id;

	private this(int id)
	{
		Id = id;
	}

	/// Generate a new unique ViewId.
	public static ViewId Generate()
	{
		let id = Interlocked.Increment(ref sNextId, .Relaxed) - 1;
		return .(id);
	}

	/// Invalid/unassigned ID.
	public static readonly ViewId Invalid = .(0);

	public bool IsValid => Id != 0;

	public int GetHashCode() => Id;

	public bool Equals(ViewId other) => Id == other.Id;

	public static bool operator ==(ViewId a, ViewId b) => a.Id == b.Id;
	public static bool operator !=(ViewId a, ViewId b) => a.Id != b.Id;

	public override void ToString(String strBuffer)
	{
		strBuffer.AppendF("ViewId({})", Id);
	}
}
