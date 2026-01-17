namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;

/// Forward transparent render feature.
/// Renders all transparent geometry with back-to-front sorting.
public class ForwardTransparentFeature : RenderFeatureBase
{
	// Sorted transparent draws
	private List<SortedDraw> mSortedDraws = new .() ~ delete _;

	/// Feature name.
	public override StringView Name => "ForwardTransparent";

	/// Depends on forward opaque (uses same color/depth buffers).
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
	}

	// Transparent render pipelines for different blend modes
	private IRenderPipeline mAlphaBlendPipeline ~ delete _;
	private IRenderPipeline mAdditivePipeline ~ delete _;
	private IRenderPipeline mMultiplyPipeline ~ delete _;
	private IPipelineLayout mTransparentPipelineLayout ~ delete _;

	// Bind group layouts
	private IBindGroupLayout mSceneBindGroupLayout ~ delete _;
	private IBindGroupLayout mObjectBindGroupLayout ~ delete _;

	protected override Result<void> OnInitialize()
	{
		// Create bind group layouts
		if (CreateBindGroupLayouts() case .Err)
			return .Err;

		// Create transparent pipelines for different blend modes
		if (CreateTransparentPipelines() case .Err)
			return .Err;

		return .Ok;
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
			Label = "Transparent Scene BindGroup Layout",
			Entries = sceneEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&sceneDesc))
		{
		case .Ok(let layout): mSceneBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Material bind group layout is provided by MaterialSystem
		// See Renderer.MaterialSystem.DefaultMaterialLayout

		// Per-object bind group: transform matrix
		BindGroupLayoutEntry[1] objectEntries = .(
			.() { Binding = 0, Visibility = .Vertex, Type = .UniformBuffer } // Object transform
		);

		BindGroupLayoutDescriptor objectDesc = .()
		{
			Label = "Transparent Object BindGroup Layout",
			Entries = objectEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&objectDesc))
		{
		case .Ok(let layout): mObjectBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateTransparentPipelines()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Load forward shaders with transparent flags
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("forward", .NormalMap | .DefaultTransparent);
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		// Get material bind group layout from MaterialSystem
		let materialLayout = Renderer.MaterialSystem?.DefaultMaterialLayout;
		if (materialLayout == null)
			return .Ok; // MaterialSystem not initialized yet

		// Create pipeline layout with all bind groups
		IBindGroupLayout[3] layouts = .(mSceneBindGroupLayout, materialLayout, mObjectBindGroupLayout);
		PipelineLayoutDescriptor layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(&layoutDesc))
		{
		case .Ok(let layout): mTransparentPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Vertex layout from material system (default to Mesh layout)
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Create alpha blend pipeline (standard transparency)
		{
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, .AlphaBlend)
			);

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Transparent Alpha Blend Pipeline",
				Layout = mTransparentPipelineLayout,
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
					CullMode = .None // Render both sides for transparent objects
				},
				DepthStencil = .Transparent,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mAlphaBlendPipeline = pipeline;
			case .Err: return .Err;
			}
		}

		// Create additive blend pipeline
		{
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, .Additive)
			);

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Transparent Additive Pipeline",
				Layout = mTransparentPipelineLayout,
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
					CullMode = .None
				},
				DepthStencil = .Transparent,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mAdditivePipeline = pipeline;
			case .Err: return .Err;
			}
		}

		// Create multiply blend pipeline
		{
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, .Multiply)
			);

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Transparent Multiply Pipeline",
				Layout = mTransparentPipelineLayout,
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
					CullMode = .None
				},
				DepthStencil = .Transparent,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mMultiplyPipeline = pipeline;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// Get depth prepass feature for visibility data
		let depthFeature = Renderer.GetFeature<DepthPrepassFeature>();
		if (depthFeature == null)
			return;

		// Get existing resources
		let depthHandle = graph.GetResource("SceneDepth");
		let colorHandle = graph.GetResource("SceneColor");

		if (!depthHandle.IsValid || !colorHandle.IsValid)
			return;

		// Sort transparent objects back-to-front
		SortTransparentDraws(world, depthFeature, view);

		// Add transparent pass
		if (mSortedDraws.Count > 0)
		{
			graph.AddGraphicsPass("ForwardTransparent")
				.WriteColor(colorHandle, .Load, .Store) // Load existing color, blend on top
				.ReadDepth(depthHandle) // Read depth, don't write
				.SetExecuteCallback(new (encoder) => {
					ExecuteTransparentPass(encoder, world, view);
				});
		}
	}

	private void SortTransparentDraws(RenderWorld world, DepthPrepassFeature depthFeature, RenderView view)
	{
		mSortedDraws.Clear();

		let cameraPos = view.CameraPosition;
		let batcher = depthFeature.[Friend]mBatcher;
		let commands = batcher.DrawCommands;

		// Collect transparent draws from transparent batches
		for (let batch in batcher.TransparentBatches)
		{
			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				let cmd = commands[batch.CommandStart + i];

				if (let proxy = world.GetMesh(cmd.MeshHandle))
				{
					// Calculate distance from camera to object center
					let center = (proxy.WorldBounds.Min + proxy.WorldBounds.Max) * 0.5f;
					let distSq = Vector3.DistanceSquared(cameraPos, center);

					mSortedDraws.Add(.()
					{
						ProxyHandle = cmd.MeshHandle,
						MeshHandle = proxy.MeshHandle,
						Material = proxy.Material,
						DistanceSquared = distSq
					});
				}
			}
		}

		// Sort back-to-front (furthest first)
		mSortedDraws.Sort(scope (a, b) => {
			if (a.DistanceSquared > b.DistanceSquared)
				return -1;
			if (a.DistanceSquared < b.DistanceSquared)
				return 1;
			return 0;
		});
	}

	private void ExecuteTransparentPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Bind scene bind group from ForwardOpaqueFeature (shared lighting/camera data)
		let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		if (opaqueFeature != null)
		{
			let sceneBindGroup = opaqueFeature.[Friend]mSceneBindGroup;
			if (sceneBindGroup != null)
				encoder.SetBindGroup(0, sceneBindGroup, default);
		}

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Track current pipeline and material to minimize state changes
		IRenderPipeline currentPipeline = null;
		MaterialInstance currentMaterial = null;

		// Render sorted transparent objects (back-to-front)
		for (let sortedDraw in mSortedDraws)
		{
			if (let proxy = world.GetMesh(sortedDraw.ProxyHandle))
			{
				if (let mesh = Renderer.ResourceManager.GetMesh(sortedDraw.MeshHandle))
				{
					// Get material instance (use default if none assigned)
					MaterialInstance material = sortedDraw.Material ?? defaultMaterialInstance;

					// Select pipeline based on material blend mode
					IRenderPipeline targetPipeline = mAlphaBlendPipeline;
					if (material != null)
					{
						switch (material.BlendMode)
						{
						case .Additive:
							targetPipeline = mAdditivePipeline;
						case .Multiply:
							targetPipeline = mMultiplyPipeline;
						default:
							targetPipeline = mAlphaBlendPipeline;
						}
					}

					// Set pipeline if changed
					if (targetPipeline != currentPipeline && targetPipeline != null)
					{
						encoder.SetPipeline(targetPipeline);
						currentPipeline = targetPipeline;
					}

					// Bind material if changed
					if (material != currentMaterial && material != null && materialSystem != null)
					{
						if (materialSystem.PrepareInstance(material) case .Ok(let bindGroup))
						{
							encoder.SetBindGroup(1, bindGroup, default);
							currentMaterial = material;
						}
					}

					// Bind per-object bind group with transform
					if (proxy.ObjectBindGroup != null)
						encoder.SetBindGroup(2, proxy.ObjectBindGroup, default);

					// Bind vertex/index buffers
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

					// Draw
					if (mesh.IndexBuffer != null)
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					else
						encoder.Draw(mesh.VertexCount, 1, 0, 0);

					Renderer.Stats.DrawCalls++;
					Renderer.Stats.TransparentDrawCalls++;
				}
			}
		}
	}

	/// Sorted draw entry.
	private struct SortedDraw
	{
		public MeshProxyHandle ProxyHandle;
		public GPUMeshHandle MeshHandle;
		public MaterialInstance Material;
		public float DistanceSquared;
	}
}
