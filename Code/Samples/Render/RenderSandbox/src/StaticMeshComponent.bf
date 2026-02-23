namespace RenderSandbox;

using System;
using Sedulous.Mathematics;
using Sedulous.Render;

/// Component for rendering a static (non-animated) mesh.
/// This is a simple sample component - a real ECS would have proper interfaces.
public class StaticMeshComponent
{
	/// Handle to the mesh proxy in the render world.
	public MeshProxyHandle MeshProxy;

	/// Handle to the GPU mesh in the resource manager.
	public GPUMeshHandle GPUMesh;

	/// World transform of this mesh.
	public Matrix Transform = .Identity;

	/// Whether this component is visible.
	public bool Visible = true;

	/// Material index (for multi-material support).
	public int32 MaterialIndex = 0;

	public this()
	{
	}

	public this(MeshProxyHandle meshProxy, GPUMeshHandle gpuMesh)
	{
		MeshProxy = meshProxy;
		GPUMesh = gpuMesh;
	}

	/// Updates the mesh proxy transform in the render world.
	public void UpdateTransform(RenderWorld world)
	{
		if (let proxy = world.GetMesh(MeshProxy))
		{
			proxy.WorldMatrix = Transform;
			// Set visibility via Flags
			if (Visible)
				proxy.Flags |= .Visible;
			else
				proxy.Flags &= ~.Visible;
		}
	}
}
