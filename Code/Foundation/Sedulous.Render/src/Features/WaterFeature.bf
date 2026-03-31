namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// Water uniform data matching water.vert/frag.hlsl cbuffer (space1, b0).
[CRepr]
struct WaterUniforms
{
	public Vector3 WaterCenter;
	public float WaveSpeed;
	public Vector4 WaterColor;
	public Vector2 WaterSize;
	public float WaveScale;
	public float NormalStrength;
	public float FresnelR0;
	public float RefractionStrength;
	public float SpecularPower;
	public float MaxVisibleDepth;
	public float FoamDepthThreshold;
	public float FoamIntensity;
	public float Roughness;
	public float _Pad0;
	public Vector2 FlowDirection;
	public Vector2 _Pad1;

	public const uint64 Size = 96; // 6 x float4
}

/// Water render feature.
/// Renders animated water planes with refraction, Fresnel reflection, depth absorption, and foam.
/// Integrates into the forward+ PBR pipeline with full lighting, shadows, IBL, and probes.
public class WaterFeature : RenderFeatureBase
{
	// Grid mesh (flat plane, shared by all water planes)
	const int32 GridResolution = 32;
	const int32 GridVertexCount = (GridResolution + 1) * (GridResolution + 1);
	const int32 GridIndexCount = GridResolution * GridResolution * 6;

	private IBuffer mGridVertexBuffer;
	private IBuffer mGridIndexBuffer;

	// Per-frame water uniform buffers
	private IBuffer[RenderConfig.FrameBufferCount] mWaterUniformBuffers;

	// Per-frame object uniform buffers (identity, required by scene bind group layout)
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers;
	private const uint64 ObjectUniformAlignment = 256;
	private const uint64 AlignedObjectUniformSize = ((ObjectUniforms.Size + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

	// Water bind group layout (space1)
	private IBindGroupLayout mWaterBindGroupLayout;

	// Per-water bind groups (cached with generation)
	private List<WaterBindGroupEntry> mPerWaterBindGroups = new .() ~ delete _;

	// Scene bind groups (space0, own copy)
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroups;
	private bool[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupShadowState;
	private bool[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupIBLState;
	private uint32[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupProbeGeneration;

	// Copy pass resources
	private IBindGroupLayout mCopyBindGroupLayout;
	private IRenderPipeline mCopyPipeline;
	private IPipelineLayout mCopyPipelineLayout;
	private ISampler mCopySampler;
	private IBindGroup[RenderConfig.FrameBufferCount] mCopyBindGroups;

	// Water pipeline
	private IRenderPipeline mWaterPipeline;
	private IRenderPipeline mWaterPipelineNoShadows;
	private IPipelineLayout mWaterPipelineLayout;

	// Samplers
	private ISampler mWaterSampler;   // linear wrap (normal map, foam)
	private ISampler mSceneSampler;   // linear clamp (refraction, depth)

	// Scene bind group layout (borrowed from ForwardOpaqueFeature, don't delete)

	// Limits
	const int32 MaxWaters = 8;

	// Texture generation counter
	private uint32 mTextureGeneration = 0;

	// Cached scene color copy view (stored per frame for bind group update)
	private ITextureView[RenderConfig.FrameBufferCount] mCachedSceneColorCopyViews;
	private ITextureView[RenderConfig.FrameBufferCount] mCachedSceneDepthViews;

	/// Feature name.
	public override StringView Name => "Water";

	/// Depends on ForwardOpaque and Terrain (water renders after opaque + terrain, before transparent).
	/// Terrain dependency is optional — ignored if TerrainFeature is not registered.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
		outDependencies.Add("Terrain");
	}

	protected override Result<void> OnInitialize(InitContext initCtx)
	{
		if (CreateGridMesh() case .Err)
			return .Err;

		if (CreateSamplers() case .Err)
			return .Err;

		if (CreateCopyResources() case .Err)
			return .Err;

		if (CreateWaterBindGroupLayout() case .Err)
			return .Err;



		if (CreateWaterPipelineLayout() case .Err)
			return .Err;

		if (CreateWaterPipeline() case .Err)
			return .Err;

		if (CreatePerFrameBuffers() case .Err)
			return .Err;

		if (CreateObjectUniformBuffers() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateGridMesh()
	{
		int32 vertexCount = GridVertexCount;
		uint64 vertexSize = (uint64)(vertexCount * 8); // float2 per vertex

		BufferDesc vertDesc = .()
		{
			Label = "Water Grid Vertices",
			Size = vertexSize,
			Usage = .Vertex,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(vertDesc))
		{
		case .Ok(let buf): mGridVertexBuffer = buf;
		case .Err: return .Err;
		}

		if (let ptr = mGridVertexBuffer.Map())
		{
			float* fptr = (float*)ptr;
			for (int32 z = 0; z <= GridResolution; z++)
			{
				for (int32 x = 0; x <= GridResolution; x++)
				{
					*fptr++ = (float)x / (float)GridResolution;
					*fptr++ = (float)z / (float)GridResolution;
				}
			}
			mGridVertexBuffer.Unmap();
		}

		uint64 indexSize = (uint64)(GridIndexCount * 2); // uint16 indices

		BufferDesc idxDesc = .()
		{
			Label = "Water Grid Indices",
			Size = indexSize,
			Usage = .Index,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(idxDesc))
		{
		case .Ok(let buf): mGridIndexBuffer = buf;
		case .Err: return .Err;
		}

		if (let ptr = mGridIndexBuffer.Map())
		{
			uint16* iptr = (uint16*)ptr;
			for (int32 z = 0; z < GridResolution; z++)
			{
				for (int32 x = 0; x < GridResolution; x++)
				{
					let stride = GridResolution + 1;
					uint16 tl = (uint16)(z * stride + x);
					uint16 tr = (uint16)(z * stride + x + 1);
					uint16 bl = (uint16)((z + 1) * stride + x);
					uint16 br = (uint16)((z + 1) * stride + x + 1);

					*iptr++ = tl;
					*iptr++ = bl;
					*iptr++ = tr;
					*iptr++ = tr;
					*iptr++ = bl;
					*iptr++ = br;
				}
			}
			mGridIndexBuffer.Unmap();
		}

		return .Ok;
	}

	private Result<void> CreateSamplers()
	{
		// Linear wrap sampler (for normal map, foam texture)
		{
			SamplerDesc desc = .();
			desc.MinFilter = .Linear;
			desc.MagFilter = .Linear;
			desc.MipmapFilter = .Linear;
			desc.AddressU = .Repeat;
			desc.AddressV = .Repeat;
			desc.AddressW = .Repeat;

			switch (Renderer.Device.CreateSampler(desc))
			{
			case .Ok(let s): mWaterSampler = s;
			case .Err: return .Err;
			}
		}

		// Linear clamp sampler (for scene color copy, depth)
		{
			SamplerDesc desc = .();
			desc.MinFilter = .Linear;
			desc.MagFilter = .Linear;
			desc.MipmapFilter = .Linear;
			desc.AddressU = .ClampToEdge;
			desc.AddressV = .ClampToEdge;
			desc.AddressW = .ClampToEdge;

			switch (Renderer.Device.CreateSampler(desc))
			{
			case .Ok(let s): mSceneSampler = s;
			case .Err: return .Err;
			}
		}

		// Copy pass sampler (linear clamp)
		{
			SamplerDesc desc = .();
			desc.MinFilter = .Linear;
			desc.MagFilter = .Linear;
			desc.MipmapFilter = .Linear;
			desc.AddressU = .ClampToEdge;
			desc.AddressV = .ClampToEdge;
			desc.AddressW = .ClampToEdge;

			switch (Renderer.Device.CreateSampler(desc))
			{
			case .Ok(let s): mCopySampler = s;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private Result<void> CreateCopyResources()
	{
		// Copy bind group layout: t0=SceneColor, s0=Sampler
		BindGroupLayoutEntry[2] copyEntries = .(
			.SampledTexture(0, .Fragment),
			.Sampler(0, .Fragment)
		);

		BindGroupLayoutDesc copyLayoutDesc = .()
		{
			Label = "Water Copy BindGroup Layout",
			Entries = copyEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(copyLayoutDesc))
		{
		case .Ok(let layout): mCopyBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Copy pipeline layout
		IBindGroupLayout[1] copyLayouts = .(mCopyBindGroupLayout);
		PipelineLayoutDesc copyPLDesc = .(copyLayouts);

		switch (Renderer.Device.CreatePipelineLayout(copyPLDesc))
		{
		case .Ok(let layout): mCopyPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Copy pipeline
		if (Renderer.ShaderSystem == null)
			return .Err;

		let copyVertResult = Renderer.ShaderSystem.GetShader("water_copy", .Vertex);
		let copyFragResult = Renderer.ShaderSystem.GetShader("water_copy", .Fragment);

		if (copyVertResult case .Err)
			return .Err;
		if (copyFragResult case .Err)
			return .Err;

		let copyVert = copyVertResult.Value;
		let copyFrag = copyFragResult.Value;

		ColorTargetState[1] copyColorTargets = .(.(.RGBA16Float));

		RenderPipelineDesc copyPipelineDesc = .()
		{
			Label = "Water Copy Pipeline",
			Layout = mCopyPipelineLayout,
			Vertex = .() { Shader = .(copyVert.Module, "main"), Buffers = default },
			Fragment = .() { Shader = .(copyFrag.Module, "main"), Targets = copyColorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = null,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		switch (Renderer.Device.CreateRenderPipeline(copyPipelineDesc))
		{
		case .Ok(let pipeline): mCopyPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateWaterBindGroupLayout()
	{
		// Water bind group (space1):
		// b0: WaterUniforms
		// t0: NormalMap
		// t1: FoamTexture
		// t2: SceneColorCopy
		// t3: SceneDepth
		// s0: WaterSampler (linear wrap)
		// s1: SceneSampler (linear clamp)
		BindGroupLayoutEntry[7] entries = .(
			.UniformBuffer(0, .Vertex | .Fragment),     // b0 space1: WaterUniforms
			.SampledTexture(0, .Vertex | .Fragment),    // t0 space1: NormalMap
			.SampledTexture(1, .Fragment),               // t1 space1: FoamTexture
			.SampledTexture(2, .Fragment),               // t2 space1: SceneColorCopy
			.SampledTexture(3, .Fragment),               // t3 space1: SceneDepth
			.Sampler(0, .Vertex | .Fragment),            // s0 space1: WaterSampler
			.Sampler(1, .Fragment)                       // s1 space1: SceneSampler
		);

		BindGroupLayoutDesc layoutDesc = .()
		{
			Label = "Water BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mWaterBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateWaterPipelineLayout()
	{
		IBindGroupLayout[2] layouts = .(Renderer.SharedLayouts.SceneLayout, mWaterBindGroupLayout);
		PipelineLayoutDesc plDesc = .(layouts);

		switch (Renderer.Device.CreatePipelineLayout(plDesc))
		{
		case .Ok(let layout): mWaterPipelineLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateWaterPipeline()
	{
		if (Renderer.ShaderSystem == null)
			return .Err;

		let shaderResult = Renderer.ShaderSystem.GetShaderPair("water", .ReceiveShadows);
		if (shaderResult case .Err)
			return .Err;

		let (vertShader, fragShader) = shaderResult.Value;

		VertexAttribute[1] meshAttrs = .(
			.(VertexFormat.Float2, 0, 0)
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.(8, meshAttrs, .Vertex)
		);

		ColorTargetState[2] colorTargets = .(
			.(.RGBA16Float),    // SceneColor
			.(.RGBA8Unorm)      // GBuffer
		);

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "Water Pipeline",
			Layout = mWaterPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = Span<ColorTargetState>(&colorTargets[0], 2)
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None   // Water visible from both sides
			},
			DepthStencil = null,  // No depth attachment; fragment shader discards via depth comparison
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(pipelineDesc))
		{
		case .Ok(let pipeline): mWaterPipeline = pipeline;
		case .Err: return .Err;
		}

		// No-shadows variant
		let shaderResultNoShadow = Renderer.ShaderSystem.GetShaderPair("water", .None);
		if (shaderResultNoShadow case .Ok(let pair))
		{
			let (vertNS, fragNS) = pair;

			RenderPipelineDesc noShadowDesc = pipelineDesc;
			noShadowDesc.Label = "Water Pipeline (No Shadows)";
			noShadowDesc.Vertex.Shader = .(vertNS.Module, "main");
			noShadowDesc.Fragment = .()
			{
				Shader = .(fragNS.Module, "main"),
				Targets = Span<ColorTargetState>(&colorTargets[0], 2)
			};

			switch (Renderer.Device.CreateRenderPipeline(noShadowDesc))
			{
			case .Ok(let pipeline): mWaterPipelineNoShadows = pipeline;
			case .Err:
			}
		}

		return .Ok;
	}

	private Result<void> CreatePerFrameBuffers()
	{
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc uniformDesc = .()
			{
				Label = "Water Uniforms",
				Size = WaterUniforms.Size * MaxWaters,
				Usage = .Uniform,
				Memory = .CpuToGpu
			};

			switch (Renderer.Device.CreateBuffer(uniformDesc))
			{
			case .Ok(let buf): mWaterUniformBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private Result<void> CreateObjectUniformBuffers()
	{
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc desc = .()
			{
				Label = "Water Object Uniforms",
				Size = AlignedObjectUniformSize,
				Usage = .Uniform,
				Memory = .CpuToGpu
			};

			switch (Renderer.Device.CreateBuffer(desc))
			{
			case .Ok(let buf): mObjectUniformBuffers[i] = buf;
			case .Err: return .Err;
			}

			if (let ptr = mObjectUniformBuffers[i].Map())
			{
				ObjectUniforms objUniforms = .()
				{
					WorldMatrix = .Identity,
					PrevWorldMatrix = .Identity,
					ObjectID = 0,
					MaterialID = 0,
					_Padding = .(0, 0)
				};
				Internal.MemCpy(ptr, &objUniforms, ObjectUniforms.Size);
				mObjectUniformBuffers[i].Unmap();
			}
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		let device = Renderer.Device;

		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			device.DestroyBuffer(ref mWaterUniformBuffers[i]);
			device.DestroyBuffer(ref mObjectUniformBuffers[i]);
			device.DestroyBindGroup(ref mCopyBindGroups[i]);
		}

		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mSceneBindGroups[i] != null)
				device.DestroyBindGroup(ref mSceneBindGroups[i]);
		}

		for (var entry in ref mPerWaterBindGroups)
		{
			if (entry.BindGroup != null)
				device.DestroyBindGroup(ref entry.BindGroup);
		}
		mPerWaterBindGroups.Clear();

		device.DestroyBuffer(ref mGridVertexBuffer);
		device.DestroyBuffer(ref mGridIndexBuffer);
		device.DestroyBindGroupLayout(ref mWaterBindGroupLayout);
		device.DestroyBindGroupLayout(ref mCopyBindGroupLayout);
		device.DestroyRenderPipeline(ref mCopyPipeline);
		device.DestroyPipelineLayout(ref mCopyPipelineLayout);
		device.DestroySampler(ref mCopySampler);
		device.DestroyRenderPipeline(ref mWaterPipeline);
		device.DestroyRenderPipeline(ref mWaterPipelineNoShadows);
		device.DestroyPipelineLayout(ref mWaterPipelineLayout);
		device.DestroySampler(ref mWaterSampler);
		device.DestroySampler(ref mSceneSampler);
	}

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderWorld world)
	{
		if (world.WaterCount == 0)
			return;

		let depthHandle = graph.GetResource("SceneDepth");
		let colorHandle = graph.GetResource("SceneColor");
		let gbufferHandle = graph.GetResource("SceneNormalRoughness");

		if (!depthHandle.IsValid || !colorHandle.IsValid || !gbufferHandle.IsValid)
			return;

		let frameIndex = view.FrameIndex;
		let bindGroupIndex = view.GetBindGroupIndex();

		// Upload water uniform data
		PrepareWaterData(world, frameIndex);

		// Create scene bind group
		CreateSceneBindGroup(frameIndex, bindGroupIndex);

		// Create transient copy of SceneColor for refraction sampling
		let copyDesc = RGTextureDesc(.RGBA16Float, view.Width, view.Height) { Usage = .Sampled | .RenderTarget };
		let copyHandle = graph.CreateTransient("WaterSceneColorCopy", copyDesc);

		// Copy pass reference
		RenderGraph graphRef = graph;
		RGHandle colorCopy = colorHandle;
		RGHandle copyCopy = copyHandle;

		// Pass 1: Copy SceneColor to transient texture
		graph.AddRenderPass("Water_CopyScene", scope (builder) => {
				builder.ReadTexture(colorHandle);
				builder.SetColorTarget(0, copyHandle, .DontCare, .Store);
				builder.NeverCull();
				builder.SetExecute(new [=] (encoder) => {
					let sceneColorView = graphRef.GetTextureView(colorCopy);
					ExecuteCopyPass(encoder, view, sceneColorView, frameIndex);
				});
			});

		// We need the depth view for the water bind group
		RGHandle depthCopy = depthHandle;

		// Pass 2: Render water geometry
		graph.AddRenderPass("Water", scope (builder) => {
				builder.ReadTexture(copyHandle);
				builder.ReadTexture(depthHandle);
				builder.SetColorTarget(0, colorHandle, .Load, .Store);
				builder.SetColorTarget(1, gbufferHandle, .Load, .Store);
				builder.NeverCull();
				builder.SetExecute(new [=] (encoder) => {
					let sceneColorCopyView = graphRef.GetTextureView(copyCopy);
					let depthView = graphRef.GetDepthOnlyTextureView(depthCopy);
					ExecuteWaterPass(encoder, world, view, frameIndex, bindGroupIndex, sceneColorCopyView, depthView);
				});
			});
	}

	private void PrepareWaterData(RenderWorld world, int32 frameIndex)
	{
		let uniformBuffer = mWaterUniformBuffers[frameIndex];
		if (uniformBuffer == null)
			return;

		let uniformPtr = uniformBuffer.Map();
		if (uniformPtr == null)
			return;

		uint8* uniforms = (uint8*)uniformPtr;
		int32 waterIndex = 0;

		world.ForEachWater(scope [&] (handle, proxy) =>
		{
			if (!proxy.IsActive || waterIndex >= MaxWaters)
				return;

			WaterUniforms waterUniforms = .()
			{
				WaterCenter = proxy.Position,
				WaveSpeed = proxy.WaveSpeed,
				WaterColor = proxy.WaterColor,
				WaterSize = proxy.Size,
				WaveScale = proxy.WaveScale,
				NormalStrength = proxy.NormalStrength,
				FresnelR0 = proxy.FresnelR0,
				RefractionStrength = proxy.RefractionStrength,
				SpecularPower = proxy.SpecularPower,
				MaxVisibleDepth = proxy.MaxVisibleDepth,
				FoamDepthThreshold = proxy.FoamDepthThreshold,
				FoamIntensity = proxy.FoamIntensity,
				Roughness = proxy.Roughness,
				_Pad0 = 0,
				FlowDirection = proxy.FlowDirection,
				_Pad1 = default
			};
			Internal.MemCpy(uniforms + waterIndex * WaterUniforms.Size, &waterUniforms, WaterUniforms.Size);

			waterIndex++;
		});

		uniformBuffer.Unmap();
	}

	private void ExecuteCopyPass(IRenderPassEncoder encoder, ViewContext view, ITextureView sceneColorView, int32 frameIndex)
	{
		if (mCopyPipeline == null || sceneColorView == null)
			return;

		// Recreate copy bind group if needed (SceneColor view may change per frame)
		if (mCopyBindGroups[frameIndex] != null)
			Renderer.Device.DestroyBindGroup(ref mCopyBindGroups[frameIndex]);

		BindGroupEntry[2] entries = .(
			BindGroupEntry.Texture(/*0,*/sceneColorView),
			BindGroupEntry.Sampler(/*0,*/mCopySampler)
		);

		BindGroupDesc bgDesc = .()
		{
			Label = "Water Copy BindGroup",
			Layout = mCopyBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(bgDesc) case .Ok(let bg))
		{
			mCopyBindGroups[frameIndex] = bg;
		}
		else
		{
			return;
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, view.Width, view.Height);
		encoder.SetPipeline(mCopyPipeline);
		encoder.SetBindGroup(0, mCopyBindGroups[frameIndex], default);
		encoder.Draw(3, 1, 0, 0); // Fullscreen triangle
		Renderer.Stats.DrawCalls++;
	}

	private void ExecuteWaterPass(IRenderPassEncoder encoder, RenderWorld world, ViewContext view, int32 frameIndex, int32 bindGroupIndex,
		ITextureView sceneColorCopyView, ITextureView depthView)
	{
		if (sceneColorCopyView == null || depthView == null)
			return;

		let shadowsActive = Renderer.ShadowRenderer?.ShadowPassesActive ?? false;
		let pipeline = (shadowsActive && mWaterPipeline != null) ? mWaterPipeline :
			(mWaterPipelineNoShadows != null) ? mWaterPipelineNoShadows : mWaterPipeline;

		if (pipeline == null)
			return;

		let sceneBindGroup = mSceneBindGroups[bindGroupIndex];
		if (sceneBindGroup == null)
			return;

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, view.Width, view.Height);
		encoder.SetPipeline(pipeline);

		uint32[1] dynamicOffsets = .(0);
		encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);

		encoder.SetVertexBuffer(0, mGridVertexBuffer, 0);
		encoder.SetIndexBuffer(mGridIndexBuffer, .UInt16);

		// Draw each active water plane
		int32 waterIndex = 0;
		world.ForEachWater(scope [&] (handle, proxy) =>
		{
			if (!proxy.IsActive || waterIndex >= MaxWaters)
				return;
			if (proxy.NormalMapView == null)
				return;

			// Create/update water bind group for this water
			let waterBindGroup = GetOrCreateWaterBindGroup(handle, ref proxy, frameIndex, waterIndex, sceneColorCopyView, depthView);
			if (waterBindGroup == null)
			{
				waterIndex++;
				return;
			}

			encoder.SetBindGroup(1, waterBindGroup, default);
			encoder.DrawIndexed((uint32)GridIndexCount, 1, 0, 0, 0);
			Renderer.Stats.DrawCalls++;

			waterIndex++;
		});
	}

	private IBindGroup GetOrCreateWaterBindGroup(ProxyHandle handle, ref WaterProxy proxy, int32 frameIndex, int32 waterIndex,
		ITextureView sceneColorCopyView, ITextureView depthView)
	{
		// Always recreate because scene copy/depth views change every frame
		WaterBindGroupEntry* existing = null;
		for (var entry in ref mPerWaterBindGroups)
		{
			if (entry.Handle == handle && entry.FrameIndex == frameIndex)
			{
				existing = &entry;
				break;
			}
		}

		// Delete old bind group
		if (existing != null && existing.BindGroup != null)
			Renderer.Device.DestroyBindGroup(ref existing.BindGroup);

		let uniformBuffer = mWaterUniformBuffers[frameIndex];
		if (uniformBuffer == null)
			return null;

		// Use foam texture if available, fall back to normal map
		ITextureView foamView = proxy.FoamTextureView;
		if (foamView == null)
			foamView = proxy.NormalMapView;

		BindGroupEntry[7] entries = .();
		uint64 uniformOffset = (uint64)waterIndex * WaterUniforms.Size;
		entries[0] = BindGroupEntry.Buffer(/*0,*/uniformBuffer, uniformOffset, WaterUniforms.Size);
		entries[1] = BindGroupEntry.Texture(/*0,*/proxy.NormalMapView);
		entries[2] = BindGroupEntry.Texture(/*1,*/foamView);
		entries[3] = BindGroupEntry.Texture(/*2,*/sceneColorCopyView);
		entries[4] = BindGroupEntry.Texture(/*3,*/depthView);
		entries[5] = BindGroupEntry.Sampler(/*0,*/mWaterSampler);
		entries[6] = BindGroupEntry.Sampler(/*1,*/mSceneSampler);

		BindGroupDesc bgDesc = .()
		{
			Label = "Water BindGroup",
			Layout = mWaterBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(bgDesc) case .Ok(let bg))
		{
			if (existing != null)
			{
				existing.BindGroup = bg;
				existing.Generation = mTextureGeneration;
			}
			else
			{
				mPerWaterBindGroups.Add(.()
				{
					Handle = handle,
					BindGroup = bg,
					Generation = mTextureGeneration,
					FrameIndex = frameIndex
				});
			}
			return bg;
		}

		return null;
	}

	/// Call this when water proxy textures change to trigger bind group recreation.
	public void InvalidateBindGroups()
	{
		mTextureGeneration++;
	}

	private void CreateSceneBindGroup(int32 frameIndex, int32 bindGroupIndex)
	{
		let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		if (opaqueFeature == null)
			return;

		let shadowsEnabled = Renderer.ShadowRenderer.ShadowPassesActive;

		let skyFeature = Renderer.GetFeature<SkyFeature>();
		let hasRealIBL = skyFeature?.IrradianceMapView != null;

		let probeSystem = Renderer.ProbeSystem;
		let probeGeneration = probeSystem?.Generation ?? 0;

		if (mSceneBindGroups[bindGroupIndex] != null)
		{
			if (mSceneBindGroupShadowState[bindGroupIndex] == shadowsEnabled &&
				mSceneBindGroupIBLState[bindGroupIndex] == hasRealIBL &&
				mSceneBindGroupProbeGeneration[bindGroupIndex] == probeGeneration)
				return;

			Renderer.Device.DestroyBindGroup(ref mSceneBindGroups[bindGroupIndex]);
		}

		// Create via shared helper (uses shared layout, RenderSystem subsystems)
		let bg = Renderer.SharedLayouts.CreateSceneBindGroup(frameIndex, mObjectUniformBuffers[frameIndex], probeSystem);
		if (bg != null)
		{
			mSceneBindGroups[bindGroupIndex] = bg;
			mSceneBindGroupShadowState[bindGroupIndex] = shadowsEnabled;
			mSceneBindGroupIBLState[bindGroupIndex] = hasRealIBL;
			mSceneBindGroupProbeGeneration[bindGroupIndex] = probeGeneration;
		}
	}

	/// Cached bind group per water proxy.
	private struct WaterBindGroupEntry
	{
		public ProxyHandle Handle;
		public IBindGroup BindGroup;
		public uint32 Generation;
		public int32 FrameIndex;
	}
}
