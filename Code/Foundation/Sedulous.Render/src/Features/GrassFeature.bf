namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// Grass uniform data matching grass.vert/frag.hlsl cbuffer (space1, b0).
[CRepr]
struct GrassUniforms
{
	public Vector3 GrassColor;
	public float AlphaCutoff;
	public float WindStrength;
	public float WindFrequency;
	public Vector2 WindDirection;
	public float Roughness;
	public float BladeWidth;
	public float BladeHeight;
	public float FadeStart;
	public float FadeEnd;
	public float[3] _Pad;

	public const uint64 Size = 64; // 4 x float4
}

/// Per-instance data for a grass blade (16 bytes).
[CRepr]
struct GrassInstance
{
	public Vector4 PositionScale; // xyz = world pos, w = scale
}

/// Grass render feature.
/// Renders instanced grass blades placed on terrain via CPU heightmap/splatmap sampling.
/// Cross-blade mesh with wind animation and alpha-test PBR rendering.
public class GrassFeature : RenderFeatureBase
{
	// Blade mesh: 2 perpendicular quads (cross shape)
	const int32 BladeVertexCount = 8;
	const int32 BladeIndexCount = 12;
	const int32 BladeVertexStride = 20; // float3 pos + float2 uv

	private IBuffer mBladeVertexBuffer;
	private IBuffer mBladeIndexBuffer;

	// Per-frame instance buffers
	private IBuffer[RenderConfig.FrameBufferCount] mInstanceBuffers;

	// Per-frame uniform buffers
	private IBuffer[RenderConfig.FrameBufferCount] mGrassUniformBuffers;

	// Per-frame object uniform buffers (identity, for scene bind group)
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers;
	private const uint64 ObjectUniformAlignment = 256;
	private const uint64 AlignedObjectUniformSize = ((ObjectUniforms.Size + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

	// Bind group layouts
	private IBindGroupLayout mGrassBindGroupLayout;

	// Pipelines
	private IRenderPipeline mGrassPipeline;
	private IRenderPipeline mGrassPipelineNoShadows;
	private IPipelineLayout mGrassPipelineLayout;

	// Sampler
	private ISampler mGrassSampler;

	// Per-grass bind groups (cached)
	private List<GrassBindGroupEntry> mPerGrassBindGroups = new .() ~ delete _;

	// Scene bind groups (space0, own copy)
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroups;
	private bool[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupShadowState;
	private bool[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupIBLState;
	private uint32[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupProbeGeneration;

	// Draw data per frame
	struct GrassDrawData
	{
		public int32 InstanceStart;
		public int32 InstanceCount;
		public int32 GrassIndex;
		public int32 RenderableIndex;
	}
	private List<GrassDrawData> mDrawData = new .() ~ delete _;

	// Limits
	const int32 MaxGrassTypes = 8;
	const int32 MaxInstancesPerType = 65536*4;
	const int32 MaxTotalInstances = MaxGrassTypes * MaxInstancesPerType;
	const float CellSize = 2.0f;

	// Texture generation counter
	private uint32 mTextureGeneration = 0;

	/// Feature name.
	public override StringView Name => "Grass";

	/// Depends on Terrain (grass renders after terrain, before water).
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("Terrain");
	}

	protected override Result<void> OnInitialize(InitContext initCtx)
	{
		if (CreateBladeMesh() case .Err)
			return .Err;

		if (CreateSampler() case .Err)
			return .Err;

		if (CreateGrassBindGroupLayout() case .Err)
			return .Err;



		if (CreateGrassPipelineLayout() case .Err)
			return .Err;

		if (CreateGrassPipeline() case .Err)
			return .Err;

		if (CreatePerFrameBuffers() case .Err)
			return .Err;

		if (CreateObjectUniformBuffers() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateBladeMesh()
	{
		// Cross-blade: 2 perpendicular quads forming an X shape
		// Each quad: bottom-left, bottom-right, top-left, top-right
		// UV: u=0..1 across blade, v=0 at root, v=1 at tip
		// Local space: blade centered at origin, extends up along Y

		uint64 vertexSize = (uint64)(BladeVertexCount * BladeVertexStride);

		BufferDesc vertDesc = .()
		{
			Label = "Grass Blade Vertices",
			Size = vertexSize,
			Usage = .Vertex,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(vertDesc))
		{
		case .Ok(let buf): mBladeVertexBuffer = buf;
		case .Err: return .Err;
		}

		if (let ptr = mBladeVertexBuffer.Map())
		{
			float* f = (float*)ptr;
			float hw = 0.5f; // half-width (will be scaled by BladeWidth uniform)

			// Quad 1: aligned along X axis
			// Vertex 0: bottom-left (-hw, 0, 0) uv(0, 0)
			*f++ = -hw; *f++ = 0; *f++ = 0; *f++ = 0; *f++ = 0;
			// Vertex 1: bottom-right (hw, 0, 0) uv(1, 0)
			*f++ = hw; *f++ = 0; *f++ = 0; *f++ = 1; *f++ = 0;
			// Vertex 2: top-left (-hw, 1, 0) uv(0, 1)
			*f++ = -hw; *f++ = 1; *f++ = 0; *f++ = 0; *f++ = 1;
			// Vertex 3: top-right (hw, 1, 0) uv(1, 1)
			*f++ = hw; *f++ = 1; *f++ = 0; *f++ = 1; *f++ = 1;

			// Quad 2: aligned along Z axis (perpendicular)
			// Vertex 4: bottom-left (0, 0, -hw) uv(0, 0)
			*f++ = 0; *f++ = 0; *f++ = -hw; *f++ = 0; *f++ = 0;
			// Vertex 5: bottom-right (0, 0, hw) uv(1, 0)
			*f++ = 0; *f++ = 0; *f++ = hw; *f++ = 1; *f++ = 0;
			// Vertex 6: top-left (0, 1, -hw) uv(0, 1)
			*f++ = 0; *f++ = 1; *f++ = -hw; *f++ = 0; *f++ = 1;
			// Vertex 7: top-right (0, 1, hw) uv(1, 1)
			*f++ = 0; *f++ = 1; *f++ = hw; *f++ = 1; *f++ = 1;

			mBladeVertexBuffer.Unmap();
		}

		// Index buffer: 2 quads x 2 triangles x 3 indices = 12
		uint64 indexSize = (uint64)(BladeIndexCount * 2); // uint16

		BufferDesc idxDesc = .()
		{
			Label = "Grass Blade Indices",
			Size = indexSize,
			Usage = .Index,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(idxDesc))
		{
		case .Ok(let buf): mBladeIndexBuffer = buf;
		case .Err: return .Err;
		}

		if (let ptr = mBladeIndexBuffer.Map())
		{
			uint16* i = (uint16*)ptr;
			// Quad 1: 0,2,1 1,2,3
			*i++ = 0; *i++ = 2; *i++ = 1;
			*i++ = 1; *i++ = 2; *i++ = 3;
			// Quad 2: 4,6,5 5,6,7
			*i++ = 4; *i++ = 6; *i++ = 5;
			*i++ = 5; *i++ = 6; *i++ = 7;

			mBladeIndexBuffer.Unmap();
		}

		return .Ok;
	}

	private Result<void> CreateSampler()
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
		case .Ok(let s): mGrassSampler = s;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateGrassBindGroupLayout()
	{
		// Grass bind group (space1):
		// b0: GrassUniforms
		// t0: AlbedoTexture
		// s0: GrassSampler
		BindGroupLayoutEntry[3] entries = .(
			.UniformBuffer(0, .Vertex | .Fragment),   // b0 space1: GrassUniforms
			.SampledTexture(0, .Fragment),             // t0 space1: AlbedoTexture
			.Sampler(0, .Fragment)                     // s0 space1: GrassSampler
		);

		BindGroupLayoutDesc layoutDesc = .()
		{
			Label = "Grass BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mGrassBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateGrassPipelineLayout()
	{
		IBindGroupLayout[2] layouts = .(Renderer.SharedLayouts.SceneLayout, mGrassBindGroupLayout);
		PipelineLayoutDesc plDesc = .(layouts);

		switch (Renderer.Device.CreatePipelineLayout(plDesc))
		{
		case .Ok(let layout): mGrassPipelineLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateGrassPipeline()
	{
		if (Renderer.ShaderSystem == null)
			return .Err;

		let shaderResult = Renderer.ShaderSystem.GetShaderPair("grass", .ReceiveShadows);
		if (shaderResult case .Err)
			return .Err;

		let (vertShader, fragShader) = shaderResult.Value;

		// Vertex buffer 0: blade mesh (float3 pos + float2 uv = 20 bytes)
		VertexAttribute[2] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // POSITION
			.(VertexFormat.Float2, 12, 1)   // TEXCOORD0
		);

		// Vertex buffer 1: per-instance data (float4 pos_scale = 16 bytes)
		VertexAttribute[1] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 2)    // ATTRIB0
		);

		VertexBufferLayout[2] vertexBuffers = .(
			.((.)BladeVertexStride, meshAttrs, .Vertex),
			.(16, instanceAttrs, .Instance)
		);

		ColorTargetState[2] colorTargets = .(
			.(.RGBA16Float),    // SceneColor
			.(.RGBA8Unorm)      // GBuffer
		);

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "Grass Pipeline",
			Layout = mGrassPipelineLayout,
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
				CullMode = .None   // Grass visible from both sides
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
		case .Ok(let pipeline): mGrassPipeline = pipeline;
		case .Err: return .Err;
		}

		// No-shadows variant
		let shaderResultNoShadow = Renderer.ShaderSystem.GetShaderPair("grass", .None);
		if (shaderResultNoShadow case .Ok(let pair))
		{
			let (vertNS, fragNS) = pair;

			RenderPipelineDesc noShadowDesc = pipelineDesc;
			noShadowDesc.Label = "Grass Pipeline (No Shadows)";
			noShadowDesc.Vertex.Shader = .(vertNS.Module, "main");
			noShadowDesc.Fragment = .()
			{
				Shader = .(fragNS.Module, "main"),
				Targets = Span<ColorTargetState>(&colorTargets[0], 2)
			};

			switch (Renderer.Device.CreateRenderPipeline(noShadowDesc))
			{
			case .Ok(let pipeline): mGrassPipelineNoShadows = pipeline;
			case .Err:
			}
		}

		return .Ok;
	}

	private Result<void> CreatePerFrameBuffers()
	{
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// Instance buffer
			BufferDesc instanceDesc = .()
			{
				Label = "Grass Instances",
				Size = (uint64)(MaxTotalInstances * sizeof(GrassInstance)),
				Usage = .Vertex,
				Memory = .CpuToGpu
			};

			switch (Renderer.Device.CreateBuffer(instanceDesc))
			{
			case .Ok(let buf): mInstanceBuffers[i] = buf;
			case .Err: return .Err;
			}

			// Uniform buffer
			BufferDesc uniformDesc = .()
			{
				Label = "Grass Uniforms",
				Size = GrassUniforms.Size * MaxGrassTypes,
				Usage = .Uniform,
				Memory = .CpuToGpu
			};

			switch (Renderer.Device.CreateBuffer(uniformDesc))
			{
			case .Ok(let buf): mGrassUniformBuffers[i] = buf;
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
				Label = "Grass Object Uniforms",
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
			device.DestroyBuffer(ref mInstanceBuffers[i]);
			device.DestroyBuffer(ref mGrassUniformBuffers[i]);
			device.DestroyBuffer(ref mObjectUniformBuffers[i]);
		}

		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mSceneBindGroups[i] != null) device.DestroyBindGroup(ref mSceneBindGroups[i]);
		}

		for (var entry in ref mPerGrassBindGroups)
		{
			if (entry.BindGroup != null)
				device.DestroyBindGroup(ref entry.BindGroup);
		}
		mPerGrassBindGroups.Clear();

		device.DestroyBuffer(ref mBladeVertexBuffer);
		device.DestroyBuffer(ref mBladeIndexBuffer);
		device.DestroyBindGroupLayout(ref mGrassBindGroupLayout);
		device.DestroyRenderPipeline(ref mGrassPipeline);
		device.DestroyRenderPipeline(ref mGrassPipelineNoShadows);
		device.DestroyPipelineLayout(ref mGrassPipelineLayout);
		device.DestroySampler(ref mGrassSampler);
	}

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderableList renderables)
	{
		if (renderables.GrassPatches.Count == 0)
			return;

		let depthHandle = graph.GetResource("SceneDepth");
		let colorHandle = graph.GetResource("SceneColor");
		let gbufferHandle = graph.GetResource("SceneNormalRoughness");

		if (!depthHandle.IsValid || !colorHandle.IsValid || !gbufferHandle.IsValid)
			return;

		let frameIndex = view.FrameIndex;
		let bindGroupIndex = view.GetBindGroupIndex();

		// Generate instances and upload uniforms
		PrepareGrassData(renderables, view, frameIndex);

		if (mDrawData.Count == 0)
			return;

		// Create scene bind group
		CreateSceneBindGroup(frameIndex, bindGroupIndex);

		RenderableList renderablesRef = renderables;
		graph.AddRenderPass("Grass", scope (builder) => {
				builder.SetColorTarget(0, colorHandle, .Load, .Store);
				builder.SetColorTarget(1, gbufferHandle, .Load, .Store);
				builder.SetDepthTarget(depthHandle, .Load, .Store);
				builder.NeverCull();
				builder.SetExecute(new [=] (encoder) => {
					ExecuteGrassPass(encoder, renderablesRef, view, frameIndex, bindGroupIndex);
				});
			});
	}

	private void PrepareGrassData(RenderableList renderables, ViewContext view, int32 frameIndex)
	{
		mDrawData.Clear();

		let instanceBuffer = mInstanceBuffers[frameIndex];
		let uniformBuffer = mGrassUniformBuffers[frameIndex];
		if (instanceBuffer == null || uniformBuffer == null)
			return;

		let instancePtr = instanceBuffer.Map();
		let uniformPtr = uniformBuffer.Map();
		if (instancePtr == null || uniformPtr == null)
		{
			if (instancePtr != null) instanceBuffer.Unmap();
			if (uniformPtr != null) uniformBuffer.Unmap();
			return;
		}

		GrassInstance* instances = (GrassInstance*)instancePtr;
		uint8* uniforms = (uint8*)uniformPtr;
		int32 totalInstanceCount = 0;
		int32 grassIndex = 0;

		// Get camera position for distance-based placement
		let cameraPos = view.CameraPosition;

		for (int32 gi = 0; gi < (int32)renderables.GrassPatches.Count; gi++)
		{
			if (grassIndex >= MaxGrassTypes)
				break;

			var grass = ref renderables.GrassPatches[gi];
			if (grass.HeightmapData == null || grass.HeightmapWidth == 0 || grass.HeightmapHeight == 0)
				continue;

			// Write uniforms
			float fadeEnd = grass.Distance;
			float fadeStart = fadeEnd * 0.8f;

			GrassUniforms grassUniforms = .()
			{
				GrassColor = grass.GrassColor,
				AlphaCutoff = grass.AlphaCutoff,
				WindStrength = grass.WindStrength,
				WindFrequency = grass.WindFrequency,
				WindDirection = grass.WindDirection,
				Roughness = grass.Roughness,
				BladeWidth = grass.BladeWidth,
				BladeHeight = grass.BladeHeight,
				FadeStart = fadeStart,
				FadeEnd = fadeEnd,
				_Pad = default
			};
			Internal.MemCpy(uniforms + grassIndex * GrassUniforms.Size, &grassUniforms, GrassUniforms.Size);

			// Generate instances
			int32 instanceStart = totalInstanceCount;
			int32 instanceCount = 0;
			int32 maxForThisType = Math.Min(MaxInstancesPerType, MaxTotalInstances - totalInstanceCount);

			GenerateInstances(
				ref grass, cameraPos, grassIndex,
				instances + totalInstanceCount, maxForThisType, ref instanceCount
			);

			if (instanceCount > 0)
			{
				mDrawData.Add(.()
				{
					InstanceStart = instanceStart,
					InstanceCount = instanceCount,
					GrassIndex = grassIndex,
					RenderableIndex = gi
				});
				totalInstanceCount += instanceCount;
			}

			grassIndex++;
		}

		instanceBuffer.Unmap();
		uniformBuffer.Unmap();
	}

	private void GenerateInstances(ref GrassRenderable proxy, Vector3 cameraPos, int32 grassTypeIndex,
		GrassInstance* outInstances, int32 maxInstances, ref int32 outCount)
	{
		let terrainMinX = proxy.Origin.X;
		let terrainMinZ = proxy.Origin.Z;
		let terrainMaxX = terrainMinX + proxy.WorldSize.X;
		let terrainMaxZ = terrainMinZ + proxy.WorldSize.Y;

		// Grid bounds around camera, clamped to terrain
		let dist = proxy.Distance;
		let gridMinX = Math.Max(terrainMinX, cameraPos.X - dist);
		let gridMaxX = Math.Min(terrainMaxX, cameraPos.X + dist);
		let gridMinZ = Math.Max(terrainMinZ, cameraPos.Z - dist);
		let gridMaxZ = Math.Min(terrainMaxZ, cameraPos.Z + dist);

		if (gridMinX >= gridMaxX || gridMinZ >= gridMaxZ)
			return;

		// Snap to cell grid
		let cellStartX = Math.Floor(gridMinX / CellSize) * CellSize;
		let cellStartZ = Math.Floor(gridMinZ / CellSize) * CellSize;

		int32 bladesPerCell = (int32)Math.Ceiling(proxy.Density * CellSize * CellSize);
		bladesPerCell = Math.Min(bladesPerCell, 32);

		let distSq = dist * dist;
		int32 count = 0;
		bool bufferFull = false;

		var cellZ = cellStartZ;
		while (cellZ < gridMaxZ && !bufferFull)
		{
			var cellX = cellStartX;
			while (cellX < gridMaxX && !bufferFull)
			{
				// Deterministic seed from cell + type
				uint32 seed = HashCell((int32)(cellX / CellSize), (int32)(cellZ / CellSize), grassTypeIndex);

				for (int32 b = 0; b < bladesPerCell; b++)
				{
					if (count >= maxInstances)
					{
						bufferFull = true;
						break;
					}

					// LCG random
					seed = seed * 1103515245 + 12345;
					let rx = (float)(seed & 0xFFFF) / 65535.0f;
					seed = seed * 1103515245 + 12345;
					let rz = (float)(seed & 0xFFFF) / 65535.0f;
					seed = seed * 1103515245 + 12345;
					let rScale = (float)(seed & 0xFFFF) / 65535.0f;

					let worldX = cellX + rx * CellSize;
					let worldZ = cellZ + rz * CellSize;

					// Bounds check
					if (worldX < terrainMinX || worldX > terrainMaxX || worldZ < terrainMinZ || worldZ > terrainMaxZ)
						continue;

					// Distance check
					let dx = worldX - cameraPos.X;
					let dz = worldZ - cameraPos.Z;
					let d2 = dx * dx + dz * dz;
					if (d2 > distSq)
						continue;

					// Splatmap check
					if (proxy.SplatmapData != null && proxy.SplatChannel >= 0 && proxy.SplatChannel <= 3)
					{
						let weight = SampleSplatmap(ref proxy, worldX, worldZ);
						if (weight < proxy.SplatThreshold)
							continue;
					}

					// Sample heightmap for Y position
					let worldY = SampleHeight(ref proxy, worldX, worldZ);

					// Scale
					let scale = proxy.MinScale + rScale * (proxy.MaxScale - proxy.MinScale);

					outInstances[count] = .() { PositionScale = .(worldX, worldY, worldZ, scale) };
					count++;
				}

				cellX += CellSize;
			}
			cellZ += CellSize;
		}

		outCount = count;
	}

	/// Deterministic hash for a cell coordinate.
	private static uint32 HashCell(int32 cx, int32 cz, int32 typeIndex)
	{
		uint32 h = (uint32)cx * 374761393u + (uint32)cz * 668265263u + (uint32)typeIndex * 1274126177u;
		h = (h ^ (h >> 13)) * 1274126177u;
		h = h ^ (h >> 16);
		return h;
	}

	/// Bilinear sample of CPU heightmap.
	private float SampleHeight(ref GrassRenderable proxy, float worldX, float worldZ)
	{
		let u = (worldX - proxy.Origin.X) / proxy.WorldSize.X;
		let v = (worldZ - proxy.Origin.Z) / proxy.WorldSize.Y;

		let fx = Math.Clamp(u, 0, 1) * (float)(proxy.HeightmapWidth - 1);
		let fz = Math.Clamp(v, 0, 1) * (float)(proxy.HeightmapHeight - 1);

		let ix = (int32)fx;
		let iz = (int32)fz;
		let fracX = fx - (float)ix;
		let fracZ = fz - (float)iz;

		let ix1 = Math.Min(ix + 1, (int32)(proxy.HeightmapWidth - 1));
		let iz1 = Math.Min(iz + 1, (int32)(proxy.HeightmapHeight - 1));

		let w = (int32)proxy.HeightmapWidth;
		let h00 = proxy.HeightmapData[iz * w + ix];
		let h10 = proxy.HeightmapData[iz * w + ix1];
		let h01 = proxy.HeightmapData[iz1 * w + ix];
		let h11 = proxy.HeightmapData[iz1 * w + ix1];

		let h0 = h00 + (h10 - h00) * fracX;
		let h1 = h01 + (h11 - h01) * fracX;
		let height = h0 + (h1 - h0) * fracZ;

		return proxy.Origin.Y + height * proxy.HeightScale;
	}

	/// Sample splatmap weight for the configured channel.
	private float SampleSplatmap(ref GrassRenderable proxy, float worldX, float worldZ)
	{
		let u = (worldX - proxy.Origin.X) / proxy.WorldSize.X;
		let v = (worldZ - proxy.Origin.Z) / proxy.WorldSize.Y;

		let fx = Math.Clamp(u, 0, 1) * (float)(proxy.SplatmapWidth - 1);
		let fz = Math.Clamp(v, 0, 1) * (float)(proxy.SplatmapHeight - 1);

		let ix = Math.Min((int32)fx, (int32)(proxy.SplatmapWidth - 1));
		let iz = Math.Min((int32)fz, (int32)(proxy.SplatmapHeight - 1));

		// RGBA8 packed: 4 bytes per pixel
		let pixelIndex = (iz * (int32)proxy.SplatmapWidth + ix) * 4;
		let channelValue = proxy.SplatmapData[pixelIndex + proxy.SplatChannel];
		return (float)channelValue / 255.0f;
	}

	private void ExecuteGrassPass(IRenderPassEncoder encoder, RenderableList renderables, ViewContext view, int32 frameIndex, int32 bindGroupIndex)
	{
		let shadowsActive = Renderer.ShadowRenderer?.ShadowPassesActive ?? false;
		let pipeline = (shadowsActive && mGrassPipeline != null) ? mGrassPipeline :
			(mGrassPipelineNoShadows != null) ? mGrassPipelineNoShadows : mGrassPipeline;

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

		encoder.SetVertexBuffer(0, mBladeVertexBuffer, 0);
		encoder.SetIndexBuffer(mBladeIndexBuffer, .UInt16);

		let instanceBuffer = mInstanceBuffers[frameIndex];
		if (instanceBuffer == null)
			return;

		for (let draw in mDrawData)
		{
			if (draw.RenderableIndex < 0 || draw.RenderableIndex >= renderables.GrassPatches.Count)
				continue;

			let grass = ref renderables.GrassPatches[draw.RenderableIndex];

			// Get or create bind group for this grass type
			let grassBindGroup = GetOrCreateGrassBindGroup(grass, draw.RenderableIndex, draw.GrassIndex, frameIndex);
			if (grassBindGroup == null)
				continue;

			encoder.SetBindGroup(1, grassBindGroup, default);

			let instanceOffset = (uint64)(draw.InstanceStart * sizeof(GrassInstance));
			encoder.SetVertexBuffer(1, instanceBuffer, instanceOffset);
			encoder.DrawIndexed((uint32)BladeIndexCount, (uint32)draw.InstanceCount, 0, 0, 0);
			Renderer.Stats.DrawCalls++;
		}
	}

	private IBindGroup GetOrCreateGrassBindGroup(GrassRenderable grass, int32 renderableIndex, int32 grassIndex, int32 frameIndex)
	{
		// Find existing entry
		GrassBindGroupEntry* existing = null;
		for (var entry in ref mPerGrassBindGroups)
		{
			if (entry.RenderableIndex == renderableIndex && entry.FrameIndex == frameIndex)
			{
				if (entry.Generation == mTextureGeneration && entry.BindGroup != null)
					return entry.BindGroup;
				existing = &entry;
				break;
			}
		}

		// Destroy old
		if (existing != null && existing.BindGroup != null)
			Renderer.Device.DestroyBindGroup(ref existing.BindGroup);

		if (grass.AlbedoView == null)
			return null;

		let uniformBuffer = mGrassUniformBuffers[frameIndex];
		if (uniformBuffer == null)
			return null;

		BindGroupEntry[3] entries = .();
		uint64 uniformOffset = (uint64)grassIndex * GrassUniforms.Size;
		entries[0] = BindGroupEntry.Buffer(/*0,*/uniformBuffer, uniformOffset, GrassUniforms.Size);
		entries[1] = BindGroupEntry.Texture(/*0,*/grass.AlbedoView);
		entries[2] = BindGroupEntry.Sampler(/*0,*/mGrassSampler);

		BindGroupDesc bgDesc = .()
		{
			Label = "Grass BindGroup",
			Layout = mGrassBindGroupLayout,
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
				mPerGrassBindGroups.Add(.()
				{
					RenderableIndex = renderableIndex,
					BindGroup = bg,
					Generation = mTextureGeneration,
					FrameIndex = frameIndex
				});
			}
			return bg;
		}

		return null;
	}

	/// Call this when grass proxy textures change.
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

	/// Cached bind group per grass type, keyed by the current frame's renderable index.
	private struct GrassBindGroupEntry
	{
		public int32 RenderableIndex;
		public IBindGroup BindGroup;
		public uint32 Generation;
		public int32 FrameIndex;
	}
}
