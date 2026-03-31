namespace Sedulous.RenderGraph;

using System;
using System.Collections;
using Sedulous.RHI;

/// Per-pass builder API.
/// Provided to each pass's setup callback to declare resource accesses and set the execute callback.
class RenderGraphBuilder
{
	private RenderGraph mGraph;
	private RenderGraphPass mPass;

	public this(RenderGraph graph, RenderGraphPass pass)
	{
		mGraph = graph;
		mPass = pass;
	}

	/// The pass being built. Use this to capture a reference for the execute callback.
	public RenderGraphPass Pass => mPass;

	// =========================================================================
	// Transient resource creation
	// =========================================================================

	/// Creates a transient texture that lives only within this frame.
	/// The resource is not implicitly accessed — you must declare reads/writes separately.
	public RGTexture CreateTexture(RGTextureDesc desc)
	{
		let resource = mGraph.[Friend]CreateTransientTexture(desc);
		resource.WriterPass = mPass.Index;
		return resource.AsTexture();
	}

	/// Creates a transient buffer that lives only within this frame.
	/// The resource is not implicitly accessed — you must declare reads/writes separately.
	public RGBuffer CreateBuffer(RGBufferDesc desc)
	{
		let resource = mGraph.[Friend]CreateTransientBuffer(desc);
		resource.WriterPass = mPass.Index;
		return resource.AsBuffer();
	}

	// =========================================================================
	// Read access declarations
	// =========================================================================

	/// Declares that this pass reads a texture as a sampled image in the given shader stages.
	public void ReadTexture(RGTexture tex, ShaderStage stages)
	{
		mPass.Accesses.Add(.()
		{
			Resource = tex.Resource,
			AccessType = .ReadTexture,
			Stages = stages,
			Slot = 0
		});
	}

	/// Declares that this pass reads a buffer as a uniform buffer.
	public void ReadUniformBuffer(RGBuffer buf, ShaderStage stages)
	{
		mPass.Accesses.Add(.()
		{
			Resource = buf.Resource,
			AccessType = .ReadUniformBuffer,
			Stages = stages,
			Slot = 0
		});
	}

	/// Declares that this pass reads a buffer as a read-only storage buffer.
	public void ReadStorageBuffer(RGBuffer buf, ShaderStage stages)
	{
		mPass.Accesses.Add(.()
		{
			Resource = buf.Resource,
			AccessType = .ReadStorageBuffer,
			Stages = stages,
			Slot = 0
		});
	}

	/// Declares that this pass reads the depth/stencil attachment (read-only depth test).
	public void ReadDepthStencil(RGTexture tex)
	{
		mPass.Accesses.Add(.()
		{
			Resource = tex.Resource,
			AccessType = .ReadDepthStencil,
			Stages = .Fragment,
			Slot = 0
		});
		mPass.DepthStencil = .()
		{
			Texture = tex,
			DepthLoadOp = .Load,
			DepthStoreOp = .Store,
			DepthClearValue = 1.0f,
			DepthReadOnly = true,
			StencilLoadOp = .DontCare,
			StencilStoreOp = .DontCare,
			StencilClearValue = 0,
			StencilReadOnly = true
		};
	}

	/// Declares that this pass reads a texture as a copy source.
	public void ReadCopySrc(RGTexture tex)
	{
		mPass.Accesses.Add(.()
		{
			Resource = tex.Resource,
			AccessType = .ReadCopySrc,
			Stages = .None,
			Slot = 0
		});
	}

	/// Declares that this pass reads a buffer as a copy source.
	public void ReadCopySrc(RGBuffer buf)
	{
		mPass.Accesses.Add(.()
		{
			Resource = buf.Resource,
			AccessType = .ReadCopySrc,
			Stages = .None,
			Slot = 0
		});
	}

	// =========================================================================
	// Write access declarations
	// =========================================================================

	/// Declares that this pass writes to a color render target at the given slot.
	/// When loadOp is Load, an implicit read dependency is added so the scheduler
	/// orders this pass after the previous writer (read-modify-write semantics).
	public void WriteRenderTarget(RGTexture tex, uint32 slot,
		LoadOp loadOp = .Clear, StoreOp storeOp = .Store,
		ClearColor clearColor = .Black)
	{
		// LoadOp.Load implies reading existing render target content — add a read access
		// so the scheduler creates a read-after-write dependency. Uses ReadRenderTarget
		// (not ReadTexture) because the resource stays in RenderTarget state, not ShaderRead.
		if (loadOp == .Load)
		{
			mPass.Accesses.Add(.()
			{
				Resource = tex.Resource,
				AccessType = .ReadRenderTarget,
				Stages = .Fragment,
				Slot = slot
			});
		}

		mPass.Accesses.Add(.()
		{
			Resource = tex.Resource,
			AccessType = .WriteRenderTarget,
			Stages = .Fragment,
			Slot = slot
		});
		mPass.RenderTargets.Add(.()
		{
			Slot = slot,
			Texture = tex,
			LoadOp = loadOp,
			StoreOp = storeOp,
			ClearColor = clearColor
		});
	}

	/// Declares that this pass writes to the depth/stencil attachment.
	/// When depthLoadOp is Load, an implicit read dependency is added.
	public void WriteDepthStencil(RGTexture tex,
		LoadOp depthLoadOp = .Clear, StoreOp depthStoreOp = .Store,
		float depthClearValue = 1.0f,
		LoadOp stencilLoadOp = .DontCare, StoreOp stencilStoreOp = .DontCare,
		uint8 stencilClearValue = 0)
	{
		// LoadOp.Load implies reading existing depth content. Uses ReadDepthStencilLoad
		// (not ReadDepthStencil) because the resource stays in DepthStencilWrite state.
		if (depthLoadOp == .Load)
		{
			mPass.Accesses.Add(.()
			{
				Resource = tex.Resource,
				AccessType = .ReadDepthStencilLoad,
				Stages = .Fragment,
				Slot = 0
			});
		}

		mPass.Accesses.Add(.()
		{
			Resource = tex.Resource,
			AccessType = .WriteDepthStencil,
			Stages = .Fragment,
			Slot = 0
		});
		mPass.DepthStencil = .()
		{
			Texture = tex,
			DepthLoadOp = depthLoadOp,
			DepthStoreOp = depthStoreOp,
			DepthClearValue = depthClearValue,
			DepthReadOnly = false,
			StencilLoadOp = stencilLoadOp,
			StencilStoreOp = stencilStoreOp,
			StencilClearValue = stencilClearValue,
			StencilReadOnly = false
		};
	}

	/// Declares that this pass writes to a storage texture (UAV) in the given shader stages.
	public void WriteStorage(RGTexture tex, ShaderStage stages)
	{
		mPass.Accesses.Add(.()
		{
			Resource = tex.Resource,
			AccessType = .WriteStorage,
			Stages = stages,
			Slot = 0
		});
	}

	/// Declares that this pass writes to a storage buffer (UAV) in the given shader stages.
	public void WriteStorage(RGBuffer buf, ShaderStage stages)
	{
		mPass.Accesses.Add(.()
		{
			Resource = buf.Resource,
			AccessType = .WriteStorage,
			Stages = stages,
			Slot = 0
		});
	}

	/// Declares that this pass writes to a texture as a copy destination.
	public void WriteCopyDst(RGTexture tex)
	{
		mPass.Accesses.Add(.()
		{
			Resource = tex.Resource,
			AccessType = .WriteCopyDst,
			Stages = .None,
			Slot = 0
		});
	}

	/// Declares that this pass writes to a buffer as a copy destination.
	public void WriteCopyDst(RGBuffer buf)
	{
		mPass.Accesses.Add(.()
		{
			Resource = buf.Resource,
			AccessType = .WriteCopyDst,
			Stages = .None,
			Slot = 0
		});
	}

	// =========================================================================
	// Read-write (UAV) access
	// =========================================================================

	/// Declares that this pass reads AND writes a storage texture (UAV) in the same dispatch/draw.
	/// Creates a dependency on the previous writer and produces a new version.
	public void ReadWriteStorage(RGTexture tex, ShaderStage stages)
	{
		mPass.Accesses.Add(.()
		{
			Resource = tex.Resource,
			AccessType = .ReadWriteStorage,
			Stages = stages,
			Slot = 0
		});
	}

	/// Declares that this pass reads AND writes a storage buffer (UAV) in the same dispatch/draw.
	/// Creates a dependency on the previous writer and produces a new version.
	public void ReadWriteStorage(RGBuffer buf, ShaderStage stages)
	{
		mPass.Accesses.Add(.()
		{
			Resource = buf.Resource,
			AccessType = .ReadWriteStorage,
			Stages = stages,
			Slot = 0
		});
	}

	// =========================================================================
	// Automatic mipmap generation
	// =========================================================================

	/// Declares that this pass generates mipmaps for the given texture.
	/// The texture must have been created with MipLevelCount > 1.
	/// Adds appropriate read (CopySrc) and write (CopyDst) accesses for the mip chain.
	public void GenerateMipmaps(RGTexture tex)
	{
		// Mipmap generation reads from each mip level and writes to the next.
		// We model this as a read-write access so it creates proper dependencies.
		mPass.Accesses.Add(.()
		{
			Resource = tex.Resource,
			AccessType = .ReadWriteStorage,
			Stages = .None,
			Slot = 0
		});
	}

	// =========================================================================
	// Side effects & execute
	// =========================================================================

	/// Marks this pass as having side effects (e.g., presenting to screen).
	/// Prevents the pass from being culled even if no other pass reads its outputs.
	public void HasSideEffects()
	{
		mPass.HasSideEffects = true;
	}

	/// Sets a runtime condition for this pass. If the condition returns false
	/// at execution time, the pass is skipped. Unlike culling, conditional passes
	/// still participate in scheduling and barrier solving — they are only skipped
	/// at the last moment during execution.
	public void EnableIf(delegate bool() condition)
	{
		mPass.Condition = condition;
	}

	/// Sets the execute callback for this pass.
	public void SetExecute(RGExecuteCallback callback)
	{
		mPass.ExecuteCallback = callback;
	}
}
