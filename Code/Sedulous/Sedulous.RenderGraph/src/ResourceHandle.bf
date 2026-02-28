using System;

namespace Sedulous.RenderGraph;

/// Opaque handle to a resource (texture or buffer) within the render graph.
///
/// Handles are versioned to track read-after-write dependencies. Each write
/// to a resource produces a new version. Passes declare dependencies on
/// specific versions to establish correct ordering.
///
public struct ResourceHandle : IEquatable<ResourceHandle>, IHashable
{
	/// Index into the render graph's resource array.
	public readonly uint16 Index;
	/// Version number tracking writes (incremented on each write).
	public readonly uint16 Version;

	/// An invalid handle (used as a sentinel / default value).
	public static readonly ResourceHandle Invalid = .(uint16.MaxValue, 0);

	public this(uint16 index, uint16 version)
	{
		Index = index;
		Version = version;
	}

	/// Whether this handle refers to a valid resource.
	public bool IsValid => Index != uint16.MaxValue;

	public bool Equals(ResourceHandle other)
	{
		return Index == other.Index && Version == other.Version;
	}

	public int GetHashCode()
	{
		return (int)Index << 16 | (int)Version;
	}

	public static bool operator==(ResourceHandle a, ResourceHandle b) => a.Equals(b);
	public static bool operator!=(ResourceHandle a, ResourceHandle b) => !a.Equals(b);
}
