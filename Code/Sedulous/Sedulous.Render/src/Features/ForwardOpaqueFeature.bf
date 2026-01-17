namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;

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

	// Pipeline cache (material -> pipeline)
	private Dictionary<MaterialInstance, IRenderPipeline> mPipelineCache = new .() ~ delete _;

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

		// Create forward pipelines
		if (CreateForwardPipelines() case .Err)
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

		// Load forward shaders with default opaque flags
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("forward", .DefaultOpaque | .NormalMap);
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

		// Vertex layout from material system (default to Mesh layout)
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

	protected override void OnShutdown()
	{
		// Clear pipeline cache
		for (let kv in mPipelineCache)
			delete kv.value;
		mPipelineCache.Clear();

		if (mSceneBindGroup != null)
			delete mSceneBindGroup;

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

		// Add shadow passes
		AddShadowPasses(graph, world, depthFeature.Visibility, view);

		// Add forward opaque pass
		graph.AddGraphicsPass("ForwardOpaque")
			.WriteColor(colorHandle, .Clear, .Store, .(0.0f, 0.0f, 0.0f, 1.0f))
			.ReadDepth(depthHandle)
			.NeverCull()
			.SetExecuteCallback(new (encoder) => {
				ExecuteForwardPass(encoder, world, view, depthFeature);
			});
	}

	private void UpdateLighting(RenderWorld world, VisibilityResolver visibility, RenderView view)
	{
		// Update cluster grid
		let inverseProj = Matrix.Invert(view.ProjectionMatrix);
		mLighting.ClusterGrid.Update(view.Width, view.Height, view.NearPlane, view.FarPlane, inverseProj);

		// Update light buffer from visibility
		mLighting.LightBuffer.Update(world, visibility);
		mLighting.LightBuffer.UploadLightData();
		mLighting.LightBuffer.UploadUniforms();

		// Perform light culling (CPU fallback for now)
		mLighting.ClusterGrid.CullLightsCPU(world, visibility);
	}

	private void AddShadowPasses(RenderGraph graph, RenderWorld world, VisibilityResolver visibility, RenderView view)
	{
		if (!mShadowRenderer.EnableShadows)
			return;

		// Get camera proxy for CSM
		CameraProxy* camera = null;
		for (let mesh in visibility.VisibleMeshes)
		{
			// Would get camera from view
			break;
		}

		// Update shadow renderer
		mShadowRenderer.Update(world, visibility, camera);

		// Get shadow passes
		List<ShadowPass> shadowPasses = scope .();
		mShadowRenderer.GetShadowPasses(shadowPasses);

		// Add each shadow pass
		for (let shadowPass in shadowPasses)
		{
			String passName = scope $"Shadow_{shadowPass.Type}_{shadowPass.CascadeIndex}";

			// Import shadow render target
			let shadowTarget = graph.ImportTexture(passName, null, shadowPass.RenderTarget);

			// Copy shadow pass for closure
			ShadowPass passCopy = shadowPass;
			graph.AddGraphicsPass(passName)
				.WriteDepth(shadowTarget)
				.SetExecuteCallback(new (encoder) => {
					ExecuteShadowPass(encoder, world, visibility, passCopy);
				});
		}
	}

	private Result<void> CreateBindGroupLayouts()
	{
		// Scene bind group: camera, lighting, shadows
		// This is pass-specific and stays hardcoded
		BindGroupLayoutEntry[6] sceneEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer }, // Camera
			.() { Binding = 1, Visibility = .Fragment, Type = .UniformBuffer }, // Lighting uniforms
			.() { Binding = 2, Visibility = .Fragment, Type = .StorageBuffer }, // Light buffer
			.() { Binding = 3, Visibility = .Fragment, Type = .StorageBuffer }, // Cluster info
			.() { Binding = 4, Visibility = .Fragment, Type = .StorageBuffer }, // Light indices
			.() { Binding = 5, Visibility = .Fragment, Type = .UniformBuffer } // Shadow uniforms
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

	private void ExecuteForwardPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view, DepthPrepassFeature depthFeature)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Set forward pipeline
		if (mForwardPipeline != null)
			encoder.SetPipeline(mForwardPipeline);

		// Bind scene bind group (camera, lighting, shadows)
		if (mSceneBindGroup != null)
			encoder.SetBindGroup(0, mSceneBindGroup, default);

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Track current bound material to minimize rebinds
		MaterialInstance currentMaterial = null;

		// Get draw commands from batcher
		let commands = depthFeature.[Friend]mBatcher.DrawCommands;

		// Render opaque batches with full shading
		for (let batch in depthFeature.[Friend]mBatcher.OpaqueBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			// Draw each command in this batch
			for (int32 i = 0; i < batch.CommandCount; i++)
			{
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
			}
		}
	}

	private void ExecuteShadowPass(IRenderPassEncoder encoder, RenderWorld world, VisibilityResolver visibility, ShadowPass shadowPass)
	{
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

		// Render shadow casters
		for (let visibleMesh in visibility.VisibleMeshes)
		{
			if (let proxy = world.GetMesh(visibleMesh.Handle))
			{
				if (!proxy.CastsShadows)
					continue;

				if (let mesh = Renderer.ResourceManager.GetMesh(proxy.MeshHandle))
				{
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
				}
			}
		}
	}
}
