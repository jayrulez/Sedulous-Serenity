namespace Sedulous.Renderer;

using System;
using System.Collections;
using System.IO;
using Sedulous.RHI;

/// Dynamic render pipeline creation with caching.
/// Creates pipelines on demand from (material + vertex layout + RT format)
/// and caches them by PipelineKey. Supports optional disk serialization
/// via IPipelineCache.
public class RenderPipelineCache
{
	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private IPipelineCache mPipelineCache;

	/// Cached pipelines.
	private Dictionary<PipelineKey, IRenderPipeline> mPipelines = new .() ~ delete _;

	/// Cached pipeline layouts, keyed by a hash of their bind group layouts.
	private Dictionary<uint64, IPipelineLayout> mLayouts = new .() ~ delete _;

	/// Initializes the pipeline cache.
	public Result<void> Initialize(IDevice device, ShaderLibrary shaderLibrary)
	{
		mDevice = device;
		mShaderLibrary = shaderLibrary;

		// Create pipeline cache (empty initial data)
		let cacheResult = device.CreatePipelineCache(PipelineCacheDesc()
		{
			Label = "RenderPipelineCache"
		});

		if (cacheResult case .Ok(let cache))
			mPipelineCache = cache;

		return .Ok;
	}

	/// Gets or creates a render pipeline for the given configuration.
	public Result<IRenderPipeline> GetOrCreate(
		MaterialDefinition material,
		Span<VertexBufferLayout> vertexBuffers,
		IBindGroupLayout sceneLayout,
		TextureFormat colorFormat,
		TextureFormat depthFormat,
		uint8 sampleCount = 1,
		PipelineVariantFlags variantFlags = .None,
		IBindGroupLayout objectLayout = null,
		TextureFormat colorFormat2 = .Undefined)
	{
		let shaderNameHash = HashName(material.ShaderName);

		let key = PipelineKey()
		{
			VertexShader = .() { ShaderNameHash = shaderNameHash, Stage = .Vertex, Flags = variantFlags },
			FragmentShader = .() { ShaderNameHash = shaderNameHash, Stage = .Fragment, Flags = variantFlags },
			VertexLayoutHash = PipelineKey.HashVertexLayouts(vertexBuffers),
			BlendMode = material.BlendMode,
			CullMode = material.CullMode,
			DepthMode = material.DepthMode,
			ColorFormat = colorFormat,
			ColorFormat2 = colorFormat2,
			DepthFormat = depthFormat,
			SampleCount = sampleCount,
			VariantFlags = variantFlags,
		};

		// Check cache
		if (mPipelines.TryGetValue(key, let existing))
			return .Ok(existing);

		// Compile shaders
		let vsResult = mShaderLibrary.GetCompiledShader(material.ShaderName, .Vertex, variantFlags);
		if (vsResult case .Err)
			return .Err;

		// Fragment shader is optional for depth-only
		IShaderModule fsModule = null;
		bool hasFragment = !variantFlags.HasFlag(.DepthOnly);
		if (hasFragment)
		{
			let fsResult = mShaderLibrary.GetCompiledShader(material.ShaderName, .Fragment, variantFlags);
			if (fsResult case .Err)
				return .Err;
			fsModule = fsResult.Value;
		}

		// Get or create pipeline layout
		// 3-set layout: scene + material + object (forward pass with material bindings)
		// 2-set layout with object: scene + object (depth pass, no material bindings)
		// 2-set layout without object: scene + material (legacy/simple)
		Result<IPipelineLayout> layoutResult;
		if (objectLayout != null && material.BindGroupLayout != null)
			layoutResult = GetOrCreateLayout(sceneLayout, material.BindGroupLayout, objectLayout);
		else if (objectLayout != null)
			layoutResult = GetOrCreateLayout(sceneLayout, objectLayout);
		else
			layoutResult = GetOrCreateLayout(sceneLayout, material.BindGroupLayout);
		if (layoutResult case .Err)
			return .Err;

		// Build descriptor
		let blend = MaterialDefinition.GetBlendState(material.BlendMode);
		var colorTargets = ColorTargetState[2](
			.() { Format = colorFormat, Blend = blend },
			.() { Format = colorFormat2 }  // No blending on G-buffer
		);
		let colorTargetCount = (colorFormat2 != .Undefined) ? 2 : 1;

		var depthState = MaterialDefinition.GetDepthStencilState(material.DepthMode, depthFormat);

		var desc = RenderPipelineDesc()
		{
			Layout = layoutResult.Value,
			Vertex = .() { Shader = .(vsResult.Value, "VSMain"), Buffers = vertexBuffers },
			Primitive = .()
			{
				Topology = .TriangleList,
				CullMode = material.CullMode,
				FrontFace = .CCW
			},
			DepthStencil = depthState,
			Multisample = .() { Count = (uint32)sampleCount },
			Cache = mPipelineCache,
			Label = material.Name
		};

		if (hasFragment)
		{
			desc.Fragment = .() { Shader = .(fsModule, "PSMain"), Targets = Span<ColorTargetState>(&colorTargets[0], colorTargetCount) };
		}

		let pipelineResult = mDevice.CreateRenderPipeline(desc);
		if (pipelineResult case .Err)
			return .Err;

		let pipeline = pipelineResult.Value;
		mPipelines[key] = pipeline;
		return .Ok(pipeline);
	}

	/// Gets or creates a pipeline layout from scene + material bind group layouts.
	public Result<IPipelineLayout> GetOrCreateLayout(
		IBindGroupLayout sceneLayout,
		IBindGroupLayout materialLayout)
	{
		// Hash the layout pointers for caching
		let hash = ((uint64)(int)Internal.UnsafeCastToPtr(sceneLayout) * 2654435761) ^ ((uint64)(int)Internal.UnsafeCastToPtr(materialLayout) * 40503);

		if (mLayouts.TryGetValue(hash, let existing))
			return .Ok(existing);

		// Set 0 = scene, Set 1 = material
		IBindGroupLayout[2] layouts = .(sceneLayout, materialLayout);
		let result = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = Span<IBindGroupLayout>(&layouts[0], 2),
			Label = "MaterialPipelineLayout"
		});

		if (result case .Err)
			return .Err;

		let layout = result.Value;
		mLayouts[hash] = layout;
		return .Ok(layout);
	}

	/// Gets or creates a pipeline layout from scene + material + object bind group layouts.
	public Result<IPipelineLayout> GetOrCreateLayout(
		IBindGroupLayout sceneLayout,
		IBindGroupLayout materialLayout,
		IBindGroupLayout objectLayout)
	{
		// Hash all three layout pointers for caching
		var hash = ((uint64)(int)Internal.UnsafeCastToPtr(sceneLayout) * 2654435761);
		hash ^= ((uint64)(int)Internal.UnsafeCastToPtr(materialLayout) * 40503);
		hash ^= ((uint64)(int)Internal.UnsafeCastToPtr(objectLayout) * 2246822519);

		if (mLayouts.TryGetValue(hash, let existing))
			return .Ok(existing);

		// Set 0 = scene, Set 1 = material, Set 2 = object
		IBindGroupLayout[3] layouts = .(sceneLayout, materialLayout, objectLayout);
		let result = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = Span<IBindGroupLayout>(&layouts[0], 3),
			Label = "MaterialObjectPipelineLayout"
		});

		if (result case .Err)
			return .Err;

		let layout = result.Value;
		mLayouts[hash] = layout;
		return .Ok(layout);
	}

	/// Saves the pipeline cache data to disk.
	public Result<void> SaveCache(StringView path)
	{
		if (mPipelineCache == null)
			return .Err;

		let size = mPipelineCache.GetDataSize();
		if (size == 0)
			return .Ok;

		let data = scope uint8[size];
		if (mPipelineCache.GetData(data) case .Err)
			return .Err;

		let stream = scope FileStream();
		if (stream.Create(path, .Write) case .Err)
			return .Err;

		if (stream.TryWrite(Span<uint8>(data.Ptr, data.Count)) case .Err)
			return .Err;

		return .Ok;
	}

	/// Loads pipeline cache data from disk.
	public Result<void> LoadCache(StringView path)
	{
		if (mPipelineCache != null)
			mDevice.DestroyPipelineCache(ref mPipelineCache);

		let stream = scope FileStream();
		if (stream.Open(path, .Read) case .Err)
		{
			// No existing cache is fine — create empty
			let cacheResult = mDevice.CreatePipelineCache(PipelineCacheDesc());
			if (cacheResult case .Ok(let cache))
				mPipelineCache = cache;
			return .Ok;
		}

		let size = stream.Length;
		let data = scope uint8[size];
		if (stream.TryRead(Span<uint8>(data.Ptr, data.Count)) case .Err)
			return .Err;

		let cacheResult = mDevice.CreatePipelineCache(PipelineCacheDesc()
		{
			InitialData = Span<uint8>(data.Ptr, data.Count)
		});

		if (cacheResult case .Err)
			return .Err;

		mPipelineCache = cacheResult.Value;
		return .Ok;
	}

	/// Destroys all cached pipelines.
	public void Clear()
	{
		for (let kv in mPipelines)
		{
			var pipeline = kv.value;
			mDevice.DestroyRenderPipeline(ref pipeline);
		}
		mPipelines.Clear();

		for (let kv in mLayouts)
		{
			var layout = kv.value;
			mDevice.DestroyPipelineLayout(ref layout);
		}
		mLayouts.Clear();
	}

	/// Shuts down and releases all resources.
	public void Shutdown()
	{
		Clear();

		if (mPipelineCache != null)
			mDevice.DestroyPipelineCache(ref mPipelineCache);
	}

	// --- Internal ---

	private static uint32 HashName(StringView name)
	{
		uint32 hash = 2166136261;
		for (let c in name.RawChars)
		{
			hash ^= (uint32)c;
			hash *= 16777619;
		}
		return hash;
	}
}
