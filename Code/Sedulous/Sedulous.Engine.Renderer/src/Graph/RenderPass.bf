namespace Sedulous.Engine.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Type of render pass.
enum PassType
{
	/// Graphics pass with render targets.
	Graphics,
	/// Compute pass.
	Compute,
	/// Transfer/copy pass.
	Transfer
}

/// How a pass accesses a resource.
enum ResourceAccess
{
	/// Read-only access.
	Read,
	/// Write-only access.
	Write,
	/// Read-write access.
	ReadWrite
}

/// Describes a resource dependency for a pass.
struct ResourceDependency
{
	public ResourceHandle Handle;
	public ResourceAccess Access;
	public TextureLayout RequiredLayout;

	public this(ResourceHandle handle, ResourceAccess access, TextureLayout layout = .General)
	{
		Handle = handle;
		Access = access;
		RequiredLayout = layout;
	}
}

/// Describes a color attachment for a graphics pass.
struct PassColorAttachment
{
	public ResourceHandle Target;
	public LoadOp LoadOp;
	public StoreOp StoreOp;
	public Color ClearColor;

	public this(ResourceHandle target, LoadOp load = .Clear, StoreOp store = .Store)
	{
		Target = target;
		LoadOp = load;
		StoreOp = store;
		ClearColor = .(0, 0, 0, 1);
	}
}

/// Describes a depth attachment for a graphics pass.
struct PassDepthAttachment
{
	public ResourceHandle Target;
	public LoadOp DepthLoadOp;
	public StoreOp DepthStoreOp;
	public LoadOp StencilLoadOp;
	public StoreOp StencilStoreOp;
	public float ClearDepth;
	public uint8 ClearStencil;

	public this(ResourceHandle target, LoadOp depthLoad = .Clear, StoreOp depthStore = .Store)
	{
		Target = target;
		DepthLoadOp = depthLoad;
		DepthStoreOp = depthStore;
		StencilLoadOp = .Clear;
		StencilStoreOp = .Store;
		ClearDepth = 0.0f; // Reverse-Z: 0 = far
		ClearStencil = 0;
	}
}

/// Delegate type for pass execution.
delegate void PassExecuteDelegate(PassExecuteContext context);

/// Context passed to pass execution callbacks.
struct PassExecuteContext
{
	public RenderGraph Graph;
	public IDevice Device;
	public ICommandEncoder Encoder;
	public IRenderPassEncoder RenderPass;
	public IComputePassEncoder ComputePass;
	public uint32 FrameIndex;
	public float DeltaTime;
	public float TotalTime;

	/// Gets the actual texture for a resource handle.
	public ITexture GetTexture(ResourceHandle handle)
	{
		return Graph.[Friend]GetResourceTexture(handle);
	}

	/// Gets the actual texture view for a resource handle.
	public ITextureView GetTextureView(ResourceHandle handle)
	{
		return Graph.[Friend]GetResourceTextureView(handle);
	}

	/// Gets the actual buffer for a resource handle.
	public IBuffer GetBuffer(ResourceHandle handle)
	{
		return Graph.[Friend]GetResourceBuffer(handle);
	}
}

/// Represents a single pass in the render graph.
class RenderPass
{
	/// Pass name for debugging.
	public String Name ~ delete _;

	/// Type of pass.
	public PassType Type;

	/// Pass index in the graph (set during compilation).
	public uint32 Index;

	/// Resources this pass reads from.
	public List<ResourceDependency> Reads = new .() ~ delete _;

	/// Resources this pass writes to.
	public List<ResourceDependency> Writes = new .() ~ delete _;

	/// Color attachments for graphics passes.
	public List<PassColorAttachment> ColorAttachments = new .() ~ delete _;

	/// Depth attachment for graphics passes.
	public PassDepthAttachment? DepthAttachment;

	/// Execution callback.
	public PassExecuteDelegate Execute ~ delete _;

	/// Barriers to insert before this pass.
	public List<TextureBarrier> PreBarriers = new .() ~ delete _;

	public this(StringView name, PassType type)
	{
		Name = new String(name);
		Type = type;
	}
}

/// Describes a texture barrier to insert.
struct TextureBarrier
{
	public ResourceHandle Handle;
	public TextureLayout OldLayout;
	public TextureLayout NewLayout;
}
