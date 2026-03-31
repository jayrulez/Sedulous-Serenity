using Sedulous.RHI;
namespace Sedulous.Render;

/// Per-mesh skinning data.
public class SkinningInstance
{
	/// Skinning parameters uniform buffer.
	public IBuffer ParamsBuffer;

	/// Handle to the bone buffer (not owned, from GPUResourceManager).
	public GPUBoneBufferHandle BoneBufferHandle;

	/// Reference to source vertex buffer (not owned, from GPUMesh).
	public IBuffer SourceVertexBuffer;

	/// Skinned vertex output buffer (owned).
	public IBuffer SkinnedVertexBuffer;

	/// Bind group for compute dispatch.
	public IBindGroup BindGroup;

	/// Number of vertices in the mesh.
	public int32 VertexCount;

	/// Number of bones in the skeleton.
	public int32 BoneCount;

	public void Destroy(IDevice device)
	{
		device.DestroyBuffer(ref ParamsBuffer);
		device.DestroyBuffer(ref SkinnedVertexBuffer);
		device.DestroyBindGroup(ref BindGroup);
	}
}