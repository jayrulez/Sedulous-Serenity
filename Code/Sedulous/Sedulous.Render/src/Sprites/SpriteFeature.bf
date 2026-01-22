namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Sprite render feature - renders camera-facing billboarded quads batched by texture.
public class SpriteFeature : RenderFeatureBase
{
	// Render pipeline (alpha blend, depth test, no depth write)
	private IRenderPipeline mRenderPipeline ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;

	// Bind group layouts
	private IBindGroupLayout mBindGroupLayout ~ delete _;

	// Per-frame instance buffers
	private IBuffer[RenderConfig.FrameBufferCount] mInstanceBuffers ~ { for (let b in _) delete b; };

	// Default sampler
	private ISampler mDefaultSampler ~ delete _;

	// Per-frame bind groups cached per texture per frame
	private List<TextureBindGroupEntry>[RenderConfig.FrameBufferCount] mBindGroupCache;

	// Sprite batch data
	private List<SpriteBatch> mBatches = new .() ~ delete _;
	private List<SpriteInstance> mInstances = new .() ~ delete _;

	// Sort key for grouping by texture
	private List<SpriteSortEntry> mSortEntries = new .() ~ delete _;

	// Per-frame view dimensions
	private uint32 mViewWidth;
	private uint32 mViewHeight;

	// Max sprites per frame
	private const int32 MaxSprites = 8192;

	/// Feature name.
	public override StringView Name => "Sprites";

	/// Sprites render after transparent.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardTransparent");
	}

	protected override Result<void> OnInitialize()
	{
		InitBindGroupCache();

		if (CreateResources() case .Err)
			return .Err;

		if (CreatePipeline() case .Err)
			return .Err;

		return .Ok;
	}

	protected override void OnShutdown()
	{
		CleanupBindGroupCache();
	}

	private void InitBindGroupCache()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			mBindGroupCache[i] = new .();
	}

	private void CleanupBindGroupCache()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mBindGroupCache[i] != null)
			{
				for (let entry in mBindGroupCache[i])
					delete entry.BindGroup;
				delete mBindGroupCache[i];
				mBindGroupCache[i] = null;
			}
		}
	}

	private Result<void> CreateResources()
	{
		// Create default sampler
		SamplerDescriptor samplerDesc = .()
		{
			Label = "Sprite Sampler",
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear
		};

		switch (Renderer.Device.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler): mDefaultSampler = sampler;
		case .Err: return .Err;
		}

		// Create per-frame instance buffers
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDescriptor bufDesc = .()
			{
				Label = "Sprite Instance Buffer",
				Size = (uint64)(MaxSprites * SpriteInstance.SizeInBytes),
				Usage = .Vertex | .CopyDst
			};

			switch (Renderer.Device.CreateBuffer(&bufDesc))
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

		BindGroupLayoutDescriptor layoutDesc = .()
		{
			Label = "Sprite BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(&pipelineLayoutDesc))
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
					ArrayStride = (uint64)SpriteInstance.SizeInBytes,
					StepMode = .Instance,
					Attributes = VertexAttribute[4](
						.() { Format = .Float3,           Offset = 0,  ShaderLocation = 0 },  // Position
						.() { Format = .Float2,           Offset = 12, ShaderLocation = 1 },  // Size
						.() { Format = .Float4,           Offset = 16, ShaderLocation = 2 },  // UVRect
						.() { Format = .UByte4Normalized, Offset = 32, ShaderLocation = 3 }   // Color
					)
				}
			);

			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, .AlphaBlend)
			);

			RenderPipelineDescriptor renderDesc = .()
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
				DepthStencil = .Transparent,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&renderDesc))
			{
			case .Ok(let pipeline): mRenderPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		return .Ok;
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		if (mRenderPipeline == null)
			return;

		// Collect sprites and group by texture
		mBatches.Clear();
		mInstances.Clear();
		mSortEntries.Clear();

		int32 spriteIdx = 0;
		world.ForEachSprite(scope [&] (handle, proxy) =>
		{
			if (!proxy.IsActive || proxy.Texture == null)
				return;

			if (spriteIdx >= MaxSprites)
				return;

			mSortEntries.Add(.() { TextureView = proxy.Texture, OriginalIndex = spriteIdx });

			SpriteInstance inst = .();
			inst.Position = proxy.Position;
			inst.Size = proxy.Size;
			inst.UVRect = proxy.UVRect;
			inst.Color = proxy.Color;
			mInstances.Add(inst);

			spriteIdx++;
		});

		if (mInstances.Count == 0)
			return;

		// Sort by texture pointer (groups same-texture sprites together)
		SortByTexture();

		// Build batches from sorted entries
		BuildBatches();

		// Upload instance data
		let frameIndex = Renderer.RenderFrameContext.FrameIndex;
		let buffer = mInstanceBuffers[frameIndex];

		if (buffer != null)
		{
			// Write sorted instances to buffer
			List<SpriteInstance> sortedInstances = scope .();
			sortedInstances.Reserve((int)mInstances.Count);
			for (let entry in mSortEntries)
				sortedInstances.Add(mInstances[entry.OriginalIndex]);

			Renderer.Device.Queue.WriteBuffer(
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

		graph.AddGraphicsPass("SpriteRender")
			.WriteColor(colorHandle, .Load, .Store)
			.ReadDepth(depthHandle)
			.NeverCull()
			.SetExecuteCallback(new [&] (encoder) => {
				ExecuteRenderPass(encoder);
			});
	}

	private void ExecuteRenderPass(IRenderPassEncoder encoder)
	{
		if (mViewWidth == 0 || mViewHeight == 0)
			return;

		encoder.SetViewport(0, 0, (float)mViewWidth, (float)mViewHeight, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, mViewWidth, mViewHeight);

		encoder.SetPipeline(mRenderPipeline);

		let frameIndex = Renderer.RenderFrameContext.FrameIndex;
		let instanceBuffer = mInstanceBuffers[frameIndex];
		if (instanceBuffer == null)
			return;

		encoder.SetVertexBuffer(0, instanceBuffer, 0);

		for (let batch in mBatches)
		{
			let bindGroup = GetOrCreateBindGroup(batch.TextureView, frameIndex);
			if (bindGroup == null)
				continue;

			encoder.SetBindGroup(0, bindGroup, default);
			encoder.Draw(6, (uint32)batch.Count, 0, (uint32)batch.StartIndex);
			Renderer.Stats.DrawCalls++;
			Renderer.Stats.InstanceCount += batch.Count;
		}
	}

	private IBindGroup GetOrCreateBindGroup(ITextureView textureView, int32 frameIndex)
	{
		let cache = mBindGroupCache[frameIndex];

		// Linear search (few unique textures per frame)
		for (let entry in cache)
		{
			if (entry.TextureView == textureView)
				return entry.BindGroup;
		}

		let cameraBuffer = Renderer.RenderFrameContext?.GetSceneUniformBuffer(frameIndex);
		if (cameraBuffer == null || mBindGroupLayout == null || mDefaultSampler == null)
			return null;

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Texture(0, textureView),
			BindGroupEntry.Sampler(0, mDefaultSampler)
		);

		BindGroupDescriptor bgDesc = .()
		{
			Label = "Sprite BindGroup",
			Layout = mBindGroupLayout,
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroup(&bgDesc))
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
			while (j >= 0 && (int)(void*)mSortEntries[j].TextureView > (int)(void*)key.TextureView)
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
