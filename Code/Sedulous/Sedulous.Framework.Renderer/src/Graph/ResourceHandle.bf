namespace Sedulous.Framework.Renderer;

using System;

/// Type of resource in the render graph.
enum ResourceType
{
	Texture,
	Buffer
}

/// Handle to a resource in the render graph.
/// This is a lightweight value type that references a resource by index.
struct ResourceHandle : IEquatable<ResourceHandle>, IHashable
{
	public const Self Invalid = .((uint32)-1, .Texture);

	private uint32 mIndex;
	private ResourceType mType;

	public uint32 Index => mIndex;
	public ResourceType Type => mType;
	public bool IsValid => mIndex != (uint32)-1;

	public this(uint32 index, ResourceType type)
	{
		mIndex = index;
		mType = type;
	}

	public bool Equals(ResourceHandle other)
	{
		return mIndex == other.mIndex && mType == other.mType;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ ((uint32)mType << 24));
	}

	public static bool operator ==(ResourceHandle lhs, ResourceHandle rhs)
	{
		return lhs.Equals(rhs);
	}

	public static bool operator !=(ResourceHandle lhs, ResourceHandle rhs)
	{
		return !lhs.Equals(rhs);
	}
}
