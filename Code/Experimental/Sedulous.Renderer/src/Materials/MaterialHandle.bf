namespace Sedulous.Renderer;

using System;

/// Handle to a MaterialDefinition.
public struct MaterialDefHandle : IHashable
{
	public uint32 Index;
	public uint32 Generation;

	public static Self Invalid = .() { Index = uint32.MaxValue, Generation = 0 };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)(Index ^ (Generation << 16));

	public static bool operator ==(Self lhs, Self rhs) => lhs.Index == rhs.Index && lhs.Generation == rhs.Generation;
	public static bool operator !=(Self lhs, Self rhs) => !(lhs == rhs);
}

/// Handle to a MaterialInstance.
public struct MaterialInstanceHandle : IHashable
{
	public uint32 Index;
	public uint32 Generation;

	public static Self Invalid = .() { Index = uint32.MaxValue, Generation = 0 };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)(Index ^ (Generation << 16));

	public static bool operator ==(Self lhs, Self rhs) => lhs.Index == rhs.Index && lhs.Generation == rhs.Generation;
	public static bool operator !=(Self lhs, Self rhs) => !(lhs == rhs);
}
