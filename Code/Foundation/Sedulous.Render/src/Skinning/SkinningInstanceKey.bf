using System;
namespace Sedulous.Render;

/// Composite key for skinning instances that includes both a source identifier
/// and the mesh handle. SourceId scopes the handle space — renderables produced
/// by different RenderableList producers (different worlds, different editor
/// viewports, etc.) won't collide on handle indices.
struct SkinningInstanceKey : IHashable
{
	public uint32 SourceId;
	public SkinnedMeshRenderHandle Handle;

	public int GetHashCode()
	{
		// Combine source id hash with handle hash
		int handleHash = Handle.GetHashCode();
		return (int)SourceId ^ (handleHash * 31);
	}

	public static bool operator==(Self lhs, Self rhs)
	{
		return lhs.SourceId == rhs.SourceId && lhs.Handle.Handle == rhs.Handle.Handle;
	}
}
