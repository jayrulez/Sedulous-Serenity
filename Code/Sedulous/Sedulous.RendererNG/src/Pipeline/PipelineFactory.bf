namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Materials;

/// Cached render pipeline entry.
class CachedPipeline
{
	public IRenderPipeline Pipeline ~ delete _;
	public uint64 LastUsedFrame;
	public PipelineConfig Config;
}

/// Creates and caches render pipelines based on PipelineConfig.
/// Uses content-based hashing for cache lookup.
class PipelineFactory : IDisposable
{
	private IDevice mDevice;
	private ShaderLibrary mShaderSystem;

	/// Pipeline cache by config hash.
	private Dictionary<int, CachedPipeline> mPipelineCache = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	/// Pipeline layout cache (by bind group layout combination).
	private Dictionary<int, IPipelineLayout> mLayoutCache = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	/// Current frame number for LRU tracking.
	private uint64 mCurrentFrame = 0;

	/// Number of frames before unused pipelines are purged.
	public uint32 PurgeThreshold = 300; // ~5 seconds at 60fps

	/// Total pipelines created.
	public int PipelineCount => mPipelineCache.Count;

	/// Total pipeline layouts created.
	public int LayoutCount => mLayoutCache.Count;

	/// Initializes the pipeline factory.
	public Result<void> Initialize(IDevice device, ShaderLibrary shaderSystem)
	{
		mDevice = device;
		mShaderSystem = shaderSystem;
		return .Ok;
	}

	/// Sets the current frame number for LRU tracking.
	public void BeginFrame(uint64 frameIndex)
	{
		mCurrentFrame = frameIndex;
	}

	/// Gets or creates a render pipeline for the given configuration.
	public Result<IRenderPipeline> GetOrCreatePipeline(PipelineConfig config, IPipelineLayout layout)
	{
		let hash = config.GetHashCode();

		// Check cache
		if (mPipelineCache.TryGetValue(hash, let cached))
		{
			cached.LastUsedFrame = mCurrentFrame;
			return cached.Pipeline;
		}

		// Create new pipeline
		switch (CreatePipeline(config, layout))
		{
		case .Ok(let pipeline):
			let entry = new CachedPipeline();
			entry.Pipeline = pipeline;
			entry.LastUsedFrame = mCurrentFrame;
			entry.Config = config;
			mPipelineCache[hash] = entry;
			return pipeline;

		case .Err:
			return .Err;
		}
	}

	/// Creates a new render pipeline from configuration.
	private Result<IRenderPipeline> CreatePipeline(PipelineConfig config, IPipelineLayout layout)
	{
		// Get shaders
		IShaderModule vertexShader = null;
		IShaderModule fragmentShader = null;

		if (mShaderSystem.GetShader(config.ShaderName, .Vertex, config.ShaderFlags) case .Ok(let vsModule))
		{
			if (vsModule.GetRhiModule(mDevice) case .Ok(let rhi))
				vertexShader = rhi;
		}

		if (vertexShader == null)
		{
			Console.WriteLine("PipelineFactory: Failed to get vertex shader '{}'", config.ShaderName);
			return .Err;
		}

		if (!config.DepthOnly)
		{
			if (mShaderSystem.GetShader(config.ShaderName, .Fragment, config.ShaderFlags) case .Ok(let fsModule))
			{
				if (fsModule.GetRhiModule(mDevice) case .Ok(let rhi))
					fragmentShader = rhi;
			}

			if (fragmentShader == null)
			{
				Console.WriteLine("PipelineFactory: Failed to get fragment shader '{}'", config.ShaderName);
				return .Err;
			}
		}

		// Build vertex layout for per-vertex data (slot 0)
		VertexAttribute[8] vertexAttribs = default;
		let attribCount = VertexLayouts.FillAttributes(config.VertexLayout, Span<VertexAttribute>(&vertexAttribs[0], 8));
		let stride = VertexLayouts.GetStride(config.VertexLayout);

		// Build instance attributes (slot 1) for instanced rendering
		// MeshInstanceData: WorldMatrix (4x float4), NormalMatrix (4x float4), CustomData (float4)
		// Locations 3-11 (after per-vertex data which uses 0-2)
		// Constructor: (format, offset, shaderLocation)
		VertexAttribute[9] instanceAttribs = .(
			.(.Float4, 0,   3),   // WorldMatrix row 0
			.(.Float4, 16,  4),   // WorldMatrix row 1
			.(.Float4, 32,  5),   // WorldMatrix row 2
			.(.Float4, 48,  6),   // WorldMatrix row 3
			.(.Float4, 64,  7),   // NormalMatrix row 0
			.(.Float4, 80,  8),   // NormalMatrix row 1
			.(.Float4, 96,  9),   // NormalMatrix row 2
			.(.Float4, 112, 10),  // NormalMatrix row 3
			.(.Float4, 128, 11)   // CustomData
		);
		let instanceStride = MeshInstanceData.Size; // 144 bytes

		// Set up vertex buffers - 1 for per-vertex, optionally 1 for per-instance
		VertexBufferLayout[2] vertexBuffers = default;
		int32 bufferCount = 0;

		if (attribCount > 0)
		{
			vertexBuffers[0] = .(stride, Span<VertexAttribute>(&vertexAttribs[0], attribCount));
			bufferCount++;
		}

		// Add instance buffer for instanced rendering
		if (config.ShaderFlags.HasFlag(.Instanced))
		{
			var instanceLayout = VertexBufferLayout(instanceStride, instanceAttribs);
			instanceLayout.StepMode = .Instance;
			vertexBuffers[bufferCount] = instanceLayout;
			bufferCount++;
		}

		// Build primitive state
		var primitive = PrimitiveState();
		primitive.Topology = config.Topology;
		primitive.FrontFace = config.FrontFace;
		primitive.FillMode = config.FillMode;

		switch (config.CullMode)
		{
		case .None: primitive.CullMode = .None;
		case .Back: primitive.CullMode = .Back;
		case .Front: primitive.CullMode = .Front;
		}

		// Build depth/stencil state
		DepthStencilState? depthStencil = null;
		if (config.DepthMode != .Disabled)
		{
			var ds = DepthStencilState();
			ds.Format = config.DepthFormat;
			ds.DepthBias = (int32)config.DepthBias;
			ds.DepthBiasSlopeScale = config.DepthBiasSlopeScale;

			switch (config.DepthMode)
			{
			case .ReadWrite:
				ds.DepthTestEnabled = true;
				ds.DepthWriteEnabled = true;
				ds.DepthCompare = config.DepthCompare;
			case .ReadOnly:
				ds.DepthTestEnabled = true;
				ds.DepthWriteEnabled = false;
				ds.DepthCompare = config.DepthCompare;
			case .WriteOnly:
				ds.DepthTestEnabled = false;
				ds.DepthWriteEnabled = true;
			case .Disabled:
				// Already handled above
			}

			depthStencil = ds;
		}

		// Build color targets
		ColorTargetState[1] colorTargets = default;
		FragmentState? fragmentState = null;

		if (config.ColorTargetCount > 0 && !config.DepthOnly)
		{
			var target = ColorTargetState(config.ColorFormat);
			target.WriteMask = config.ColorWriteMask;

			// Set blend state based on mode
			switch (config.BlendMode)
			{
			case .Opaque:
				target.Blend = null;
			case .AlphaBlend:
				target.Blend = BlendState.AlphaBlend;
			case .Additive:
				var blend = BlendState();
				blend.Color = .(.Add, .One, .One);
				blend.Alpha = .(.Add, .One, .One);
				target.Blend = blend;
			case .Multiply:
				var blend = BlendState();
				blend.Color = .(.Add, .Dst, .Zero);
				blend.Alpha = .(.Add, .DstAlpha, .Zero);
				target.Blend = blend;
			case .PremultipliedAlpha:
				var blend = BlendState();
				blend.Color = .(.Add, .One, .OneMinusSrcAlpha);
				blend.Alpha = .(.Add, .One, .OneMinusSrcAlpha);
				target.Blend = blend;
			}

			colorTargets[0] = target;

			var fs = FragmentState();
			fs.Shader = .(fragmentShader);
			fs.Targets = Span<ColorTargetState>(&colorTargets[0], config.ColorTargetCount);
			fragmentState = fs;
		}

		// Build multisample state
		var multisample = MultisampleState();
		multisample.Count = config.SampleCount;

		// Create pipeline descriptor
		var desc = RenderPipelineDescriptor();
		desc.Layout = layout;
		desc.Vertex = .() {
			Shader = .(vertexShader),
			Buffers = bufferCount > 0 ? Span<VertexBufferLayout>(&vertexBuffers[0], bufferCount) : default
		};
		desc.Fragment = fragmentState;
		desc.Primitive = primitive;
		desc.DepthStencil = depthStencil;
		desc.Multisample = multisample;

		return mDevice.CreateRenderPipeline(&desc);
	}

	/// Purges pipelines that haven't been used recently.
	public void PurgeUnused()
	{
		List<int> toRemove = scope .();

		for (let (hash, cached) in mPipelineCache)
		{
			if (mCurrentFrame - cached.LastUsedFrame > PurgeThreshold)
				toRemove.Add(hash);
		}

		for (let hash in toRemove)
		{
			if (mPipelineCache.TryGetValue(hash, let cached))
			{
				delete cached;
				mPipelineCache.Remove(hash);
			}
		}
	}

	/// Clears all cached pipelines.
	public void ClearCache()
	{
		for (let kv in mPipelineCache)
			delete kv.value;
		mPipelineCache.Clear();

		for (let kv in mLayoutCache)
			delete kv.value;
		mLayoutCache.Clear();
	}

	/// Gets pipeline factory statistics.
	public void GetStats(String outStats)
	{
		outStats.AppendF("Pipeline Factory Stats:\n");
		outStats.AppendF("  Cached pipelines: {}\n", mPipelineCache.Count);
		outStats.AppendF("  Cached layouts: {}\n", mLayoutCache.Count);
		outStats.AppendF("  Current frame: {}\n", mCurrentFrame);
	}

	public void Dispose()
	{
		ClearCache();
	}
}
