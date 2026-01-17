namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;

/// Depth prepass render feature.
/// Renders depth-only for all opaque geometry to enable:
/// - Early-Z rejection in forward pass
/// - Hi-Z pyramid generation for occlusion culling
public class DepthPrepassFeature : RenderFeatureBase
{
	// Resources
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IRenderPipeline mDepthPipeline ~ delete _;
	private IRenderPipeline mDepthSkinnedPipeline ~ delete _;
	private IRenderPipeline mDepthInstancedPipeline ~ delete _;

	// Visibility
	private VisibilityResolver mVisibility = new .() ~ delete _;
	private FrustumCuller mCuller = new .() ~ delete _;
	private DrawBatcher mBatcher = new .() ~ delete _;

	// Hi-Z resources
	private HiZOcclusionCuller mHiZCuller ~ delete _;

	// Configuration
	private bool mEnableHiZ = true;

	/// Feature name.
	public override StringView Name => "DepthPrepass";

	/// Gets the Hi-Z culler.
	public HiZOcclusionCuller HiZCuller => mHiZCuller;

	/// Gets the visibility resolver.
	public VisibilityResolver Visibility => mVisibility;

	/// Gets or sets whether Hi-Z occlusion culling is enabled.
	public bool EnableHiZ
	{
		get => mEnableHiZ;
		set => mEnableHiZ = value;
	}

	/// No dependencies - depth prepass runs first.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		// No dependencies
	}

	protected override Result<void> OnInitialize()
	{
		// Initialize Hi-Z culler (with default size, will be resized on first use)
		mHiZCuller = new HiZOcclusionCuller();
		if (mHiZCuller.Initialize(Renderer.Device, 1920, 1080, Renderer.ShaderSystem) case .Err)
			return .Err;

		// Create bind group layout for depth pass
		if (CreateBindGroupLayout() case .Err)
			return .Err;

		// Create depth pipelines
		if (CreateDepthPipelines() case .Err)
			return .Err;

		return .Ok;
	}

	// Pipeline layout
	private IPipelineLayout mPipelineLayout ~ delete _;

	private Result<void> CreateDepthPipelines()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Load depth shaders
		let shaderPairResult = Renderer.ShaderSystem.GetShaderPair("depth", .DepthTest | .DepthWrite);
		if (shaderPairResult case .Err)
			return .Ok; // Shaders not available yet, will create lazily

		let (vertShader, fragShader) = shaderPairResult.Value;

		// Create pipeline layout from bind group layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(&layoutDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Vertex layout from material system (default to Mesh layout)
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Depth pipeline descriptor
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = "DepthPrepass Pipeline",
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = default // No color targets for depth-only
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = .Opaque,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mDepthPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		if (mHiZCuller != null)
			mHiZCuller.Dispose();
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// Create/get depth buffer
		let depthDesc = TextureResourceDesc(view.Width, view.Height, Renderer.DepthFormat, .DepthStencil | .Sampled);

		let depthHandle = graph.CreateTexture("SceneDepth", depthDesc);

		// Perform CPU frustum culling
		mCuller.SetFrustum(view.ViewProjectionMatrix);

		mVisibility.Clear();
		mVisibility.Resolve(world, view.ViewProjectionMatrix, view.CameraPosition);

		// Batch draws by material/state
		mBatcher.Clear();
		mBatcher.Build(world, mVisibility);

		// Add depth prepass
		graph.AddGraphicsPass("DepthPrepass")
			.WriteDepth(depthHandle)
			.NeverCull()
			.SetExecuteCallback(new (encoder) => {
				ExecuteDepthPass(encoder, world, view);
			});

		// Add Hi-Z generation pass if enabled
		if (mEnableHiZ && mHiZCuller.IsInitialized && mHiZCuller.GPUBuildAvailable)
		{
			// Hi-Z needs the depth buffer as input
			// Capture graph and depth handle for use in callback
			RenderGraph graphRef = graph;
			RGResourceHandle depthRef = depthHandle;

			graph.AddComputePass("HiZGenerate")
				.ReadTexture(depthHandle)
				.SetComputeCallback(new [=](encoder) => {
					let depthView = graphRef.GetTextureView(depthRef);
					ExecuteHiZGeneration(encoder, depthView);
				});
		}
	}

	private Result<void> CreateBindGroupLayout()
	{
		// Bind group for depth pass: per-object transforms
		BindGroupLayoutEntry[2] entries = .(
			.() // Camera uniforms
			{
				Binding = 0,
				Visibility = .Vertex,
				Type = .UniformBuffer
			},
			.() // Object uniforms
			{
				Binding = 1,
				Visibility = .Vertex,
				Type = .UniformBuffer
			}
		);

		BindGroupLayoutDescriptor desc = .()
		{
			Label = "DepthPrepass BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&desc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private void ExecuteDepthPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Set depth pipeline
		if (mDepthPipeline != null)
			encoder.SetPipeline(mDepthPipeline);

		// Get draw commands from batcher
		let commands = mBatcher.DrawCommands;

		// Render opaque batches
		for (let batch in mBatcher.OpaqueBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			// Draw each command in this batch
			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				let cmd = commands[batch.CommandStart + i];

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
				}
			}
		}
	}

	private void ExecuteHiZGeneration(IComputePassEncoder encoder, ITextureView depthView)
	{
		if (depthView == null)
			return;

		// Generate Hi-Z pyramid from depth buffer
		mHiZCuller.BuildPyramid(encoder, depthView);
		Renderer.Stats.ComputeDispatches++;
	}
}
