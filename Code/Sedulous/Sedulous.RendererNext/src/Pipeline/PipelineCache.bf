namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;

/// Caches render pipelines by configuration key.
/// Eliminates duplicate pipelines for different depth/blend combinations.
class PipelineCache
{
	/// Cached pipeline entry with owned string key.
	private struct CacheEntry
	{
		public String ShaderName;
		public IRenderPipeline Pipeline;
	}

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private Dictionary<int, CacheEntry> mPipelines = new .() ~ {
		for (let kv in _)
		{
			delete kv.value.ShaderName;
			delete kv.value.Pipeline;
		}
		delete _;
	};

	private Dictionary<int, IBindGroupLayout> mBindGroupLayouts = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<int, IPipelineLayout> mPipelineLayouts = new .() ~ DeleteDictionaryAndValues!(_);

	public this(IDevice device, ShaderLibrary shaderLibrary)
	{
		mDevice = device;
		mShaderLibrary = shaderLibrary;
	}

	/// Gets or creates a pipeline for the given configuration.
	public Result<IRenderPipeline> GetPipeline(PipelineKey key, VertexBufferLayout[] vertexLayouts, IBindGroupLayout[] bindGroupLayouts)
	{
		let hash = key.GetHashCode();

		// Check cache
		if (mPipelines.TryGetValue(hash, let entry))
			return .Ok(entry.Pipeline);

		// Create new pipeline
		if (CreatePipeline(key, vertexLayouts, bindGroupLayouts) case .Ok(let pipeline))
		{
			CacheEntry newEntry;
			newEntry.ShaderName = new String(key.ShaderName);
			newEntry.Pipeline = pipeline;
			mPipelines[hash] = newEntry;
			return .Ok(pipeline);
		}

		return .Err;
	}

	/// Gets or creates a pipeline layout.
	public Result<IPipelineLayout> GetPipelineLayout(Span<IBindGroupLayout> layouts)
	{
		// Generate hash from layouts using object references
		int hash = 0;
		for (let layout in layouts)
			hash = hash * 31 + Internal.UnsafeCastToPtr(layout).GetHashCode();

		if (mPipelineLayouts.TryGetValue(hash, let existing))
			return .Ok(existing);

		PipelineLayoutDescriptor desc = .(layouts);
		if (mDevice.CreatePipelineLayout(&desc) case .Ok(let layout))
		{
			mPipelineLayouts[hash] = layout;
			return .Ok(layout);
		}

		return .Err;
	}

	/// Creates a new pipeline for the given configuration.
	private Result<IRenderPipeline> CreatePipeline(PipelineKey key, VertexBufferLayout[] vertexLayouts, IBindGroupLayout[] bindGroupLayouts)
	{
		// Load shaders
		let vertResult = mShaderLibrary.GetShader(key.ShaderName, .Vertex, key.Flags);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Value;

		let fragResult = mShaderLibrary.GetShader(key.ShaderName, .Fragment, key.Flags);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Value;

		// Create pipeline layout
		IPipelineLayout pipelineLayout;
		if (bindGroupLayouts.Count > 0)
		{
			PipelineLayoutDescriptor layoutDesc = .(bindGroupLayouts);
			if (mDevice.CreatePipelineLayout(&layoutDesc) case .Ok(let layout))
				pipelineLayout = layout;
			else
				return .Err;
		}
		else
		{
			pipelineLayout = null;
		}

		// Build color target with blend state
		ColorTargetState[1] colorTargets = .(CreateColorTarget(key.ColorFormat, key.BlendMode));

		// Build depth state
		DepthStencilState depthState = key.DepthConfig.ToRHI();

		// Create pipeline descriptor
		RenderPipelineDescriptor desc = .()
		{
			Layout = pipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexLayouts
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = key.Topology,
				FrontFace = .CCW,
				CullMode = key.CullMode
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = key.SampleCount,
				Mask = uint32.MaxValue
			}
		};

		if (mDevice.CreateRenderPipeline(&desc) case .Ok(let pipeline))
		{
			// Clean up the pipeline layout we created (pipeline holds reference)
			if (pipelineLayout != null)
				delete pipelineLayout;
			return .Ok(pipeline);
		}

		if (pipelineLayout != null)
			delete pipelineLayout;
		return .Err;
	}

	/// Creates a color target state with the specified blend mode.
	private static ColorTargetState CreateColorTarget(TextureFormat format, BlendMode blendMode)
	{
		ColorTargetState state = .(format);

		switch (blendMode)
		{
		case .Opaque:
			state.Blend = null;

		case .AlphaBlend:
			state.Blend = .()
			{
				Color = .()
				{
					SrcFactor = .SrcAlpha,
					DstFactor = .OneMinusSrcAlpha,
					Operation = .Add
				},
				Alpha = .()
				{
					SrcFactor = .One,
					DstFactor = .OneMinusSrcAlpha,
					Operation = .Add
				}
			};

		case .Additive:
			state.Blend = .()
			{
				Color = .()
				{
					SrcFactor = .SrcAlpha,
					DstFactor = .One,
					Operation = .Add
				},
				Alpha = .()
				{
					SrcFactor = .One,
					DstFactor = .One,
					Operation = .Add
				}
			};

		case .Multiply:
			state.Blend = .()
			{
				Color = .()
				{
					SrcFactor = .Dst,
					DstFactor = .Zero,
					Operation = .Add
				},
				Alpha = .()
				{
					SrcFactor = .DstAlpha,
					DstFactor = .Zero,
					Operation = .Add
				}
			};

		case .Premultiplied:
			state.Blend = .()
			{
				Color = .()
				{
					SrcFactor = .One,
					DstFactor = .OneMinusSrcAlpha,
					Operation = .Add
				},
				Alpha = .()
				{
					SrcFactor = .One,
					DstFactor = .OneMinusSrcAlpha,
					Operation = .Add
				}
			};
		}

		return state;
	}

	/// Clears all cached pipelines.
	public void Clear()
	{
		for (let kv in mPipelines)
		{
			delete kv.value.ShaderName;
			delete kv.value.Pipeline;
		}
		mPipelines.Clear();

		DeleteDictionaryAndValues!(mBindGroupLayouts);
		mBindGroupLayouts = new .();

		DeleteDictionaryAndValues!(mPipelineLayouts);
		mPipelineLayouts = new .();
	}

	/// Number of cached pipelines.
	public int32 CachedPipelineCount => (int32)mPipelines.Count;
}
