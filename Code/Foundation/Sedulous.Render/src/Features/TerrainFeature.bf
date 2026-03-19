namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.RenderGraph;

/// Per-patch instance data uploaded to the GPU.
[CRepr]
struct TerrainPatchInstance
{
	public float OffsetX;
	public float OffsetZ;
	public float ScaleX;
	public float ScaleZ;

	public const uint64 Size = 16;
}

/// Terrain uniform data matching terrain.vert/frag.hlsl cbuffer.
[CRepr]
struct TerrainUniforms
{
	public Vector3 TerrainOrigin;
	public float HeightScale;
	public Vector2 TerrainWorldSize;
	public Vector2 HeightmapSize;
	public Vector4 LayerScales;
	public float Roughness;
	public float Metallic;
	public float[2] _Pad;

	public const uint64 Size = 64;
}

/// Terrain render feature.
/// Renders heightmap-based terrain as a chunked grid of patches with splatmap blending.
/// Integrates into the forward+ PBR pipeline with full lighting, shadows, IBL, and probes.
public class TerrainFeature : RenderFeatureBase
{
	// Grid mesh (shared by all patches)
	const int32 GridResolution = 64;
	const int32 GridVertexCount = (GridResolution + 1) * (GridResolution + 1);
	const int32 GridIndexCount = GridResolution * GridResolution * 6;

	private IBuffer mGridVertexBuffer ~ delete _;
	private IBuffer mGridIndexBuffer ~ delete _;

	// Per-frame instance buffers (all terrain patches packed contiguously)
	private IBuffer[RenderConfig.FrameBufferCount] mInstanceBuffers;

	// Per-frame terrain uniform buffers (all terrain uniforms packed contiguously)
	private IBuffer[RenderConfig.FrameBufferCount] mTerrainUniformBuffers;

	// Terrain bind group layout (space1)
	private IBindGroupLayout mTerrainBindGroupLayout ~ delete _;

	// Per-terrain bind groups (space1) — recreated when textures change
	// Key: terrain proxy generation, value: bind group
	private List<TerrainBindGroupEntry> mPerTerrainBindGroups = new .() ~ {
		for (let entry in _) { if (entry.BindGroup != null) delete entry.BindGroup; }
		delete _;
	};

	// Per-frame draw data collected during PrepareTerrainData
	private List<TerrainDrawData> mDrawData = new .() ~ delete _;

	// Own scene bind groups (space0) — built from shared resources, like ForwardTransparentFeature
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroups;
	private bool[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupShadowState;
	private bool[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupIBLState;
	private uint32[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupProbeGeneration;

	// Object uniform buffer (required by scene bind group layout, terrain uses offset 0 with identity)
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers;
	private const uint64 ObjectUniformAlignment = 256;
	private const uint64 AlignedObjectUniformSize = ((ObjectUniforms.Size + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

	// Pipeline
	private IRenderPipeline mTerrainPipeline ~ delete _;
	private IRenderPipeline mTerrainPipelineNoShadows ~ delete _;
	private IPipelineLayout mTerrainPipelineLayout ~ delete _;

	// Scene bind group layout borrowed from ForwardOpaqueFeature (don't delete)
	private IBindGroupLayout mSceneBindGroupLayout;

	// Sampler for terrain textures
	private ISampler mTerrainSampler ~ delete _;

	// Limits
	const int32 MaxTotalPatches = 64 * 64;
	const int32 MaxTerrains = 16;

	// Terrain texture generation counter (incremented when proxy textures change)
	private uint32 mTextureGeneration = 0;

	/// Feature name.
	public override StringView Name => "Terrain";

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => Renderer.RenderFrameContext?.FrameIndex ?? 0;

	/// Gets the bind group index accounting for the active view.
	private int32 GetBindGroupIndex(int32 frameIndex) => frameIndex * RenderConfig.MaxViews + (Renderer.RenderFrameContext?.ActiveViewIndex ?? 0);

	/// Depends on ForwardOpaque (terrain renders after opaque meshes).
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
	}

	protected override Result<void> OnInitialize()
	{
		if (CreateGridMesh() case .Err)
			return .Err;

		// Create terrain sampler (linear clamp for heightmap/normalmap/splatmap)
		{
			SamplerDesc samplerDesc = .();
			samplerDesc.MinFilter = .Linear;
			samplerDesc.MagFilter = .Linear;
			samplerDesc.MipmapFilter = .Linear;
			samplerDesc.AddressU = .ClampToEdge;
			samplerDesc.AddressV = .ClampToEdge;
			samplerDesc.AddressW = .ClampToEdge;

			switch (Renderer.Device.CreateSampler(samplerDesc))
			{
			case .Ok(let sampler): mTerrainSampler = sampler;
			case .Err: return .Err;
			}
		}

		if (CreateTerrainBindGroupLayout() case .Err)
			return .Err;

		// Borrow scene bind group layout from ForwardOpaqueFeature
		if (let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>())
			mSceneBindGroupLayout = opaqueFeature.[Friend]mSceneBindGroupLayout;

		if (mSceneBindGroupLayout == null)
			return .Err;

		if (CreatePipelineLayout() case .Err)
			return .Err;

		if (CreateTerrainPipeline() case .Err)
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
		uint64 vertexSize = (uint64)(vertexCount * 8);

		BufferDesc vertDesc = .()
		{
			Label = "Terrain Grid Vertices",
			Size = vertexSize,
			Usage = .Vertex,
			MemoryAccess = .CpuToGpu
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

		uint64 indexSize = (uint64)(GridIndexCount * 2);

		BufferDesc idxDesc = .()
		{
			Label = "Terrain Grid Indices",
			Size = indexSize,
			Usage = .Index,
			MemoryAccess = .CpuToGpu
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

	private Result<void> CreateTerrainBindGroupLayout()
	{
		// Binding numbers = HLSL register numbers; RHI applies DXC shifts automatically
		BindGroupLayoutEntry[9] entries = .(
			.UniformBuffer(0, .Vertex | .Fragment),            // b0 space1: TerrainUniforms
			.SampledTexture(0, .Vertex | .Fragment),           // t0 space1: Heightmap
			.SampledTexture(1, .Fragment),                      // t1 space1: NormalMap
			.SampledTexture(2, .Fragment),                      // t2 space1: Splatmap
			.SampledTexture(3, .Fragment),                      // t3 space1: LayerAlbedo0
			.SampledTexture(4, .Fragment),                      // t4 space1: LayerAlbedo1
			.SampledTexture(5, .Fragment),                      // t5 space1: LayerAlbedo2
			.SampledTexture(6, .Fragment),                      // t6 space1: LayerAlbedo3
			.Sampler(0, .Vertex | .Fragment)                   // s0 space1: TerrainSampler
		);

		BindGroupLayoutDesc layoutDesc = .()
		{
			Label = "Terrain BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mTerrainBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreatePipelineLayout()
	{
		IBindGroupLayout[2] layouts = .(mSceneBindGroupLayout, mTerrainBindGroupLayout);
		PipelineLayoutDesc plDesc = .(layouts);

		switch (Renderer.Device.CreatePipelineLayout(plDesc))
		{
		case .Ok(let layout): mTerrainPipelineLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateTerrainPipeline()
	{
		if (Renderer.ShaderSystem == null)
			return .Err;

		let shaderResult = Renderer.ShaderSystem.GetShaderPair("terrain", .ReceiveShadows);
		if (shaderResult case .Err)
			return .Err;

		let (vertShader, fragShader) = shaderResult.Value;

		VertexAttribute[1] meshAttrs = .(
			.(VertexFormat.Float2, 0, 0)
		);
		VertexAttribute[1] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 1)
		);
		VertexBufferLayout[2] vertexBuffers = .(
			.(8, meshAttrs, .Vertex),
			.(16, instanceAttrs, .Instance)
		);

		ColorTargetState[2] colorTargets = .(
			.(.RGBA16Float),
			.(.RGBA8Unorm)
		);

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "Terrain Pipeline",
			Layout = mTerrainPipelineLayout,
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
				CullMode = .Back
			},
			DepthStencil = .()
			{
				Format = Renderer.DepthFormat,
				DepthTestEnabled = true,
				DepthWriteEnabled = true,
				DepthCompare = .LessEqual
			},
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(pipelineDesc))
		{
		case .Ok(let pipeline): mTerrainPipeline = pipeline;
		case .Err: return .Err;
		}

		// No-shadows variant
		let shaderResultNoShadow = Renderer.ShaderSystem.GetShaderPair("terrain", .None);
		if (shaderResultNoShadow case .Ok(let pair))
		{
			let (vertNS, fragNS) = pair;

			RenderPipelineDesc noShadowDesc = pipelineDesc;
			noShadowDesc.Label = "Terrain Pipeline (No Shadows)";
			noShadowDesc.Vertex.Shader = .(vertNS.Module, "main");
			noShadowDesc.Fragment = .()
			{
				Shader = .(fragNS.Module, "main"),
				Targets = Span<ColorTargetState>(&colorTargets[0], 2)
			};

			switch (Renderer.Device.CreateRenderPipeline(noShadowDesc))
			{
			case .Ok(let pipeline): mTerrainPipelineNoShadows = pipeline;
			case .Err:
			}
		}

		return .Ok;
	}

	private Result<void> CreatePerFrameBuffers()
	{
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc instDesc = .()
			{
				Label = "Terrain Instance Buffer",
				Size = TerrainPatchInstance.Size * MaxTotalPatches,
				Usage = .Vertex,
				MemoryAccess = .CpuToGpu
			};

			switch (Renderer.Device.CreateBuffer(instDesc))
			{
			case .Ok(let buf): mInstanceBuffers[i] = buf;
			case .Err: return .Err;
			}

			BufferDesc uniformDesc = .()
			{
				Label = "Terrain Uniforms",
				Size = TerrainUniforms.Size * MaxTerrains,
				Usage = .Uniform,
				MemoryAccess = .CpuToGpu
			};

			switch (Renderer.Device.CreateBuffer(uniformDesc))
			{
			case .Ok(let buf): mTerrainUniformBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private Result<void> CreateObjectUniformBuffers()
	{
		// Scene bind group layout requires ObjectUniforms at b1 (dynamic offset).
		// Terrain doesn't use per-object transforms — write identity at offset 0.
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc desc = .()
			{
				Label = "Terrain Object Uniforms",
				Size = AlignedObjectUniformSize,
				Usage = .Uniform,
				MemoryAccess = .CpuToGpu
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
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mInstanceBuffers[i] != null)
			{
				delete mInstanceBuffers[i];
				mInstanceBuffers[i] = null;
			}
			if (mTerrainUniformBuffers[i] != null)
			{
				delete mTerrainUniformBuffers[i];
				mTerrainUniformBuffers[i] = null;
			}
			if (mObjectUniformBuffers[i] != null)
			{
				delete mObjectUniformBuffers[i];
				mObjectUniformBuffers[i] = null;
			}
		}

		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mSceneBindGroups[i] != null)
			{
				delete mSceneBindGroups[i];
				mSceneBindGroups[i] = null;
			}
		}

		for (let entry in mPerTerrainBindGroups)
		{
			if (entry.BindGroup != null)
				delete entry.BindGroup;
		}
		mPerTerrainBindGroups.Clear();
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		if (world.TerrainCount == 0)
			return;

		let depthHandle = graph.GetResource("SceneDepth");
		let colorHandle = graph.GetResource("SceneColor");
		let gbufferHandle = graph.GetResource("SceneNormalRoughness");

		if (!depthHandle.IsValid || !colorHandle.IsValid || !gbufferHandle.IsValid)
			return;

		let frameIndex = FrameIndex;

		// Collect draw data for all active terrains
		PrepareTerrainData(world, frameIndex);

		if (mDrawData.Count == 0)
			return;

		// Create/update bind groups
		UpdatePerTerrainBindGroups(world, frameIndex);
		CreateSceneBindGroup(frameIndex);

		graph.AddGraphicsPass("Terrain")
			.WriteColor(colorHandle, .Load, .Store)
			.WriteColor(gbufferHandle, .Load, .Store)
			.WriteDepth(depthHandle, .Load, .Store)
			.NeverCull()
			.SetExecuteCallback(new (encoder) => {
				ExecuteTerrainPass(encoder, world, view, frameIndex);
			});
	}

	private void PrepareTerrainData(RenderWorld world, int32 frameIndex)
	{
		mDrawData.Clear();

		let instanceBuffer = mInstanceBuffers[frameIndex];
		let uniformBuffer = mTerrainUniformBuffers[frameIndex];
		if (instanceBuffer == null || uniformBuffer == null)
			return;

		// Map both buffers for writing
		let instancePtr = instanceBuffer.Map();
		let uniformPtr = uniformBuffer.Map();
		if (instancePtr == null || uniformPtr == null)
		{
			if (instancePtr != null) instanceBuffer.Unmap();
			if (uniformPtr != null) uniformBuffer.Unmap();
			return;
		}

		TerrainPatchInstance* instances = (TerrainPatchInstance*)instancePtr;
		uint8* uniforms = (uint8*)uniformPtr;

		int32 totalPatchOffset = 0;
		int32 terrainIndex = 0;

		world.ForEachTerrain(scope [&] (handle, proxy) =>
		{
			if (!proxy.IsActive || terrainIndex >= MaxTerrains)
				return;

			int32 patchCount = proxy.PatchCountX * proxy.PatchCountZ;
			if (totalPatchOffset + patchCount > MaxTotalPatches)
				patchCount = MaxTotalPatches - totalPatchOffset;
			if (patchCount <= 0)
				return;

			// Write uniform data for this terrain
			TerrainUniforms terrainUniforms = .()
			{
				TerrainOrigin = proxy.Position,
				HeightScale = proxy.HeightScale,
				TerrainWorldSize = proxy.WorldSize,
				HeightmapSize = .((float)proxy.HeightmapWidth, (float)proxy.HeightmapHeight),
				LayerScales = proxy.LayerScales,
				Roughness = proxy.Roughness,
				Metallic = proxy.Metallic,
				_Pad = default
			};
			Internal.MemCpy(uniforms + terrainIndex * TerrainUniforms.Size, &terrainUniforms, TerrainUniforms.Size);

			// Write instance data (patch offsets and sizes)
			let patchSizeX = proxy.WorldSize.X / (float)proxy.PatchCountX;
			let patchSizeZ = proxy.WorldSize.Y / (float)proxy.PatchCountZ;

			int32 written = 0;
			for (int32 pz = 0; pz < proxy.PatchCountZ; pz++)
			{
				for (int32 px = 0; px < proxy.PatchCountX; px++)
				{
					if (written >= patchCount)
						break;

					instances[totalPatchOffset + written] = .()
					{
						OffsetX = (float)px * patchSizeX,
						OffsetZ = (float)pz * patchSizeZ,
						ScaleX = patchSizeX,
						ScaleZ = patchSizeZ
					};
					written++;
				}
			}

			mDrawData.Add(.()
			{
				Handle = handle,
				TerrainIndex = terrainIndex,
				InstanceStart = totalPatchOffset,
				PatchCount = written
			});

			totalPatchOffset += written;
			terrainIndex++;
		});

		instanceBuffer.Unmap();
		uniformBuffer.Unmap();
	}

	private void UpdatePerTerrainBindGroups(RenderWorld world, int32 frameIndex)
	{
		let currentGen = mTextureGeneration;
		let uniformBuffer = mTerrainUniformBuffers[frameIndex];
		if (uniformBuffer == null)
			return;

		for (let draw in mDrawData)
		{
			// Find or create bind group entry for this terrain
			TerrainBindGroupEntry* existing = null;
			for (var entry in ref mPerTerrainBindGroups)
			{
				if (entry.Handle == draw.Handle)
				{
					existing = &entry;
					break;
				}
			}

			// Check if existing bind group is still valid
			if (existing != null && existing.BindGroup != null && existing.Generation == currentGen)
				continue;

			// Get terrain proxy for its textures
			let terrain = world.GetTerrain(.() { Handle = draw.Handle });
			if (terrain == null)
				continue;

			if (terrain.HeightmapView == null || terrain.NormalMapView == null ||
				terrain.SplatmapView == null)
				continue;

			// Build bind group entries
			BindGroupEntry[9] entries = .();
			uint64 uniformOffset = (uint64)(draw.TerrainIndex) * TerrainUniforms.Size;
			entries[0] = BindGroupEntry.Buffer(0, uniformBuffer, uniformOffset, TerrainUniforms.Size);
			entries[1] = BindGroupEntry.Texture(0, terrain.HeightmapView);
			entries[2] = BindGroupEntry.Texture(1, terrain.NormalMapView);
			entries[3] = BindGroupEntry.Texture(2, terrain.SplatmapView);

			ITextureView fallbackView = terrain.LayerAlbedoViews[0];
			bool hasAllLayers = true;
			for (int32 i = 0; i < 4; i++)
			{
				ITextureView view = terrain.LayerAlbedoViews[i];
				if (view == null) view = fallbackView;
				if (view == null) { hasAllLayers = false; break; }
				entries[4 + i] = BindGroupEntry.Texture(3 + (uint32)i, view);
			}

			if (!hasAllLayers)
				continue;

			entries[8] = BindGroupEntry.Sampler(0, mTerrainSampler);

			BindGroupDesc bgDesc = .()
			{
				Label = "Terrain BindGroup",
				Layout = mTerrainBindGroupLayout,
				Entries = entries
			};

			if (Renderer.Device.CreateBindGroup(bgDesc) case .Ok(let bg))
			{
				if (existing != null)
				{
					if (existing.BindGroup != null)
						delete existing.BindGroup;
					existing.BindGroup = bg;
					existing.Generation = currentGen;
				}
				else
				{
					mPerTerrainBindGroups.Add(.()
					{
						Handle = draw.Handle,
						BindGroup = bg,
						Generation = currentGen
					});
				}
			}
		}
	}

	/// Call this when terrain proxy textures change to trigger bind group recreation.
	public void InvalidateBindGroups()
	{
		mTextureGeneration++;
	}

	private void CreateSceneBindGroup(int32 frameIndex)
	{
		let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		if (opaqueFeature == null)
			return;

		let shadowsEnabled = opaqueFeature.[Friend]mShadowPassesActive;

		let skyFeature = Renderer.GetFeature<SkyFeature>();
		let hasRealIBL = skyFeature?.IrradianceMapView != null;

		let probeSystem = opaqueFeature.[Friend]mProbeSystem;
		let probeGeneration = probeSystem?.Generation ?? 0;

		let bindGroupIndex = GetBindGroupIndex(frameIndex);

		if (mSceneBindGroups[bindGroupIndex] != null)
		{
			if (mSceneBindGroupShadowState[bindGroupIndex] == shadowsEnabled &&
				mSceneBindGroupIBLState[bindGroupIndex] == hasRealIBL &&
				mSceneBindGroupProbeGeneration[bindGroupIndex] == probeGeneration)
				return;

			delete mSceneBindGroups[bindGroupIndex];
			mSceneBindGroups[bindGroupIndex] = null;
		}

		let sceneLayout = opaqueFeature.[Friend]mSceneBindGroupLayout;
		if (sceneLayout == null)
			return;

		let lighting = opaqueFeature.[Friend]mLighting;
		if (lighting == null)
			return;

		let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
		let objectUniformBuffer = mObjectUniformBuffers[frameIndex];
		let lightingBuffer = lighting.LightBuffer?.GetUniformBuffer(frameIndex);
		let lightDataBuffer = lighting.LightBuffer?.GetLightDataBuffer(frameIndex);
		let viewIndex = Renderer.RenderFrameContext?.ActiveViewIndex ?? 0;
		let clusterInfoBuffer = lighting.ClusterGrid?.GetClusterLightInfoBuffer(frameIndex, viewIndex);
		let lightIndexBuffer = lighting.ClusterGrid?.GetLightIndexBuffer(frameIndex, viewIndex);

		if (cameraBuffer == null || objectUniformBuffer == null ||
			lightingBuffer == null || lightDataBuffer == null ||
			clusterInfoBuffer == null || lightIndexBuffer == null)
			return;

		BindGroupEntry[15] entries = .();

		entries[0] = BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size);
		entries[1] = BindGroupEntry.Buffer(1, objectUniformBuffer, 0, AlignedObjectUniformSize);
		entries[2] = BindGroupEntry.Buffer(3, lightingBuffer, 0, (uint64)LightingUniforms.Size);
		entries[3] = BindGroupEntry.Buffer(4, lightDataBuffer, 0, (uint64)(lighting.LightBuffer.MaxLights * GPULight.Size));
		entries[4] = BindGroupEntry.Buffer(5, clusterInfoBuffer, 0, (uint64)(lighting.ClusterGrid.Config.TotalClusters * 8));
		entries[5] = BindGroupEntry.Buffer(6, lightIndexBuffer, 0, (uint64)(lighting.ClusterGrid.Config.MaxLightsPerCluster * lighting.ClusterGrid.Config.TotalClusters * 4));

		let shadowData = opaqueFeature.[Friend]mShadowRenderer?.GetShadowShaderData() ?? .();
		let materialSystem = Renderer.MaterialSystem;

		if (shadowsEnabled && shadowData.CascadedShadowUniforms != null)
			entries[6] = BindGroupEntry.Buffer(5, shadowData.CascadedShadowUniforms, 0, (uint64)ShadowUniforms.Size);
		else
			entries[6] = BindGroupEntry.Buffer(5, lightingBuffer, 0, (uint64)LightingUniforms.Size);

		let dummyShadowMapView = opaqueFeature.[Friend]mDummyShadowMapArrayView;
		if (shadowsEnabled && shadowData.CascadedShadowMapView != null)
			entries[7] = BindGroupEntry.Texture(7, shadowData.CascadedShadowMapView);
		else if (dummyShadowMapView != null)
			entries[7] = BindGroupEntry.Texture(7, dummyShadowMapView);
		else
			return;

		if (shadowData.CascadedShadowSampler != null)
			entries[8] = BindGroupEntry.Sampler(1, shadowData.CascadedShadowSampler);
		else if (materialSystem?.DefaultSampler != null)
			entries[8] = BindGroupEntry.Sampler(1, materialSystem.DefaultSampler);
		else
			return;

		ITextureView irradianceView = opaqueFeature.[Friend]mFallbackIrradianceCubemapView;
		ITextureView prefilteredView = opaqueFeature.[Friend]mFallbackPrefilteredCubemapView;
		ITextureView brdfLutView = opaqueFeature.[Friend]mFallbackBRDFLutView;
		ISampler iblSampler = opaqueFeature.[Friend]mIBLSampler;

		if (skyFeature != null)
		{
			if (skyFeature.IrradianceMapView != null) irradianceView = skyFeature.IrradianceMapView;
			if (skyFeature.PrefilteredMapView != null) prefilteredView = skyFeature.PrefilteredMapView;
			if (skyFeature.BRDFLutView != null) brdfLutView = skyFeature.BRDFLutView;
			if (skyFeature.EnvironmentSampler != null) iblSampler = skyFeature.EnvironmentSampler;
		}

		if (irradianceView == null || prefilteredView == null || brdfLutView == null || iblSampler == null)
			return;

		entries[9] = BindGroupEntry.Texture(8, irradianceView);
		entries[10] = BindGroupEntry.Texture(9, prefilteredView);
		entries[11] = BindGroupEntry.Texture(10, brdfLutView);
		entries[12] = BindGroupEntry.Sampler(2, iblSampler);

		if (probeSystem == null || probeSystem.GetProbeUniformBuffer(frameIndex) == null || probeSystem.GetCubemapArrayView() == null)
			return;

		entries[13] = BindGroupEntry.Buffer(6, probeSystem.GetProbeUniformBuffer(frameIndex), 0, ProbeUniforms.Size);
		entries[14] = BindGroupEntry.Texture(11, probeSystem.GetCubemapArrayView());

		BindGroupDesc bgDesc = .()
		{
			Label = "Terrain Scene BindGroup",
			Layout = sceneLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(bgDesc) case .Ok(let bg))
		{
			mSceneBindGroups[bindGroupIndex] = bg;
			mSceneBindGroupShadowState[bindGroupIndex] = shadowsEnabled;
			mSceneBindGroupIBLState[bindGroupIndex] = hasRealIBL;
			mSceneBindGroupProbeGeneration[bindGroupIndex] = probeGeneration;
		}
	}

	private void ExecuteTerrainPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view, int32 frameIndex)
	{
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, view.Width, view.Height);

		let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		let shadowsActive = opaqueFeature?.[Friend]mShadowPassesActive ?? false;
		let pipeline = (shadowsActive && mTerrainPipeline != null) ? mTerrainPipeline :
			(mTerrainPipelineNoShadows != null) ? mTerrainPipelineNoShadows : mTerrainPipeline;

		if (pipeline == null)
			return;

		let sceneBindGroup = mSceneBindGroups[GetBindGroupIndex(frameIndex)];
		if (sceneBindGroup == null)
			return;

		let instanceBuffer = mInstanceBuffers[frameIndex];
		if (instanceBuffer == null)
			return;

		encoder.SetPipeline(pipeline);
		uint32[1] dynamicOffsets = .(0);
		encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);

		encoder.SetVertexBuffer(0, mGridVertexBuffer, 0);
		encoder.SetIndexBuffer(mGridIndexBuffer, .UInt16);

		// Draw each terrain with its own bind group and instance range
		for (let draw in mDrawData)
		{
			// Find bind group for this terrain
			IBindGroup terrainBindGroup = null;
			for (let entry in mPerTerrainBindGroups)
			{
				if (entry.Handle == draw.Handle)
				{
					terrainBindGroup = entry.BindGroup;
					break;
				}
			}

			if (terrainBindGroup == null)
				continue;

			encoder.SetBindGroup(1, terrainBindGroup, default);

			// Set instance buffer with offset for this terrain's patches
			uint64 instanceOffset = (uint64)draw.InstanceStart * TerrainPatchInstance.Size;
			encoder.SetVertexBuffer(1, instanceBuffer, instanceOffset);

			encoder.DrawIndexed((uint32)GridIndexCount, (uint32)draw.PatchCount, 0, 0, 0);
			Renderer.Stats.DrawCalls++;
		}
	}

	/// Per-terrain draw data collected each frame.
	private struct TerrainDrawData
	{
		public ProxyHandle Handle;
		public int32 TerrainIndex;
		public int32 InstanceStart;
		public int32 PatchCount;
	}

	/// Cached bind group per terrain proxy.
	private struct TerrainBindGroupEntry
	{
		public ProxyHandle Handle;
		public IBindGroup BindGroup;
		public uint32 Generation;
	}
}
