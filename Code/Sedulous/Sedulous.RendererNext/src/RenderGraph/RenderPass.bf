namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;

/// Base class for render passes in the render graph.
abstract class RenderPass
{
	private String mName ~ delete _;
	private List<RenderGraphTextureHandle> mTextureReads = new .() ~ delete _;
	private List<RenderGraphTextureHandle> mTextureWrites = new .() ~ delete _;
	private List<RenderGraphBufferHandle> mBufferReads = new .() ~ delete _;
	private List<RenderGraphBufferHandle> mBufferWrites = new .() ~ delete _;

	/// Name of this render pass (for debugging).
	public StringView Name => mName;

	/// Index in the render graph's pass list.
	public int32 PassIndex { get; set; } = -1;

	/// Creates a render pass with the given name.
	protected this(StringView name)
	{
		mName = new .(name);
	}

	/// Declares a texture read dependency.
	protected void ReadTexture(RenderGraphTextureHandle handle)
	{
		if (handle.IsValid)
			mTextureReads.Add(handle);
	}

	/// Declares a texture write dependency.
	protected void WriteTexture(RenderGraphTextureHandle handle)
	{
		if (handle.IsValid)
			mTextureWrites.Add(handle);
	}

	/// Declares a buffer read dependency.
	protected void ReadBuffer(RenderGraphBufferHandle handle)
	{
		if (handle.IsValid)
			mBufferReads.Add(handle);
	}

	/// Declares a buffer write dependency.
	protected void WriteBuffer(RenderGraphBufferHandle handle)
	{
		if (handle.IsValid)
			mBufferWrites.Add(handle);
	}

	/// Gets texture read dependencies.
	public Span<RenderGraphTextureHandle> TextureReads => mTextureReads;

	/// Gets texture write dependencies.
	public Span<RenderGraphTextureHandle> TextureWrites => mTextureWrites;

	/// Gets buffer read dependencies.
	public Span<RenderGraphBufferHandle> BufferReads => mBufferReads;

	/// Gets buffer write dependencies.
	public Span<RenderGraphBufferHandle> BufferWrites => mBufferWrites;

	/// Clears all declared dependencies (called before Setup).
	public void ClearDependencies()
	{
		mTextureReads.Clear();
		mTextureWrites.Clear();
		mBufferReads.Clear();
		mBufferWrites.Clear();
	}

	/// Called during graph setup to declare resource dependencies.
	public abstract void Setup(RenderGraphBuilder builder);

	/// Called during graph execution to perform rendering.
	public abstract void Execute(RenderGraphContext context);
}

/// Context passed to render passes during execution.
class RenderGraphContext
{
	private Dictionary<uint32, RenderGraphResource> mResources;

	/// The device for creating resources.
	public IDevice Device { get; set; }

	/// The command encoder for recording commands.
	public ICommandEncoder CommandEncoder { get; set; }

	/// Current frame index (0 to MAX_FRAMES_IN_FLIGHT-1).
	public int32 FrameIndex { get; set; }

	/// Sets the resource map for resolution.
	public void SetResources(Dictionary<uint32, RenderGraphResource> resources)
	{
		mResources = resources;
	}

	/// Resolves a texture handle to the actual texture.
	public ITexture GetTexture(RenderGraphTextureHandle handle)
	{
		if (!handle.IsValid || mResources == null)
			return null;

		if (mResources.TryGetValue(handle.Handle.Index, let resource))
			return resource.Texture;

		return null;
	}

	/// Resolves a texture handle to a texture view.
	public ITextureView GetTextureView(RenderGraphTextureHandle handle)
	{
		if (!handle.IsValid || mResources == null)
			return null;

		if (mResources.TryGetValue(handle.Handle.Index, let resource))
			return resource.TextureView;

		return null;
	}

	/// Resolves a buffer handle to the actual buffer.
	public IBuffer GetBuffer(RenderGraphBufferHandle handle)
	{
		if (!handle.IsValid || mResources == null)
			return null;

		if (mResources.TryGetValue(handle.Handle.Index, let resource))
			return resource.Buffer;

		return null;
	}
}

/// Builder for declaring render graph resources and dependencies.
class RenderGraphBuilder
{
	private Dictionary<uint32, RenderGraphResource> mResources;
	private uint32 mNextResourceIndex = 0;
	private uint32 mVersion = 1;

	/// Sets the resource storage for this builder.
	public void SetResources(Dictionary<uint32, RenderGraphResource> resources)
	{
		mResources = resources;
	}

	/// Resets the builder for a new frame.
	public void Reset()
	{
		mNextResourceIndex = 0;
		mVersion++;
	}

	/// Creates a transient texture for this frame.
	public RenderGraphTextureHandle CreateTexture(StringView name, RenderGraphTextureDescriptor descriptor)
	{
		if (mResources == null)
			return .Invalid;

		let index = mNextResourceIndex++;
		let handle = RenderGraphHandle() { Index = index, Version = mVersion };

		let resource = new RenderGraphResource(name);
		resource.Handle = handle;
		resource.Type = .Texture;
		resource.Lifetime = .Transient;
		resource.TextureDesc = descriptor;

		mResources[index] = resource;

		return .() { Handle = handle };
	}

	/// Creates a transient texture for this frame.
	public RenderGraphTextureHandle CreateTexture(RenderGraphTextureDescriptor descriptor)
	{
		return CreateTexture("Transient", descriptor);
	}

	/// Creates a transient buffer for this frame.
	public RenderGraphBufferHandle CreateBuffer(StringView name, RenderGraphBufferDescriptor descriptor)
	{
		if (mResources == null)
			return .Invalid;

		let index = mNextResourceIndex++;
		let handle = RenderGraphHandle() { Index = index, Version = mVersion };

		let resource = new RenderGraphResource(name);
		resource.Handle = handle;
		resource.Type = .Buffer;
		resource.Lifetime = .Transient;
		resource.BufferDesc = descriptor;

		mResources[index] = resource;

		return .() { Handle = handle };
	}

	/// Creates a transient buffer for this frame.
	public RenderGraphBufferHandle CreateBuffer(RenderGraphBufferDescriptor descriptor)
	{
		return CreateBuffer("Transient", descriptor);
	}

	/// Imports an external texture into the graph.
	public RenderGraphTextureHandle ImportTexture(StringView name, ITexture texture, ITextureView view = null)
	{
		if (mResources == null || texture == null)
			return .Invalid;

		let index = mNextResourceIndex++;
		let handle = RenderGraphHandle() { Index = index, Version = mVersion };

		let resource = new RenderGraphResource(name);
		resource.Handle = handle;
		resource.Type = .Texture;
		resource.Lifetime = .Imported;
		resource.Texture = texture;
		resource.TextureView = view;

		mResources[index] = resource;

		return .() { Handle = handle };
	}

	/// Imports an external buffer into the graph.
	public RenderGraphBufferHandle ImportBuffer(StringView name, IBuffer buffer)
	{
		if (mResources == null || buffer == null)
			return .Invalid;

		let index = mNextResourceIndex++;
		let handle = RenderGraphHandle() { Index = index, Version = mVersion };

		let resource = new RenderGraphResource(name);
		resource.Handle = handle;
		resource.Type = .Buffer;
		resource.Lifetime = .Imported;
		resource.Buffer = buffer;

		mResources[index] = resource;

		return .() { Handle = handle };
	}
}
