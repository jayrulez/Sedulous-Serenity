namespace Sedulous.RendererNext;

using System;

/// Handle to a resource in the render graph.
/// Handles are lightweight identifiers that get resolved to actual resources during execution.
struct RenderGraphHandle : IEquatable<RenderGraphHandle>, IHashable
{
	public uint32 Index;
	public uint32 Version;

	public static Self Invalid => .() { Index = uint32.MaxValue, Version = 0 };

	public bool IsValid => Index != uint32.MaxValue;

	public bool Equals(Self other) => Index == other.Index && Version == other.Version;
	public int GetHashCode() => (int)(Index ^ (Version << 16));

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}

/// Handle to a texture resource in the render graph.
struct RenderGraphTextureHandle : IEquatable<RenderGraphTextureHandle>, IHashable
{
	public RenderGraphHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };

	public bool IsValid => Handle.IsValid;

	public bool Equals(Self other) => Handle.Equals(other.Handle);
	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}

/// Handle to a buffer resource in the render graph.
struct RenderGraphBufferHandle : IEquatable<RenderGraphBufferHandle>, IHashable
{
	public RenderGraphHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };

	public bool IsValid => Handle.IsValid;

	public bool Equals(Self other) => Handle.Equals(other.Handle);
	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}
