namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;

/// Per-object uniform data matching forward.vert.hlsl ObjectUniforms (b1, space0).
[CRepr]
struct ObjectUniforms
{
	public Matrix WorldMatrix;
	public Matrix PrevWorldMatrix;
	public Matrix NormalMatrix;
	public uint32 ObjectID;
	public uint32 MaterialID;
	public float[2] _Padding;

	public const uint64 Size = 208; // 3 matrices (192) + 2 uint32 (8) + 2 float (8) = 208

	public static Self Identity => .()
	{
		WorldMatrix = .Identity,
		PrevWorldMatrix = .Identity,
		NormalMatrix = .Identity,
		ObjectID = 0,
		MaterialID = 0,
		_Padding = .(0, 0)
	};
}

/// Forward opaque render feature.
/// Renders all opaque geometry with full PBR shading and clustered lighting.
public class ForwardOpaqueFeature : RenderFeatureBase
{
	// Lighting system
	private LightingSystem mLighting ~ delete _;
	private ShadowRenderer mShadowRenderer ~ delete _;

	// Bind groups
	private IBindGroupLayout mSceneBindGroupLayout ~ delete _;
	private IBindGroup mSceneBindGroup ~ delete _;

	// Object uniform buffer (for per-object transforms with dynamic offsets)
	private IBuffer mObjectUniformBuffer ~ delete _;
	private const int MaxObjectsPerFrame = 1024;
	private const uint64 ObjectUniformAlignment = 256; // Vulkan minUniformBufferOffsetAlignment
	private const uint64 AlignedObjectUniformSize = ((ObjectUniforms.Size + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

	// Pipeline cache (material -> pipeline)
	private Dictionary<MaterialInstance, IRenderPipeline> mPipelineCache = new .() ~ delete _;

	// Shadow depth rendering
	private IRenderPipeline mShadowDepthPipeline ~ delete _;
	private IPipelineLayout mShadowPipelineLayout ~ delete _;
	private IBindGroupLayout mShadowBindGroupLayout ~ delete _;
	private IBindGroup mShadowBindGroup ~ delete _;
	private IBuffer mShadowUniformBuffer ~ delete _; // Per-cascade SceneUniforms for light matrices
	private IBuffer mShadowObjectBuffer ~ delete _;  // Per-object transforms for shadow pass
	private SceneUniforms mShadowUniforms; // CPU-side shadow uniforms
	private uint64 mAlignedSceneUniformSize; // Aligned size for dynamic uniform offset

	/// Feature name.
	public override StringView Name => "ForwardOpaque";

	/// Gets the lighting system.
	public LightingSystem Lighting => mLighting;

	/// Gets the shadow renderer.
	public ShadowRenderer ShadowRenderer => mShadowRenderer;

	/// Depends on depth prepass.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("DepthPrepass");
	}

	protected override Result<void> OnInitialize()
	{
		// Initialize lighting system
		mLighting = new LightingSystem();
		if (mLighting.Initialize(Renderer.Device, .Default, Renderer.ShaderSystem) case .Err)
			return .Err;

		// Initialize shadow renderer
		mShadowRenderer = new ShadowRenderer();
		if (mShadowRenderer.Initialize(Renderer.Device) case .Err)
			return .Err;

		// Create bind group layouts
		if (CreateBindGroupLayouts() case .Err)
			return .Err;

		// Create object uniform buffer
		if (CreateObjectUniformBuffer() case .Err)
			return .Err;

		// Create forward pipelines
		if (CreateForwardPipelines() case .Err)
			return .Err;

		// Create shadow depth pipeline
		if (CreateShadowPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	private IRenderPipeline mForwardPipeline ~ delete _;
	private IPipelineLayout mForwardPipelineLayout ~ delete _;

	private Result<void> CreateForwardPipelines()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Load forward shaders with default opaque flags (no NormalMap since StaticMesh has no tangents)
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("forward", .DefaultOpaque);
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		// Get material bind group layout from MaterialSystem
		let materialLayout = Renderer.MaterialSystem?.DefaultMaterialLayout;
		if (materialLayout == null)
			return .Ok; // MaterialSystem not initialized yet

		// Create pipeline layout
		IBindGroupLayout[2] layouts = .(mSceneBindGroupLayout, materialLayout);
		PipelineLayoutDescriptor layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(&layoutDesc))
		{
		case .Ok(let layout): mForwardPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Vertex layout - Mesh format matches Sedulous.Geometry.StaticMesh
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Color targets for HDR output
		ColorTargetState[1] colorTargets = .(
			.(.RGBA16Float)
		);

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = "Forward Opaque Pipeline",
			Layout = mForwardPipelineLayout,
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
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = .() // Depth test with equal, no write
			{
				DepthTestEnabled = true,
				DepthWriteEnabled = false,
				DepthCompare = .LessEqual
			},
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mForwardPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateShadowPipeline()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Load depth shaders for shadow rendering
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("depth", .DepthTest | .DepthWrite);
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		// Create shadow bind group layout: light VP (b0, dynamic) + object transforms (b1, dynamic)
		// Both use dynamic offset: b0 selects cascade VP, b1 selects object transforms
		BindGroupLayoutEntry[2] shadowEntries = .(
			.() { Binding = 0, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true }, // Light ViewProjectionMatrix (per cascade)
			.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true } // Object transforms
		);

		BindGroupLayoutDescriptor shadowLayoutDesc = .()
		{
			Label = "Shadow BindGroup Layout",
			Entries = shadowEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&shadowLayoutDesc))
		{
		case .Ok(let layout): mShadowBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create shadow pipeline layout
		IBindGroupLayout[1] layouts = .(mShadowBindGroupLayout);
		PipelineLayoutDescriptor layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(&layoutDesc))
		{
		case .Ok(let layout): mShadowPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Create shadow uniform buffer large enough for 4 cascades with alignment
		// Each cascade needs SceneUniforms aligned to 256 bytes
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		const uint64 AlignedSceneUniformSize = ((SceneUniforms.Size + 255) / 256) * 256; // 256-byte aligned
		BufferDescriptor uniformDesc = .()
		{
			Size = AlignedSceneUniformSize * 4, // 4 cascades
			Usage = .Uniform,
			MemoryAccess = .Upload // CPU-mappable
		};
		switch (Renderer.Device.CreateBuffer(&uniformDesc))
		{
		case .Ok(let buf): mShadowUniformBuffer = buf;
		case .Err: return .Err;
		}

		// Initialize shadow uniforms
		mShadowUniforms = .Identity;
		mAlignedSceneUniformSize = AlignedSceneUniformSize;

		// Create shadow object buffer with Upload memory for CPU mapping
		BufferDescriptor objDesc = .()
		{
			Size = AlignedObjectUniformSize * MaxObjectsPerFrame,
			Usage = .Uniform,
			MemoryAccess = .Upload // CPU-mappable
		};
		switch (Renderer.Device.CreateBuffer(&objDesc))
		{
		case .Ok(let buf): mShadowObjectBuffer = buf;
		case .Err: return .Err;
		}

		// Vertex layout
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Shadow depth pipeline - depth only output
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = "Shadow Depth Pipeline",
			Layout = mShadowPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = default // No color targets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = .()
			{
				DepthTestEnabled = true,
				DepthWriteEnabled = true,
				DepthCompare = .Less,
				Format = .Depth32Float // Match shadow map format
			},
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mShadowDepthPipeline = pipeline;
		case .Err: return .Err;
		}

		// Create shadow bind group
		CreateShadowBindGroup();

		return .Ok;
	}

	protected override void OnShutdown()
	{
		// Clear pipeline cache
		for (let kv in mPipelineCache)
			delete kv.value;
		mPipelineCache.Clear();

		if (mSceneBindGroup != null)
		{
			delete mSceneBindGroup;
			mSceneBindGroup = null;
		}

		if (mShadowBindGroup != null)
		{
			delete mShadowBindGroup;
			mShadowBindGroup = null;
		}

		if (mLighting != null)
			mLighting.Dispose();

		if (mShadowRenderer != null)
			mShadowRenderer.Dispose();
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// Get depth prepass feature for visibility data
		let depthFeature = Renderer.GetFeature<DepthPrepassFeature>();
		if (depthFeature == null)
			return;

		// Get existing depth buffer
		let depthHandle = graph.GetResource("SceneDepth");
		if (!depthHandle.IsValid)
			return;

		// Create HDR color buffer
		let colorDesc = TextureResourceDesc(view.Width, view.Height, .RGBA16Float, .RenderTarget | .Sampled);

		let colorHandle = graph.CreateTexture("SceneColor", colorDesc);

		// Update lighting
		UpdateLighting(world, depthFeature.Visibility, view);

		// Add shadow passes and get shadow map handle for automatic barrier
		RGResourceHandle shadowMapHandle = .Invalid;
		AddShadowPasses(graph, world, depthFeature.Visibility, view, out shadowMapHandle);

		// Create/update scene bind group (needs to be done each frame for frame-specific resources)
		CreateSceneBindGroup();

		// Upload object uniforms BEFORE the render pass
		PrepareObjectUniforms(depthFeature);

		// Add forward opaque pass
		// ReadTexture on shadow map triggers automatic barrier: DepthStencil -> ShaderReadOnly
		var passBuilder = graph.AddGraphicsPass("ForwardOpaque")
			.WriteColor(colorHandle, .Clear, .Store, .(0.0f, 0.0f, 0.0f, 1.0f))
			.ReadDepth(depthHandle)
			.NeverCull();

		// Add shadow map as read dependency if available (triggers automatic barrier)
		if (shadowMapHandle.IsValid)
			passBuilder.ReadTexture(shadowMapHandle);

		passBuilder.SetExecuteCallback(new (encoder) => {
			ExecuteForwardPass(encoder, world, view, depthFeature);
		});
	}

	private void PrepareObjectUniforms(DepthPrepassFeature depthFeature)
	{
		// Upload all object transforms to the uniform buffer BEFORE the render pass
		// Use Map/Unmap to avoid command buffer creation
		let commands = depthFeature.[Friend]mBatcher.DrawCommands;

		if (let bufferPtr = mObjectUniformBuffer.Map())
		{
			int32 objectIndex = 0;
			for (let batch in depthFeature.[Friend]mBatcher.OpaqueBatches)
			{
				if (batch.CommandCount == 0)
					continue;

				for (int32 i = 0; i < batch.CommandCount; i++)
				{
					if (objectIndex >= MaxObjectsPerFrame)
						break;

					let cmd = commands[batch.CommandStart + i];

					// Build object uniforms from draw command
					ObjectUniforms objUniforms = .()
					{
						WorldMatrix = cmd.WorldMatrix,
						PrevWorldMatrix = cmd.PrevWorldMatrix,
						NormalMatrix = cmd.NormalMatrix,
						ObjectID = (uint32)objectIndex,
						MaterialID = 0,
						_Padding = .(0, 0)
					};

					// Copy to mapped buffer at aligned offset
					let bufferOffset = (uint64)objectIndex * AlignedObjectUniformSize;
					Internal.MemCpy((uint8*)bufferPtr + bufferOffset, &objUniforms, ObjectUniforms.Size);

					objectIndex++;
				}
			}
			mObjectUniformBuffer.Unmap();
		}
	}

	private static bool sLightingDebugPrinted = false;

	private void UpdateLighting(RenderWorld world, VisibilityResolver visibility, RenderView view)
	{
		// Update cluster grid
		let inverseProj = Matrix.Invert(view.ProjectionMatrix);
		mLighting.ClusterGrid.Update(view.Width, view.Height, view.NearPlane, view.FarPlane, inverseProj);

		// Calculate cluster scale/bias for shader
		let config = mLighting.ClusterGrid.Config;
		let clusterScaleX = (float)config.ClustersX / (float)view.Width;
		let clusterScaleY = (float)config.ClustersY / (float)view.Height;
		let logDepthScale = (float)config.ClustersZ / Math.Log(view.FarPlane / view.NearPlane);
		let logDepthBias = -(float)config.ClustersZ * Math.Log(view.NearPlane) / Math.Log(view.FarPlane / view.NearPlane);

		// Update light buffer cluster info
		mLighting.LightBuffer.SetClusterInfo(
			config.ClustersX, config.ClustersY, config.ClustersZ,
			.(clusterScaleX, clusterScaleY),
			.(logDepthScale, logDepthBias)
		);

		// Apply environment settings from RenderWorld
		mLighting.LightBuffer.AmbientColor = world.AmbientColor;
		mLighting.LightBuffer.AmbientIntensity = world.AmbientIntensity;
		mLighting.LightBuffer.Exposure = world.Exposure;

		// Update light buffer from visibility
		mLighting.LightBuffer.Update(world, visibility);
		mLighting.LightBuffer.UploadLightData();
		mLighting.LightBuffer.UploadUniforms();

		// Perform light culling (CPU fallback for now)
		// Pass view matrix to transform light positions to view space for cluster testing
		mLighting.ClusterGrid.CullLightsCPU(world, visibility, view.ViewMatrix);

		// Debug output (once)
		if (!sLightingDebugPrinted)
		{
			sLightingDebugPrinted = true;
			Console.WriteLine("\n=== Lighting Debug ===");
			Console.WriteLine("World lights: {}", world.LightCount);
			Console.WriteLine("Visible lights: {}", visibility.VisibleLights.Length);
			Console.WriteLine("Light buffer count: {}", mLighting.LightBuffer.LightCount);
			Console.WriteLine("Cluster grid: {}x{}x{}", config.ClustersX, config.ClustersY, config.ClustersZ);
			Console.WriteLine("Clusters with lights: {}", mLighting.ClusterGrid.Stats.ClustersWithLights);
			Console.WriteLine("Avg lights/cluster: {}", mLighting.ClusterGrid.Stats.AverageLightsPerCluster);
			Console.WriteLine("ClusterScale: ({}, {})", clusterScaleX, clusterScaleY);
			Console.WriteLine("ClusterBias: ({}, {})", logDepthScale, logDepthBias);

			// Print light details
			for (let visLight in visibility.VisibleLights)
			{
				if (let light = world.GetLight(visLight.Handle))
				{
					Console.WriteLine("  Light: type={}, pos=({},{},{}), dir=({},{},{}), color=({},{},{}), intensity={}",
						(int)light.Type, light.Position.X, light.Position.Y, light.Position.Z,
						light.Direction.X, light.Direction.Y, light.Direction.Z,
						light.Color.X, light.Color.Y, light.Color.Z, light.Intensity);
				}
			}
		}
	}

	private static bool sShadowDebugPrinted = false;

	private void AddShadowPasses(RenderGraph graph, RenderWorld world, VisibilityResolver visibility, RenderView view, out RGResourceHandle outShadowMapHandle)
	{
		outShadowMapHandle = .Invalid;

		if (!mShadowRenderer.EnableShadows)
			return;

		if (!mShadowRenderer.IsInitialized)
			return;

		// Create camera proxy from RenderView for CSM calculations
		let target = view.CameraPosition + view.CameraForward;
		var camera = CameraProxy.CreatePerspective(
			view.CameraPosition,
			target,
			view.CameraUp,
			view.FieldOfView,
			view.AspectRatio,
			view.NearPlane,
			view.FarPlane
		);

		// Update shadow renderer
		mShadowRenderer.Update(world, visibility, &camera);

		// Get shadow passes
		List<ShadowPass> shadowPasses = scope .();
		mShadowRenderer.GetShadowPasses(shadowPasses);

		if (shadowPasses.Count == 0)
			return;

		// Debug output (once)
		if (!sShadowDebugPrinted)
		{
			sShadowDebugPrinted = true;
			Console.WriteLine("[Shadow] Adding {} shadow passes", shadowPasses.Count);
		}

		// Upload all shadow uniforms BEFORE adding passes (avoid WriteBuffer during render pass)
		PrepareShadowUniforms(world, visibility, shadowPasses);

		// Import the shadow map array once with a common name for barrier tracking
		// This handle will be used by the forward pass to trigger automatic barrier
		let cascadedShadowMap = mShadowRenderer.CascadedShadows?.ShadowMapArray;
		let cascadedShadowMapView = mShadowRenderer.CascadedShadows?.ShadowMapArrayView;
		if (cascadedShadowMap != null && cascadedShadowMapView != null)
		{
			outShadowMapHandle = graph.ImportTexture("ShadowMap", cascadedShadowMap, cascadedShadowMapView);
		}

		// Add each shadow pass
		int32 cascadeIndex = 0;
		for (let shadowPass in shadowPasses)
		{
			String passName = scope $"Shadow_{shadowPass.Type}_{shadowPass.CascadeIndex}";

			// Get the actual texture based on pass type
			ITexture shadowTexture = null;
			switch (shadowPass.Type)
			{
			case .Cascade:
				shadowTexture = mShadowRenderer.CascadedShadows?.ShadowMapArray;
			case .AtlasTile, .PointLightFace:
				shadowTexture = mShadowRenderer.ShadowAtlas?.AtlasTexture;
			}

			if (shadowTexture == null || shadowPass.RenderTarget == null)
				continue;

			// Import shadow render target with actual texture
			let shadowTarget = graph.ImportTexture(passName, shadowTexture, shadowPass.RenderTarget);

			// Copy shadow pass and cascade index for closure
			ShadowPass passCopy = shadowPass;
			int32 cascadeIdx = cascadeIndex;
			graph.AddGraphicsPass(passName)
				.WriteDepth(shadowTarget)
				.NeverCull() // Shadow maps are used externally by forward pass
				.SetExecuteCallback(new (encoder) => {
					ExecuteShadowPass(encoder, world, visibility, passCopy, cascadeIdx);
				});

			cascadeIndex++;
		}
	}

	// Store shadow passes for VP lookup during execution
	private List<ShadowPass> mCurrentShadowPasses = new .() ~ delete _;

	private void PrepareShadowUniforms(RenderWorld world, VisibilityResolver visibility, List<ShadowPass> shadowPasses)
	{
		// Store shadow passes for VP lookup during cascade rendering
		mCurrentShadowPasses.Clear();
		for (let pass in shadowPasses)
			mCurrentShadowPasses.Add(pass);

		// Map shadow uniform buffer and write cascade VPs directly (no command buffers needed)
		if (let uniformPtr = mShadowUniformBuffer.Map())
		{
			for (int32 i = 0; i < shadowPasses.Count && i < 4; i++)
			{
				mShadowUniforms.ViewProjectionMatrix = shadowPasses[i].ViewProjection;
				let offset = (uint64)i * mAlignedSceneUniformSize;
				Internal.MemCpy((uint8*)uniformPtr + offset, &mShadowUniforms, SceneUniforms.Size);
			}
			mShadowUniformBuffer.Unmap();
		}

		// Map shadow object buffer and write transforms directly
		if (let objectPtr = mShadowObjectBuffer.Map())
		{
			int32 objectIndex = 0;
			for (let visibleMesh in visibility.VisibleMeshes)
			{
				if (objectIndex >= MaxObjectsPerFrame)
					break;

				if (let proxy = world.GetMesh(visibleMesh.Handle))
				{
					if (!proxy.CastsShadows)
						continue;

					ObjectUniforms objUniforms = .()
					{
						WorldMatrix = proxy.WorldMatrix,
						PrevWorldMatrix = proxy.PrevWorldMatrix,
						NormalMatrix = proxy.NormalMatrix,
						ObjectID = (uint32)objectIndex,
						MaterialID = 0,
						_Padding = default
					};

					let offset = (uint64)objectIndex * AlignedObjectUniformSize;
					Internal.MemCpy((uint8*)objectPtr + offset, &objUniforms, ObjectUniforms.Size);

					objectIndex++;
				}
			}
			mShadowObjectBuffer.Unmap();
		}
	}

	private Result<void> CreateBindGroupLayouts()
	{
		// Scene bind group: camera, per-object transforms, lighting, shadows
		// Shader bindings (space0): b0=Camera, b1=ObjectUniforms, b3=LightingUniforms, b5=ShadowUniforms,
		//                           t4=Lights, t5=ClusterLightInfo, t6=LightIndices (read-only StructuredBuffers),
		//                           t7=ShadowMap, s1=ShadowSampler
		// Use HLSL register numbers - RHI applies Vulkan shifts based on Type
		BindGroupLayoutEntry[9] sceneEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer }, // b0: Camera
			.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true }, // b1: ObjectUniforms (dynamic offset per-object)
			.() { Binding = 3, Visibility = .Fragment, Type = .UniformBuffer },           // b3: Lighting uniforms
			.() { Binding = 4, Visibility = .Fragment, Type = .StorageBuffer },           // t4: Lights (StructuredBuffer)
			.() { Binding = 5, Visibility = .Fragment, Type = .StorageBuffer },           // t5: ClusterLightInfo (StructuredBuffer)
			.() { Binding = 6, Visibility = .Fragment, Type = .StorageBuffer },           // t6: LightIndices (StructuredBuffer)
			.() { Binding = 5, Visibility = .Fragment, Type = .UniformBuffer },           // b5: Shadow uniforms
			.() { Binding = 7, Visibility = .Fragment, Type = .SampledTexture },          // t7: ShadowMap
			.() { Binding = 1, Visibility = .Fragment, Type = .ComparisonSampler }        // s1: ShadowSampler
		);

		BindGroupLayoutDescriptor sceneDesc = .()
		{
			Label = "Scene BindGroup Layout",
			Entries = sceneEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&sceneDesc))
		{
		case .Ok(let layout): mSceneBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Material bind group layout is now provided by MaterialSystem
		// See Renderer.MaterialSystem.DefaultMaterialLayout

		return .Ok;
	}

	private Result<void> CreateObjectUniformBuffer()
	{
		// Create object uniform buffer large enough for MaxObjectsPerFrame with alignment
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		var bufferDesc = BufferDescriptor()
		{
			Size = AlignedObjectUniformSize * MaxObjectsPerFrame,
			Usage = .Uniform,
			MemoryAccess = .Upload // CPU-mappable
		};

		switch (Renderer.Device.CreateBuffer(&bufferDesc))
		{
		case .Ok(let buffer): mObjectUniformBuffer = buffer;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private void CreateSceneBindGroup()
	{
		// Delete old bind group if exists
		if (mSceneBindGroup != null)
		{
			delete mSceneBindGroup;
			mSceneBindGroup = null;
		}

		// Need all resources to be valid
		let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
		let lightingBuffer = mLighting?.LightBuffer?.UniformBuffer;
		let lightDataBuffer = mLighting?.LightBuffer?.LightDataBuffer;
		let clusterInfoBuffer = mLighting?.ClusterGrid?.ClusterLightInfoBuffer;
		let lightIndexBuffer = mLighting?.ClusterGrid?.LightIndexBuffer;

		// Check required resources
		if (cameraBuffer == null || mObjectUniformBuffer == null ||
			lightingBuffer == null || lightDataBuffer == null ||
			clusterInfoBuffer == null || lightIndexBuffer == null)
		{
			return; // Can't create bind group without all resources
		}

		// Build bind group entries
		// Note: Some shadow resources may be null - provide fallbacks or skip
		BindGroupEntry[9] entries = .();

		// b0: Camera uniforms
		entries[0] = BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size);

		// b1: Object uniforms (dynamic offset - bind full buffer, use aligned size per object)
		entries[1] = BindGroupEntry.Buffer(1, mObjectUniformBuffer, 0, AlignedObjectUniformSize);

		// b3: Lighting uniforms
		entries[2] = BindGroupEntry.Buffer(3, lightingBuffer, 0, (uint64)LightingUniforms.Size);

		// t4: Lights storage buffer
		entries[3] = BindGroupEntry.Buffer(4, lightDataBuffer, 0, (uint64)(mLighting.LightBuffer.MaxLights * GPULight.Size));

		// t5: ClusterLightInfo storage buffer (8 bytes per cluster: 2 uint32)
		entries[4] = BindGroupEntry.Buffer(5, clusterInfoBuffer, 0, (uint64)(mLighting.ClusterGrid.Config.TotalClusters * 8));

		// t6: LightIndices storage buffer
		entries[5] = BindGroupEntry.Buffer(6, lightIndexBuffer, 0, (uint64)(mLighting.ClusterGrid.Config.MaxLightsPerCluster * mLighting.ClusterGrid.Config.TotalClusters * 4));

		// Get shadow resources from ShadowRenderer
		let shadowData = mShadowRenderer.GetShadowShaderData();
		let materialSystem = Renderer.MaterialSystem;

		// b5: Shadow uniforms
		if (shadowData.CascadedShadowUniforms != null)
			entries[6] = BindGroupEntry.Buffer(5, shadowData.CascadedShadowUniforms, 0, (uint64)ShadowUniforms.Size);
		else
			entries[6] = BindGroupEntry.Buffer(5, lightingBuffer, 0, (uint64)LightingUniforms.Size); // Fallback

		// t7: Shadow map texture (cascaded shadow map array)
		if (shadowData.CascadedShadowMapView != null)
			entries[7] = BindGroupEntry.Texture(7, shadowData.CascadedShadowMapView);
		else if (materialSystem?.DepthTexture != null)
			entries[7] = BindGroupEntry.Texture(7, materialSystem.DepthTexture); // Fallback
		else
			return; // Can't create without texture

		// s1: Shadow sampler (comparison sampler for PCF)
		if (shadowData.CascadedShadowSampler != null)
			entries[8] = BindGroupEntry.Sampler(1, shadowData.CascadedShadowSampler);
		else if (materialSystem?.DefaultSampler != null)
			entries[8] = BindGroupEntry.Sampler(1, materialSystem.DefaultSampler); // Fallback
		else
			return; // Can't create without sampler

		// Create bind group
		BindGroupDescriptor bgDesc = .()
		{
			Label = "Scene BindGroup",
			Layout = mSceneBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&bgDesc) case .Ok(let bg))
			mSceneBindGroup = bg;
	}

	private static bool sForwardPassDebugPrinted = false;

	private void ExecuteForwardPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view, DepthPrepassFeature depthFeature)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Set forward pipeline
		if (mForwardPipeline != null)
			encoder.SetPipeline(mForwardPipeline);

		// Debug output (once)
		if (!sForwardPassDebugPrinted)
		{
			sForwardPassDebugPrinted = true;
			Console.WriteLine("\n=== Forward Pass Debug ===");
			Console.WriteLine("Pipeline: {}", mForwardPipeline != null ? "OK" : "NULL");
			Console.WriteLine("SceneBindGroup: {}", mSceneBindGroup != null ? "OK" : "NULL");
			Console.WriteLine("ObjectUniformBuffer: {}", mObjectUniformBuffer != null ? "OK" : "NULL");
		}

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Track current bound material to minimize rebinds
		MaterialInstance currentMaterial = null;

		// Get draw commands from batcher (uniforms already uploaded in PrepareObjectUniforms)
		let commands = depthFeature.[Friend]mBatcher.DrawCommands;

		// Render with dynamic offsets
		int32 objectIndex = 0;
		for (let batch in depthFeature.[Friend]mBatcher.OpaqueBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			// Draw each command in this batch
			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= MaxObjectsPerFrame)
					break;

				let cmd = commands[batch.CommandStart + i];

				// Get mesh proxy to access material
				MeshProxy* proxy = null;
				if (cmd.MeshHandle.IsValid)
					proxy = world.GetMesh(cmd.MeshHandle);

				// Get material instance (use default if none assigned)
				MaterialInstance material = proxy?.Material ?? defaultMaterialInstance;

				// Bind material if changed
				if (material != currentMaterial && material != null && materialSystem != null)
				{
					// Prepare material instance (ensures bind group is ready)
					if (materialSystem.PrepareInstance(material) case .Ok(let bindGroup))
					{
						encoder.SetBindGroup(1, bindGroup, default);
						currentMaterial = material;
					}
				}

				// Bind scene bind group with dynamic offset for this object's transforms
				if (mSceneBindGroup != null)
				{
					uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
					encoder.SetBindGroup(0, mSceneBindGroup, dynamicOffsets);
				}

				// Get mesh data
				if (let mesh = Renderer.ResourceManager.GetMesh(cmd.GPUMesh))
				{
					// Bind vertex/index buffers
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

					if (mesh.IndexBuffer != null)
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					else
						encoder.Draw(mesh.VertexCount, 1, 0, 0);

					Renderer.Stats.DrawCalls++;
					Renderer.Stats.TriangleCount += (int32)(mesh.IndexCount / 3);
				}

				objectIndex++;
			}
		}
	}

	private void ExecuteShadowPass(IRenderPassEncoder encoder, RenderWorld world, VisibilityResolver visibility, ShadowPass shadowPass, int32 cascadeIndex)
	{
		// Skip if no pipeline or bind group
		if (mShadowDepthPipeline == null || mShadowBindGroup == null)
			return;

		// Set viewport for shadow map tile
		encoder.SetViewport(
			(float)shadowPass.Viewport.X,
			(float)shadowPass.Viewport.Y,
			(float)shadowPass.Viewport.Width,
			(float)shadowPass.Viewport.Height,
			0.0f, 1.0f
		);

		encoder.SetScissorRect(
			(int32)shadowPass.Viewport.X,
			(int32)shadowPass.Viewport.Y,
			(uint32)shadowPass.Viewport.Width,
			(uint32)shadowPass.Viewport.Height
		);

		// Set shadow pipeline
		encoder.SetPipeline(mShadowDepthPipeline);

		// Calculate cascade VP offset (for dynamic uniform binding 0)
		uint32 cascadeVPOffset = (uint32)((int64)cascadeIndex * (int64)mAlignedSceneUniformSize);

		// Render shadow casters (object transforms already uploaded in PrepareShadowUniforms)
		int32 objectIndex = 0;
		for (let visibleMesh in visibility.VisibleMeshes)
		{
			if (objectIndex >= MaxObjectsPerFrame)
				break;

			if (let proxy = world.GetMesh(visibleMesh.Handle))
			{
				if (!proxy.CastsShadows)
					continue;

				if (let mesh = Renderer.ResourceManager.GetMesh(proxy.MeshHandle))
				{
					// Two dynamic offsets: [0] = cascade VP, [1] = object transforms
					uint32 objectOffset = (uint32)((int64)objectIndex * (int64)AlignedObjectUniformSize);
					uint32[2] dynamicOffsets = .(cascadeVPOffset, objectOffset);
					encoder.SetBindGroup(0, mShadowBindGroup, dynamicOffsets);

					// Bind vertex/index buffers and draw
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					}
					else
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
					}

					Renderer.Stats.ShadowDrawCalls++;
					objectIndex++;
				}
			}
		}
	}

	private void CreateShadowBindGroup()
	{
		// Only create once
		if (mShadowBindGroup != null)
			return;

		if (mShadowBindGroupLayout == null || mShadowUniformBuffer == null || mShadowObjectBuffer == null)
			return;

		// Create bind group entries
		// For dynamic uniform buffers, size is the per-element size that dynamic offset selects
		BindGroupEntry[2] entries = .(
			BindGroupEntry.Buffer(0, mShadowUniformBuffer, 0, mAlignedSceneUniformSize), // Per-cascade VP (dynamic)
			BindGroupEntry.Buffer(1, mShadowObjectBuffer, 0, AlignedObjectUniformSize)   // Per-object transforms (dynamic)
		);

		BindGroupDescriptor bgDesc = .()
		{
			Label = "Shadow BindGroup",
			Layout = mShadowBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&bgDesc) case .Ok(let bg))
			mShadowBindGroup = bg;
	}
}
