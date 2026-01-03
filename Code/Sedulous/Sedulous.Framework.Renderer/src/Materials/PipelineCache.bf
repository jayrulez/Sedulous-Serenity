namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;

/// Key identifying a unique pipeline configuration.
struct PipelineKey : IEquatable<PipelineKey>, IHashable
{
	/// Material for render state.
	public Material Material;

	/// Vertex buffer layout hash.
	public int VertexLayoutHash;

	/// Render target format.
	public TextureFormat ColorFormat;

	/// Depth format (or Undefined if no depth).
	public TextureFormat DepthFormat;

	/// MSAA sample count.
	public uint32 SampleCount;

	public this(Material material, int vertexLayoutHash, TextureFormat colorFormat, TextureFormat depthFormat = .Depth32Float, uint32 sampleCount = 1)
	{
		Material = material;
		VertexLayoutHash = vertexLayoutHash;
		ColorFormat = colorFormat;
		DepthFormat = depthFormat;
		SampleCount = sampleCount;
	}

	public bool Equals(PipelineKey other)
	{
		return Material == other.Material &&
			VertexLayoutHash == other.VertexLayoutHash &&
			ColorFormat == other.ColorFormat &&
			DepthFormat == other.DepthFormat &&
			SampleCount == other.SampleCount;
	}

	public int GetHashCode()
	{
		int hash = 17;
		if (Material != null)
		{
			hash = hash * 31 + Material.ShaderName.GetHashCode();
			hash = hash * 31 + (int)Material.ShaderFlags;
			hash = hash * 31 + (int)Material.BlendMode;
			hash = hash * 31 + (int)Material.CullMode;
			hash = hash * 31 + (int)Material.DepthMode;
		}
		hash = hash * 31 + VertexLayoutHash;
		hash = hash * 31 + (int)ColorFormat;
		hash = hash * 31 + (int)DepthFormat;
		hash = hash * 31 + (int)SampleCount;
		return hash;
	}
}

/// Cached pipeline with associated layout and bind group layouts.
class CachedPipeline
{
	public IRenderPipeline Pipeline ~ delete _;
	public IPipelineLayout PipelineLayout ~ delete _;
	public IBindGroupLayout[] BindGroupLayouts ~ DeleteContainerAndItems!(_);

	public this(IRenderPipeline pipeline, IPipelineLayout layout, IBindGroupLayout[] bindGroupLayouts)
	{
		Pipeline = pipeline;
		PipelineLayout = layout;
		BindGroupLayouts = bindGroupLayouts;
	}
}

/// Caches render pipelines by configuration to avoid redundant creation.
class PipelineCache
{
	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private Dictionary<int, CachedPipeline> mCache = new .() ~ DeleteDictionaryAndValues!(_);

	public this(IDevice device, ShaderLibrary shaderLibrary)
	{
		mDevice = device;
		mShaderLibrary = shaderLibrary;
	}

	/// Gets or creates a pipeline for the given configuration.
	public Result<CachedPipeline> GetPipeline(PipelineKey key, Span<VertexBufferLayout> vertexBuffers)
	{
		let hash = key.GetHashCode();

		// Check cache
		if (mCache.TryGetValue(hash, let cached))
			return .Ok(cached);

		// Create new pipeline
		if (CreatePipeline(key, vertexBuffers) case .Ok(let pipeline))
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
		{
			delete kv.value;
		}
		mCache.Clear();
	}

	/// Gets the number of cached pipelines.
	public int Count => mCache.Count;

	// ===== Internal Methods =====

	private Result<CachedPipeline> CreatePipeline(PipelineKey key, Span<VertexBufferLayout> vertexBuffers)
	{
		let material = key.Material;
		if (material == null)
			return .Err;

		// Get shaders
		let shaderResult = mShaderLibrary.GetShaderPair(material.ShaderName, material.ShaderFlags);
		if (shaderResult case .Err)
		{
			Console.WriteLine(scope $"[PipelineCache] Failed to get shaders for: {material.ShaderName}");
			return .Err;
		}

		let (vertShader, fragShader) = shaderResult.Value;

		// Create bind group layouts
		// For now, use a simple layout: binding 0 = camera UBO, binding 1 = material UBO
		// Textures and samplers use higher bindings
		IBindGroupLayout[] bindGroupLayouts = null;
		IPipelineLayout pipelineLayout = null;

		// Create a default bind group layout
		if (CreateDefaultBindGroupLayout() case .Ok(let layout))
		{
			bindGroupLayouts = new IBindGroupLayout[](layout);

			IBindGroupLayout[1] layouts = .(layout);
			PipelineLayoutDescriptor layoutDesc = .(layouts);
			if (mDevice.CreatePipelineLayout(&layoutDesc) case .Ok(let pl))
			{
				pipelineLayout = pl;
			}
			else
			{
				delete layout;
				delete bindGroupLayouts;
				return .Err;
			}
		}
		else
		{
			return .Err;
		}

		// Color target state
		ColorTargetState[1] colorTargets;
		if (let blend = material.GetBlendState())
		{
			colorTargets = .(.(key.ColorFormat, blend));
		}
		else
		{
			colorTargets = .(.(key.ColorFormat));
		}

		// Depth stencil state
		DepthStencilState? depthStencil = null;
		if (key.DepthFormat != .RGBA8Unorm) // Using RGBA8Unorm as "no depth" indicator
		{
			depthStencil = material.GetDepthStencilState();
		}

		// Build pipeline descriptor
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = pipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = material.GetPrimitiveState(),
			DepthStencil = depthStencil,
			Multisample = .()
			{
				Count = key.SampleCount,
				Mask = uint32.MaxValue,
				AlphaToCoverageEnabled = false
			}
		};

		if (mDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
		{
			return .Ok(new CachedPipeline(pipeline, pipelineLayout, bindGroupLayouts));
		}

		// Cleanup on failure
		delete pipelineLayout;
		DeleteContainerAndItems!(bindGroupLayouts);
		return .Err;
	}

	private Result<IBindGroupLayout> CreateDefaultBindGroupLayout()
	{
		// Default layout using HLSL register numbers:
		// RHI internally shifts: buffers=N, textures=N+1000, samplers=N+3000
		// b0: Camera uniform buffer (vertex + fragment)
		// b1: Material uniform buffer (fragment)
		// t0: Albedo texture (fragment)
		// s0: Material sampler (fragment)
		BindGroupLayoutEntry[4] entries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment), // b0 - Camera
			BindGroupLayoutEntry.UniformBuffer(1, .Fragment),           // b1 - Material
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),          // t0 - Albedo texture
			BindGroupLayoutEntry.Sampler(0, .Fragment)                  // s0 - Material sampler
		);

		BindGroupLayoutDescriptor desc = .(entries);
		if (mDevice.CreateBindGroupLayout(&desc) case .Ok(let layout))
			return .Ok(layout);

		return .Err;
	}
}

/// Helper to compute vertex layout hash.
static class VertexLayoutHelper
{
	public static int ComputeHash(Span<VertexBufferLayout> layouts)
	{
		int hash = 17;
		for (let layout in layouts)
		{
			hash = hash * 31 + (int)layout.ArrayStride;
			for (let attr in layout.Attributes)
			{
				hash = hash * 31 + (int)attr.Format;
				hash = hash * 31 + (int)attr.Offset;
				hash = hash * 31 + (int)attr.ShaderLocation;
			}
		}
		return hash;
	}
}
