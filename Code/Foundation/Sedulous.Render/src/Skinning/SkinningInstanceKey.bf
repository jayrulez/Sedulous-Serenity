using System;
namespace Sedulous.Render;

/// Composite key for skinning instances that includes both world and mesh handle.
/// This is necessary because each RenderWorld has its own handle space.
struct SkinningInstanceKey : IHashable
{
	public RenderWorld World;
	public SkinnedMeshProxyHandle Handle;

	public int GetHashCode()
	{
		// Combine world identity hash with handle hash
		int worldHash = World != null ? (int)Internal.UnsafeCastToPtr(World) : 0;
		int handleHash = Handle.GetHashCode();
		return worldHash ^ (handleHash * 31);
	}

	public static bool operator==(Self lhs, Self rhs)
	{
		return lhs.World == rhs.World && lhs.Handle.Handle == rhs.Handle.Handle;
	}
}