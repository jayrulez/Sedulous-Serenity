namespace Sedulous.Renderer;

using System;

/// Callback for iterating over active proxies.
public delegate void ProxyCallback<T>(ProxyHandle handle, ref T proxy) where T : struct;

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

/// Typed handle for static mesh proxies.
public struct StaticMeshProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

/// Typed handle for light proxies.
public struct LightProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

/// Typed handle for camera proxies.
public struct CameraProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

/// Typed handle for skinned mesh proxies.
public struct SkinnedMeshProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

/// Typed handle for reflection probe proxies.
public struct ReflectionProbeProxyHandle : IHashable
{
	public ProxyHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}
