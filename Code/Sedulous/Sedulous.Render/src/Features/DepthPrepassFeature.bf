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
	private IBindGroup mDepthBindGroup ~ delete _;
	private IBuffer mObjectUniformBuffer ~ delete _;
	private IRenderPipeline mDepthPipeline ~ delete _;
	private IRenderPipeline mDepthSkinnedPipeline ~ delete _;
	private IRenderPipeline mDepthInstancedPipeline ~ delete _;

	// Constants for per-object uniforms
	private const int MaxObjectsPerFrame = 1024;
	private const uint64 ObjectUniformAlignment = 256;
	private const uint64 ObjectUniformSize = 208; // 3 matrices (192) + padding
	private const uint64 AlignedObjectUniformSize = ((ObjectUniformSize + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

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

		// Create object uniform buffer
		if (CreateObjectUniformBuffer() case .Err)
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

		// Vertex layout - Mesh format matches Sedulous.Geometry.StaticMesh
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
		if (mDepthBindGroup != null)
		{
			delete mDepthBindGroup;
			mDepthBindGroup = null;
		}

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

		// Create/update bind group if needed
		if (mDepthBindGroup == null)
			CreateDepthBindGroup();

		// Upload object uniforms BEFORE the render pass
		PrepareObjectUniforms();

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
			.() // Object uniforms (with dynamic offset)
			{
				Binding = 1,
				Visibility = .Vertex,
				Type = .UniformBuffer,
				HasDynamicOffset = true
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

	private Result<void> CreateObjectUniformBuffer()
	{
		// Create buffer for per-object uniforms with space for MaxObjectsPerFrame objects
		let bufferSize = MaxObjectsPerFrame * (int)AlignedObjectUniformSize;
		BufferDescriptor bufDesc = .((uint64)bufferSize, .Uniform | .CopyDst);

		switch (Renderer.Device.CreateBuffer(&bufDesc))
		{
		case .Ok(let buffer): mObjectUniformBuffer = buffer;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private void CreateDepthBindGroup()
	{
		// Delete old bind group if exists
		if (mDepthBindGroup != null)
		{
			delete mDepthBindGroup;
			mDepthBindGroup = null;
		}

		// Get required buffers
		let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
		if (cameraBuffer == null || mObjectUniformBuffer == null)
			return;

		// Build bind group entries
		BindGroupEntry[2] entries = .(
			BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Buffer(1, mObjectUniformBuffer, 0, AlignedObjectUniformSize)
		);

		BindGroupDescriptor bgDesc = .()
		{
			Label = "DepthPrepass BindGroup",
			Layout = mBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&bgDesc) case .Ok(let bg))
			mDepthBindGroup = bg;
	}

	private void PrepareObjectUniforms()
	{
		// Upload all object transforms to the uniform buffer BEFORE the render pass
		let commands = mBatcher.DrawCommands;

		int32 objectIndex = 0;
		for (let batch in mBatcher.OpaqueBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= MaxObjectsPerFrame)
					break;

				let cmd = commands[batch.CommandStart + i];

				// Create object uniforms with the object's world transform
				ObjectUniforms objectUniforms = .()
				{
					WorldMatrix = cmd.WorldMatrix,
					PrevWorldMatrix = cmd.PrevWorldMatrix,
					NormalMatrix = cmd.NormalMatrix,
					ObjectID = (uint32)objectIndex,
					MaterialID = 0,
					_Padding = default
				};

				// Upload to buffer at aligned offset
				let offset = (uint64)(objectIndex * (int32)AlignedObjectUniformSize);
				Renderer.Device.Queue.WriteBuffer(mObjectUniformBuffer, offset, Span<uint8>((uint8*)&objectUniforms, ObjectUniformSize));

				objectIndex++;
			}
		}
	}

	private void ExecuteDepthPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Set depth pipeline
		if (mDepthPipeline != null)
			encoder.SetPipeline(mDepthPipeline);

		// Get draw commands from batcher (uniforms already uploaded in PrepareObjectUniforms)
		let commands = mBatcher.DrawCommands;

		// Render opaque batches with dynamic offsets
		int32 objectIndex = 0;
		for (let batch in mBatcher.OpaqueBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			// Draw each command in this batch
			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= MaxObjectsPerFrame)
					break;

				let cmd = commands[batch.CommandStart + i];

				// Get mesh data
				if (let mesh = Renderer.ResourceManager.GetMesh(cmd.GPUMesh))
				{
					// Bind depth bind group with dynamic offset for this object
					if (mDepthBindGroup != null)
					{
						uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
						encoder.SetBindGroup(0, mDepthBindGroup, dynamicOffsets);
					}

					// Bind vertex/index buffers
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

					if (mesh.IndexBuffer != null)
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					else
						encoder.Draw(mesh.VertexCount, 1, 0, 0);

					Renderer.Stats.DrawCalls++;
					objectIndex++;
				}
			}
		}
	}

	/// Per-object uniform data for depth prepass.
	[CRepr]
	struct ObjectUniforms
	{
		public Matrix WorldMatrix;
		public Matrix PrevWorldMatrix;
		public Matrix NormalMatrix;
		public uint32 ObjectID;
		public uint32 MaterialID;
		public float[2] _Padding;
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
