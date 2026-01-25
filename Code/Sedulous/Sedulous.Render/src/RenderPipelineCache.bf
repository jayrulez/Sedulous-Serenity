namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Materials;

/// Key for pipeline cache lookups.
/// Combines material properties with vertex layout and render target context.
struct RenderPipelineKey : IHashable, IEquatable<RenderPipelineKey>
{
	/// Hash of shader name and flags.
	public int ShaderHash;

	/// Hash of render state (blend, cull, depth).
	public int RenderStateHash;

	/// Hash of vertex buffer layouts.
	public int VertexLayoutHash;

	/// Color target format.
	public TextureFormat ColorFormat;

	/// Depth buffer format.
	public TextureFormat DepthFormat;

	/// MSAA sample count.
	public uint8 SampleCount;

	/// Pipeline layout pointer hash (for bind group compatibility).
	public int LayoutHash;

	/// Additional flags for variants.
	public uint32 VariantFlags;

	public int GetHashCode()
	{
		int hash = ShaderHash;
		hash = hash * 31 + RenderStateHash;
		hash = hash * 31 + VertexLayoutHash;
		hash = hash * 31 + (int)ColorFormat;
		hash = hash * 31 + (int)DepthFormat;
		hash = hash * 31 + (int)SampleCount;
		hash = hash * 31 + LayoutHash;
		hash = hash * 31 + (int)VariantFlags;
		return hash;
	}

	public bool Equals(RenderPipelineKey other)
	{
		return ShaderHash == other.ShaderHash &&
			RenderStateHash == other.RenderStateHash &&
			VertexLayoutHash == other.VertexLayoutHash &&
			ColorFormat == other.ColorFormat &&
			DepthFormat == other.DepthFormat &&
			SampleCount == other.SampleCount &&
			LayoutHash == other.LayoutHash &&
			VariantFlags == other.VariantFlags;
	}
}

/// Variant flags for pipeline creation.
/// These affect shader selection and pipeline state.
enum PipelineVariantFlags : uint32
{
	None = 0,
	Instanced = 1 << 0,      // Use instanced shader variant
	ReceiveShadows = 1 << 1,
	BackFaceCull = 1 << 2,   // For two-pass transparent rendering
	FrontFaceCull = 1 << 3,
}

/// Caches render pipelines by configuration.
/// Creates pipelines on demand based on material properties and caller-provided vertex layouts.
///
/// Vertex layouts are determined by the mesh type being rendered, not the material.
/// The caller (render feature) knows what mesh format it's rendering and provides
/// the appropriate vertex buffer layouts.
class RenderPipelineCache
{
	private IDevice mDevice;
	private NewShaderSystem mShaderSystem;
	private Dictionary<int, IRenderPipeline> mCache = new .() ~ DeleteDictionaryAndValues!(_);

	public this(IDevice device, NewShaderSystem shaderSystem)
	{
		mDevice = device;
		mShaderSystem = shaderSystem;
	}

	/// Gets or creates a pipeline for a material instance with caller-provided vertex layouts.
	///
	/// Parameters:
	/// - material: The material instance (provides shader name, flags, blend/cull/depth modes)
	/// - vertexBuffers: Vertex buffer layouts determined by mesh type (provided by caller)
	/// - layout: Pipeline layout for bind groups
	/// - colorFormat: Render target color format
	/// - depthFormat: Render target depth format
	/// - sampleCount: MSAA sample count
	/// - variantFlags: Additional pipeline variants (shadows, cull mode overrides)
	/// - depthModeOverride: Override material's depth mode (e.g., for forward pass with depth prepass)
	/// - depthCompareOverride: Override material's depth compare (e.g., LessEqual for forward pass after prepass)
	public Result<IRenderPipeline> GetPipelineForMaterial(
		MaterialInstance material,
		Span<VertexBufferLayout> vertexBuffers,
		IPipelineLayout layout,
		TextureFormat colorFormat,
		TextureFormat depthFormat,
		uint8 sampleCount = 1,
		PipelineVariantFlags variantFlags = .None,
		DepthMode? depthModeOverride = null,
		CompareFunction? depthCompareOverride = null)
	{
		if (material == null)
			return .Err;

		// Get config from material
		var config = material.Material?.PipelineConfig ?? PipelineConfig();

		// Override blend mode from instance if set
		if (material.BlendMode != .Opaque)
			config.BlendMode = material.BlendMode;

		// Override depth mode if specified (e.g., forward pass uses read-only depth after prepass)
		if (depthModeOverride.HasValue)
			config.DepthMode = depthModeOverride.Value;

		// Override depth compare if specified (e.g., LessEqual for forward pass after prepass)
		if (depthCompareOverride.HasValue)
			config.DepthCompare = depthCompareOverride.Value;

		// Build cache key
		let key = BuildKey(config, vertexBuffers, layout, colorFormat, depthFormat, sampleCount, variantFlags);
		let hash = key.GetHashCode();

		// Check cache
		if (mCache.TryGetValue(hash, let cached))
			return .Ok(cached);

		// Create new pipeline
		if (CreatePipeline(config, vertexBuffers, layout, colorFormat, depthFormat, sampleCount, variantFlags) case .Ok(let pipeline))
		{
			mCache[hash] = pipeline;
			return .Ok(pipeline);
		}

		return .Err;
	}

	/// Clears the pipeline cache.
	public void Clear()
	{
		for (let kv in mCache)
			delete kv.value;
		mCache.Clear();
	}

	/// Gets the number of cached pipelines.
	public int Count => mCache.Count;

	// ===== Key Building =====

	private RenderPipelineKey BuildKey(
		PipelineConfig config,
		Span<VertexBufferLayout> vertexBuffers,
		IPipelineLayout layout,
		TextureFormat colorFormat,
		TextureFormat depthFormat,
		uint8 sampleCount,
		PipelineVariantFlags variantFlags)
	{
		RenderPipelineKey key = .();

		// Shader hash (name + flags)
		key.ShaderHash = 17;
		if (!config.ShaderName.IsEmpty)
			key.ShaderHash = key.ShaderHash * 31 + config.ShaderName.GetHashCode();
		key.ShaderHash = key.ShaderHash * 31 + (int)config.ShaderFlags;

		// Render state hash (blend, cull, depth)
		key.RenderStateHash = 17;
		key.RenderStateHash = key.RenderStateHash * 31 + (int)config.BlendMode;
		key.RenderStateHash = key.RenderStateHash * 31 + (int)config.CullMode;
		key.RenderStateHash = key.RenderStateHash * 31 + (int)config.DepthMode;
		key.RenderStateHash = key.RenderStateHash * 31 + (int)config.DepthCompare;

		// Vertex layout hash
		key.VertexLayoutHash = ComputeVertexLayoutHash(vertexBuffers);

		// Render target context
		key.ColorFormat = colorFormat;
		key.DepthFormat = depthFormat;
		key.SampleCount = sampleCount;
		key.LayoutHash = (int)(void*)Internal.UnsafeCastToPtr(layout);
		key.VariantFlags = (uint32)variantFlags;

		return key;
	}

	/// Computes hash of vertex buffer layouts (like old renderer's VertexLayoutHelper.ComputeHash).
	private int ComputeVertexLayoutHash(Span<VertexBufferLayout> layouts)
	{
		int hash = 17;
		for (let layout in layouts)
		{
			hash = hash * 31 + (int)layout.ArrayStride;
			hash = hash * 31 + (int)layout.StepMode;
			for (let attr in layout.Attributes)
			{
				hash = hash * 31 + (int)attr.Format;
				hash = hash * 31 + (int)attr.Offset;
				hash = hash * 31 + (int)attr.ShaderLocation;
			}
		}
		return hash;
	}

	// ===== Pipeline Creation =====

	private Result<IRenderPipeline> CreatePipeline(
		PipelineConfig config,
		Span<VertexBufferLayout> vertexBuffers,
		IPipelineLayout layout,
		TextureFormat colorFormat,
		TextureFormat depthFormat,
		uint8 sampleCount,
		PipelineVariantFlags variantFlags)
	{
		// Build shader flags from config and variant
		var shaderFlags = config.ShaderFlags;
		if (variantFlags.HasFlag(.Instanced))
			shaderFlags |= .Instanced;
		if (variantFlags.HasFlag(.ReceiveShadows))
			shaderFlags |= .ReceiveShadows;

		// Get shader name - fall back to "forward" if not specified
		StringView shaderName = config.ShaderName;
		if (shaderName.IsEmpty)
			shaderName = "forward";

		// Get shaders
		let shaderResult = mShaderSystem.GetShaderPair(shaderName, shaderFlags);
		if (shaderResult case .Err)
		{
			Console.WriteLine(scope $"[RenderPipelineCache] Failed to get shaders: {shaderName} flags={shaderFlags}");
			return .Err;
		}

		let shaderPair = shaderResult.Value;
		let vertShader = shaderPair.vert;
		let fragShader = shaderPair.frag;

		// Build color target state
		ColorTargetState[1] colorTargets = default;
		bool hasColorTarget = !config.DepthOnly && config.ColorTargetCount > 0;

		if (hasColorTarget)
		{
			let blendState = GetBlendState(config.BlendMode);
			if (blendState.HasValue)
				colorTargets[0] = .(colorFormat, blendState.Value);
			else
				colorTargets[0] = .(colorFormat);
		}

		// Build depth stencil state
		DepthStencilState? depthStencil = null;
		if (depthFormat != .Undefined && config.DepthMode != .Disabled)
		{
			var ds = GetDepthStencilState(config);
			if (config.DepthBias != 0 || config.DepthBiasSlopeScale != 0)
			{
				ds.DepthBias = (int32)config.DepthBias;
				ds.DepthBiasSlopeScale = config.DepthBiasSlopeScale;
			}
			depthStencil = ds;
		}

		// Determine cull mode (can be overridden by variant flags for two-pass rendering)
		CullMode cullMode = GetCullMode(config.CullMode);
		if (variantFlags.HasFlag(.BackFaceCull))
			cullMode = .Back;
		else if (variantFlags.HasFlag(.FrontFaceCull))
			cullMode = .Front;

		// Build label
		let label = scope String();
		label.AppendF("Pipeline: {} [{}]", shaderName, config.BlendMode);
		if (variantFlags.HasFlag(.ReceiveShadows))
			label.Append(" Shadows");

		// Build pipeline descriptor
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = label,
			Layout = layout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = hasColorTarget ? .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			} : null,
			Primitive = .()
			{
				Topology = config.Topology,
				FrontFace = config.FrontFace,
				CullMode = cullMode
			},
			DepthStencil = depthStencil,
			Multisample = .()
			{
				Count = sampleCount,
				Mask = uint32.MaxValue
			}
		};

		switch (mDevice.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline):
			return .Ok(pipeline);
		case .Err:
			Console.WriteLine(scope $"[RenderPipelineCache] Failed to create pipeline: {shaderName}");
			return .Err;
		}
	}

	// ===== State Conversion Helpers =====

	/// Converts BlendMode enum to RHI BlendState.
	public static BlendState? GetBlendState(BlendMode mode)
	{
		switch (mode)
		{
		case .Opaque:
			return null; // No blending

		case .AlphaBlend:
			return .AlphaBlend;

		case .Additive:
			return .Additive;

		case .Multiply:
			return .Multiply;

		case .PremultipliedAlpha:
			return .PremultipliedAlpha;
		}
	}

	/// Converts DepthMode enum to RHI DepthStencilState.
	public static DepthStencilState GetDepthStencilState(PipelineConfig config)
	{
		bool depthTest = false;
		bool depthWrite = false;

		switch (config.DepthMode)
		{
		case .Disabled:
			break;

		case .ReadWrite:
			depthTest = true;
			depthWrite = true;

		case .ReadOnly:
			depthTest = true;
			depthWrite = false;

		case .WriteOnly:
			depthTest = false;
			depthWrite = true;
		}

		return .()
		{
			DepthTestEnabled = depthTest,
			DepthWriteEnabled = depthWrite,
			DepthCompare = config.DepthCompare
		};
	}

	/// Converts CullModeConfig enum to RHI CullMode.
	public static CullMode GetCullMode(CullModeConfig mode)
	{
		switch (mode)
		{
		case .None: return .None;
		case .Back: return .Back;
		case .Front: return .Front;
		}
	}
}
