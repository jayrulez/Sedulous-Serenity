namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;

/// Type of render graph resource.
enum RenderGraphResourceType
{
	Texture,
	Buffer
}

/// Lifetime of a render graph resource.
enum RenderGraphResourceLifetime
{
	/// Resource is created and destroyed within the frame (transient).
	Transient,
	/// Resource is imported from outside the graph (external).
	Imported
}

/// Tracks a resource in the render graph.
class RenderGraphResource
{
	public RenderGraphHandle Handle;
	public RenderGraphResourceType Type;
	public RenderGraphResourceLifetime Lifetime;
	public String Name ~ delete _;

	// For textures
	public RenderGraphTextureDescriptor TextureDesc;
	public ITexture Texture;
	public ITextureView TextureView;

	// For buffers
	public RenderGraphBufferDescriptor BufferDesc;
	public IBuffer Buffer;

	// Lifetime tracking
	public int32 FirstUsePass = -1;
	public int32 LastUsePass = -1;
	public List<int32> ReaderPasses = new .() ~ delete _;
	public List<int32> WriterPasses = new .() ~ delete _;

	public this(StringView name)
	{
		Name = new .(name);
	}

	/// Marks this resource as read by a pass.
	public void AddReader(int32 passIndex)
	{
		if (!ReaderPasses.Contains(passIndex))
			ReaderPasses.Add(passIndex);
		UpdateLifetime(passIndex);
	}

	/// Marks this resource as written by a pass.
	public void AddWriter(int32 passIndex)
	{
		if (!WriterPasses.Contains(passIndex))
			WriterPasses.Add(passIndex);
		UpdateLifetime(passIndex);
	}

	private void UpdateLifetime(int32 passIndex)
	{
		if (FirstUsePass < 0 || passIndex < FirstUsePass)
			FirstUsePass = passIndex;
		if (passIndex > LastUsePass)
			LastUsePass = passIndex;
	}

	/// Returns true if this resource is alive at the given pass.
	public bool IsAliveAt(int32 passIndex)
	{
		return passIndex >= FirstUsePass && passIndex <= LastUsePass;
	}
}

/// Dependency information for a render pass.
struct PassDependency
{
	public int32 PassIndex;
	public RenderGraphHandle ResourceHandle;
	public bool IsWrite;
}

/// Compiled render graph with resolved dependencies.
class CompiledRenderGraph
{
	public List<int32> ExecutionOrder = new .() ~ delete _;
	public List<RenderGraphResource> Resources = new .() ~ delete _;
	public Dictionary<int32, List<PassDependency>> PassDependencies = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	/// Gets the resources that need to be allocated before a pass.
	public void GetResourcesNeededBefore(int32 passIndex, List<RenderGraphResource> outResources)
	{
		for (let resource in Resources)
		{
			if (resource.FirstUsePass == passIndex && resource.Lifetime == .Transient)
				outResources.Add(resource);
		}
	}

	/// Gets the resources that can be released after a pass.
	public void GetResourcesReleasedAfter(int32 passIndex, List<RenderGraphResource> outResources)
	{
		for (let resource in Resources)
		{
			if (resource.LastUsePass == passIndex && resource.Lifetime == .Transient)
				outResources.Add(resource);
		}
	}
}
