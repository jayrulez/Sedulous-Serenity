namespace Sedulous.Render;

using System;

/// Handle to a proxy object in a pool.
/// Uses index + generation for safe access with recycled slots.
public struct RenderHandle : IHashable
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
public struct MeshRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct SkinnedMeshRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct LightRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct ParticleEmitterRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct CameraRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct SpriteRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct TrailEmitterRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct DecalRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct ReflectionProbeRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct TerrainRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct WaterRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct GrassRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}

public struct CurveDecalRenderHandle : IHashable
{
	public RenderHandle Handle;

	public static Self Invalid => .() { Handle = .Invalid };
	public bool IsValid => Handle.IsValid;

	public int GetHashCode() => Handle.GetHashCode();

	public static bool operator ==(Self lhs, Self rhs) => lhs.Handle == rhs.Handle;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Handle != rhs.Handle;
}
