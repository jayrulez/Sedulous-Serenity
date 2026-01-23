namespace Sedulous.Render;

using System;

/// Handle to a proxy object in a pool.
/// Uses index + generation for safe access with recycled slots.
public struct ProxyHandle : IHashable
{
	public uint32 Index;
	public uint32 Generation;

	public static Self Invalid = .() { Index = uint32.MaxValue, Generation = 0 };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode()
	{
		return (int)(Index ^ (Generation << 16));
	}

	public static bool operator ==(Self lhs, Self rhs)
	{
		return lhs.Index == rhs.Index && lhs.Generation == rhs.Generation;
	}

	public static bool operator !=(Self lhs, Self rhs)
	{
		return !(lhs == rhs);
	}
}

/// Typed handle for type safety.
public struct MeshProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct SkinnedMeshProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct LightProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct ParticleEmitterProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct CameraProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct SpriteProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct TrailEmitterProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}
