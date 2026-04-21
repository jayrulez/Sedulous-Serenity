namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// Sprite render feature - renders camera-facing billboarded quads batched by texture.
public class SpriteFeature : RenderFeatureBase
{
	// Render pipeline (alpha blend, depth test, no depth write)
	private IRenderPipeline mRenderPipeline;
	private IPipelineLayout mPipelineLayout;

	// Bind group layouts
	private IBindGroupLayout mBindGroupLayout;

	// Per-frame instance buffers
	private IBuffer[RenderConfig.FrameBufferCount] mInstanceBuffers;

	// Default texture (white circle) and sampler
	private ITexture mDefaultTexture;
	private ITextureView mDefaultTextureView;
	private ISampler mDefaultSampler;

	// Per-frame/view bind groups cached per texture
	private List<TextureBindGroupEntry>[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mBindGroupCache;

	// Sprite batch data
	private List<SpriteBatch> mBatches = new .() ~ delete _;
	private List<SpriteInstance> mInstances = new .() ~ delete _;

	// Sort key for grouping by texture
	private List<SpriteSortEntry> mSortEntries = new .() ~ delete _;

	// Per-frame view dimensions
	private uint32 mViewWidth;
	private uint32 mViewHeight;
	private float mViewportX;
	private float mViewportY;

	// Max sprites per frame
	private const int32 MaxSprites = 8192;

	/// Feature name.
	public override StringView Name => "Sprites";

	/// Sprites render after transparent and sky.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardTransparent");
		outDependencies.Add("Sky");
	}

	protected override Result<void> OnInitialize(InitContext initCtx)
	{
		InitBindGroupCache();

		if (CreateResources(initCtx.TransferBatch) case .Err)
			return .Err;

		if (CreatePipeline() case .Err)
			return .Err;

		return .Ok;
	}

	protected override void OnShutdown()
	{
		let device = Renderer.Device;

		CleanupBindGroupCache();

		// Clean up per-frame instance buffers
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mInstanceBuffers[i] != null)
				device.DestroyBuffer(ref mInstanceBuffers[i]);
		}

		// Clean up pipelines and layouts
		device.DestroyRenderPipeline(ref mRenderPipeline);
		device.DestroyPipelineLayout(ref mPipelineLayout);
		device.DestroyBindGroupLayout(ref mBindGroupLayout);

		// Clean up default resources
		device.DestroyTextureView(ref mDefaultTextureView);
		device.DestroyTexture(ref mDefaultTexture);
		device.DestroySampler(ref mDefaultSampler);
	}

	private void InitBindGroupCache()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
			mBindGroupCache[i] = new .();
	}

	private void CleanupBindGroupCache()
	{
		let device = Renderer.Device;
		for (int i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mBindGroupCache[i] != null)
			{
				for (var entry in ref mBindGroupCache[i])
				{
					if (entry.BindGroup != null)
						device.DestroyBindGroup(ref entry.BindGroup);
				}
				delete mBindGroupCache[i];
				mBindGroupCache[i] = null;
			}
		}
	}

	private Result<void> CreateResources(ITransferBatch transferBatch)
	{
		// Create default white texture (32x32 solid white)
		const int32 TexSize = 32;
		const int32 TexBytes = TexSize * TexSize * 4;

		TextureDesc texDesc = .()
		{
			Label = "Default Sprite Texture",
			Width = TexSize,
			Height = TexSize,
			Depth = 1,
			Format = .RGBA8Unorm,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (Renderer.Device.CreateTexture(texDesc))
		{
		case .Ok(let tex): mDefaultTexture = tex;
		case .Err: return .Err;
		}

		uint8[] pixels = scope uint8[TexBytes];
		for (int32 i = 0; i < TexBytes; i++)
			pixels[i] = 255; // Solid white RGBA

		var layout = TextureDataLayout() { BytesPerRow = TexSize * 4, RowsPerImage = TexSize };
		var writeSize = Extent3D(TexSize, TexSize, 1);
		transferBatch.WriteTexture(mDefaultTexture, Span<uint8>(&pixels[0], TexBytes), layout, writeSize);

		TextureViewDesc viewDesc = .()
		{
			Label = "Default Sprite Texture View",
			Dimension = .Texture2D
		};

		switch (Renderer.Device.CreateTextureView(mDefaultTexture, viewDesc))
		{
		case .Ok(let view): mDefaultTextureView = view;
		case .Err: return .Err;
		}

		// Create default sampler
		SamplerDesc samplerDesc = .()
		{
			Label = "Sprite Sampler",
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear
		};

		switch (Renderer.Device.CreateSampler(samplerDesc))
		{
		case .Ok(let sampler): mDefaultSampler = sampler;
		case .Err: return .Err;
		}

		// Create per-frame instance buffers (host-visible for direct CPU writes each frame)
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc bufDesc = .()
			{
				Label = "Sprite Instance Buffer",
				Size = (uint64)(MaxSprites * SpriteInstance.SizeInBytes),
				Usage = .Vertex,
				Memory = .CpuToGpu
			};

			switch (Renderer.Device.CreateBuffer(bufDesc))
			{
			case .Ok(let buf): mInstanceBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private Result<void> CreatePipeline()
	{
		// Bind group layout:
		// - CameraUniforms (b0, vertex)
		// - Texture (t0, fragment)
		// - Sampler (s0, fragment)
		BindGroupLayoutEntry[3] entries = .(
			.() { Binding = 0, Visibility = .Vertex, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDesc layoutDesc = .()
		{
			Label = "Sprite BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDesc pipelineLayoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(pipelineLayoutDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Load shaders and create pipeline
		if (Renderer.ShaderSystem == null)
			return .Ok;

		let shaderResult = Renderer.ShaderSystem.GetShaderPair("sprite");
		if (shaderResult case .Ok(let shaders))
		{
			// Instance buffer layout (SpriteInstance as per-instance vertex data)
			VertexBufferLayout[1] vertexBuffers = .(
				.()
				{
					Stride = (uint32)SpriteInstance.SizeInBytes,
					StepMode = .Instance,
					Attributes = VertexAttribute[4](
						.() { Format = .Float3,           Offset = 0,  ShaderLocation = 0 },  // Position
						.() { Format = .Float2,           Offset = 12, ShaderLocation = 1 },  // Size
						.() { Format = .Float4,           Offset = 20, ShaderLocation = 2 },  // UVRect
						.() { Format = .UByte4Normalized, Offset = 36, ShaderLocation = 3 }   // Color
					)
				}
			);

			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, .AlphaBlend)
			);

			RenderPipelineDesc renderDesc = .()
			{
				Label = "Sprite Render Pipeline",
				Layout = mPipelineLayout,
				Vertex = .()
				{
					Shader = .(shaders.vert.Module, "main"),
					Buffers = vertexBuffers
				},
				Fragment = .()
				{
					Shader = .(shaders.frag.Module, "main"),
					Targets = colorTargets
				},
				Primitive = .()
				{
					Topology = .TriangleList,
					FrontFace = .CCW,
					CullMode = .None
				},
				DepthStencil = DepthStencilState.DepthReadOnly(Renderer.DepthFormat),
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(renderDesc))
			{
			case .Ok(let pipeline): mRenderPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		return .Ok;
	}

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderableList renderables)
	{
		if (mRenderPipeline == null)
			return;

		// Collect sprites and group by texture.
		// SpriteRenderable has everything we need — no need to reach into the world.
		mBatches.Clear();
		mInstances.Clear();
		mSortEntries.Clear();

		int32 spriteIdx = 0;
		for (let sprite in renderables.Sprites)
		{
			if (spriteIdx >= MaxSprites)
				break;

			let textureView = sprite.Texture != null ? sprite.Texture : mDefaultTextureView;
			mSortEntries.Add(.() { TextureView = textureView, OriginalIndex = spriteIdx });

			SpriteInstance inst = .();
			inst.Position = sprite.Position;
			inst.Size = sprite.Size;
			inst.UVRect = sprite.UVRect;
			inst.Color = sprite.Color;
			mInstances.Add(inst);

			spriteIdx++;
		}

		if (mInstances.Count == 0)
			return;

		// Sort by texture pointer (groups same-texture sprites together)
		SortByTexture();

		// Build batches from sorted entries
		BuildBatches();

		// Upload instance data
		let frameIndex = view.FrameIndex;
		let buffer = mInstanceBuffers[frameIndex];

		if (buffer != null)
		{
			// Write sorted instances to buffer
			List<SpriteInstance> sortedInstances = scope .();
			sortedInstances.Reserve((int)mInstances.Count);
			for (let entry in mSortEntries)
				sortedInstances.Add(mInstances[entry.OriginalIndex]);

			TransferHelper.WriteMappedBuffer(
				buffer, 0,
				Span<uint8>((uint8*)sortedInstances.Ptr, (int)(sortedInstances.Count * SpriteInstance.SizeInBytes))
			);
		}

		let colorHandle = graph.GetResource("SceneColor");
		let depthHandle = graph.GetResource("SceneDepth");

		if (!colorHandle.IsValid || !depthHandle.IsValid)
			return;

		mViewWidth = view.Width;
		mViewHeight = view.Height;
		mViewportX = view.ViewportX;
		mViewportY = view.ViewportY;

		let bindGroupIndex = view.GetBindGroupIndex();
		let sceneUniformBuffer = view.SceneUniformBuffer;

		graph.AddRenderPass("SpriteRender", scope (builder) => {
				builder.SetColorTarget(0, colorHandle, .Load, .Store);
				builder.ReadDepth(depthHandle);
				builder.NeverCull();
				builder.SetExecute(new (encoder) => {
					ExecuteRenderPass(encoder, frameIndex, bindGroupIndex, sceneUniformBuffer);
				});
			});
	}

	private void ExecuteRenderPass(IRenderPassEncoder encoder, int32 frameIndex, int32 bindGroupIndex, IBuffer sceneUniformBuffer)
	{
		if (mViewWidth == 0 || mViewHeight == 0)
			return;

		// Render to per-view SceneColor texture at (0,0), not swapchain offset
		encoder.SetViewport(0, 0, (float)mViewWidth, (float)mViewHeight, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, mViewWidth, mViewHeight);

		encoder.SetPipeline(mRenderPipeline);

		let instanceBuffer = mInstanceBuffers[frameIndex];
		if (instanceBuffer == null)
			return;

		encoder.SetVertexBuffer(0, instanceBuffer, 0);

		for (let batch in mBatches)
		{
			let bindGroup = GetOrCreateBindGroup(batch.TextureView, bindGroupIndex, sceneUniformBuffer);
			if (bindGroup == null)
				continue;

			encoder.SetBindGroup(0, bindGroup, default);
			encoder.Draw(6, (uint32)batch.Count, 0, (uint32)batch.StartIndex);
			Renderer.Stats.DrawCalls++;
			Renderer.Stats.InstanceCount += batch.Count;
		}
	}

	private IBindGroup GetOrCreateBindGroup(ITextureView textureView, int32 bindGroupIndex, IBuffer sceneUniformBuffer)
	{
		let cache = mBindGroupCache[bindGroupIndex];

		// Linear search (few unique textures per frame)
		for (let entry in cache)
		{
			if (entry.TextureView == textureView)
				return entry.BindGroup;
		}

		let cameraBuffer = sceneUniformBuffer;
		if (cameraBuffer == null || mBindGroupLayout == null || mDefaultSampler == null)
			return null;

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(/*0,*/cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Texture(/*0,*/textureView),
			BindGroupEntry.Sampler(/*0,*/mDefaultSampler)
		);

		BindGroupDesc bgDesc = .()
		{
			Label = "Sprite BindGroup",
			Layout = mBindGroupLayout,
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg):
			cache.Add(.() { TextureView = textureView, BindGroup = bg });
			return bg;
		case .Err:
			return null;
		}
	}

	private void SortByTexture()
	{
		// Insertion sort (simple, stable, good for small counts)
		for (int i = 1; i < mSortEntries.Count; i++)
		{
			let key = mSortEntries[i];
			var j = i - 1;
			while (j >= 0 && (int)Internal.UnsafeCastToPtr(mSortEntries[j].TextureView) > (int)Internal.UnsafeCastToPtr(key.TextureView))
			{
				mSortEntries[j + 1] = mSortEntries[j];
				j--;
			}
			mSortEntries[j + 1] = key;
		}
	}

	private void BuildBatches()
	{
		if (mSortEntries.Count == 0)
			return;

		var currentTexture = mSortEntries[0].TextureView;
		int32 batchStart = 0;

		for (int32 i = 1; i < mSortEntries.Count; i++)
		{
			if (mSortEntries[i].TextureView != currentTexture)
			{
				mBatches.Add(.() { TextureView = currentTexture, StartIndex = batchStart, Count = (int32)(i - batchStart) });
				currentTexture = mSortEntries[i].TextureView;
				batchStart = i;
			}
		}

		// Final batch
		mBatches.Add(.() { TextureView = currentTexture, StartIndex = batchStart, Count = (int32)(mSortEntries.Count - batchStart) });
	}

	struct TextureBindGroupEntry
	{
		public ITextureView TextureView;
		public IBindGroup BindGroup;
	}

	struct SpriteSortEntry
	{
		public ITextureView TextureView;
		public int32 OriginalIndex;
	}

	struct SpriteBatch
	{
		public ITextureView TextureView;
		public int32 StartIndex;
		public int32 Count;
	}
}
