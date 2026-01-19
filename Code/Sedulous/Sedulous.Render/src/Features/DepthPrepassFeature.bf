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
	private IBindGroup[RenderConfig.FrameBufferCount] mDepthBindGroups;  // Per-frame bind groups
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers; // Per-frame uniform buffers
	private IRenderPipeline mDepthPipeline ~ delete _;
	private IRenderPipeline mDepthSkinnedPipeline ~ delete _;
	private IRenderPipeline mDepthInstancedPipeline ~ delete _;

	// Instance buffer manager for GPU instancing
	private InstanceBufferManager mInstanceBufferManager ~ { if (_ != null) { _.Shutdown(); delete _; } };
	private bool mInstancingEnabled = false;

	// Constants for per-object uniforms
	private static int MaxObjectsPerFrame => RenderConfig.MaxOpaqueObjectsPerFrame;
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
	private bool mEnableInstancing = true;

	/// Feature name.
	public override StringView Name => "DepthPrepass";

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => Renderer.RenderFrameContext?.FrameIndex ?? 0;

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

	/// Gets or sets whether GPU instancing is enabled.
	public bool EnableInstancing
	{
		get => mEnableInstancing;
		set => mEnableInstancing = value;
	}

	/// Gets whether instancing is currently active (enabled and available).
	public bool InstancingActive => mEnableInstancing && mInstancingEnabled;

	/// Gets the instance buffer for a frame (for use by other features).
	public IBuffer GetInstanceBuffer(int32 frameIndex) => mInstanceBufferManager?.GetBuffer(frameIndex);

	/// Gets the draw batcher.
	public DrawBatcher Batcher => mBatcher;

	/// Depends on GPU skinning (skinned vertex buffers must be ready).
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("GPUSkinning");
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

		// Initialize instance buffer manager for GPU instancing
		if (mEnableInstancing)
		{
			mInstanceBufferManager = new InstanceBufferManager();
			if (mInstanceBufferManager.Initialize(Renderer.Device) case .Ok)
			{
				// Try to create instanced pipeline
				if (CreateInstancedDepthPipeline() case .Ok)
					mInstancingEnabled = true;
			}
		}

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

	private Result<void> CreateInstancedDepthPipeline()
	{
		// Skip if shader system not initialized or pipeline layout not ready
		if (Renderer.ShaderSystem == null || mPipelineLayout == null)
			return .Err;

		// Load depth shaders with INSTANCED variant
		let shaderPairResult = Renderer.ShaderSystem.GetShaderPair("depth", .DepthTest | .DepthWrite | .Instanced);
		if (shaderPairResult case .Err)
			return .Err; // Instanced shader variant not available

		let (vertShader, fragShader) = shaderPairResult.Value;

		// Vertex layout for depth instancing:
		// - Mesh buffer uses stride 48 (full Mesh format) but only declares Position/Normal/UV (what shader uses)
		// - DXC assigns locations sequentially, so instance data starts at location 3 (after UV)
		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2)   // UV
		);
		Sedulous.RHI.VertexAttribute[4] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),   // WorldRow0
			.(VertexFormat.Float4, 16, 4),  // WorldRow1
			.(VertexFormat.Float4, 32, 5),  // WorldRow2
			.(VertexFormat.Float4, 48, 6)   // WorldRow3
		);
		VertexBufferLayout[2] vertexBuffers = .(
			.(48, meshAttrs, .Vertex),              // Mesh buffer (stride 48, but only 3 attrs declared)
			.(64, instanceAttrs, .Instance)         // Instance buffer
		);

		// Instanced depth pipeline descriptor
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = "DepthPrepass Instanced Pipeline",
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
		case .Ok(let pipeline): mDepthInstancedPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mDepthBindGroups[i] != null) { delete mDepthBindGroups[i]; mDepthBindGroups[i] = null; }
			if (mObjectUniformBuffers[i] != null) { delete mObjectUniformBuffers[i]; mObjectUniformBuffers[i] = null; }
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

		// Capture frame index for consistent multi-buffering
		let frameIndex = FrameIndex;

		// Create/update bind group for current frame if needed
		if (mDepthBindGroups[frameIndex] == null)
			CreateDepthBindGroup(frameIndex);

		// Upload object uniforms BEFORE the render pass
		PrepareObjectUniforms(frameIndex);

		// Upload instance data if instancing is active
		if (InstancingActive && mInstanceBufferManager != null)
			mInstanceBufferManager.UploadInstanceData(frameIndex, mBatcher);

		// Add depth prepass
		graph.AddGraphicsPass("DepthPrepass")
			.WriteDepth(depthHandle)
			.NeverCull()
			.SetExecuteCallback(new (encoder) => {
				ExecuteDepthPass(encoder, world, view, frameIndex);
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
		// Create per-frame buffers for per-object uniforms with space for MaxObjectsPerFrame objects
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		let bufferSize = MaxObjectsPerFrame * (int)AlignedObjectUniformSize;
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDescriptor bufDesc = .()
			{
				Size = (uint64)bufferSize,
				Usage = .Uniform,
				MemoryAccess = .Upload // CPU-mappable
			};

			switch (Renderer.Device.CreateBuffer(&bufDesc))
			{
			case .Ok(let buffer): mObjectUniformBuffers[i] = buffer;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private void CreateDepthBindGroup(int32 frameIndex)
	{
		// Delete old bind group if exists
		if (mDepthBindGroups[frameIndex] != null)
		{
			delete mDepthBindGroups[frameIndex];
			mDepthBindGroups[frameIndex] = null;
		}

		// Get required buffers - use the frame-specific scene buffer and object buffer
		let frameContext = Renderer.RenderFrameContext;
		if (frameContext == null)
			return;

		// Need to get the scene buffer for this specific frame index
		let cameraBuffer = frameContext.SceneUniformBuffer; // This already returns the buffer for the current frame
		let objectBuffer = mObjectUniformBuffers[frameIndex];
		if (cameraBuffer == null || objectBuffer == null)
			return;

		// Build bind group entries
		BindGroupEntry[2] entries = .(
			BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Buffer(1, objectBuffer, 0, AlignedObjectUniformSize)
		);

		BindGroupDescriptor bgDesc = .()
		{
			Label = "DepthPrepass BindGroup",
			Layout = mBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&bgDesc) case .Ok(let bg))
			mDepthBindGroups[frameIndex] = bg;
	}

	private void PrepareObjectUniforms(int32 frameIndex)
	{
		// Upload all object transforms to the uniform buffer BEFORE the render pass
		// Use Map/Unmap to avoid command buffer creation
		let commands = mBatcher.DrawCommands;
		let skinnedCommands = mBatcher.SkinnedCommands;

		// Use the current frame's buffer
		let buffer = mObjectUniformBuffers[frameIndex];
		if (buffer == null)
			return;

		if (let bufferPtr = buffer.Map())
		{
			int32 objectIndex = 0;

			// Static meshes
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

					// Copy to mapped buffer at aligned offset
					let offset = (uint64)(objectIndex * (int32)AlignedObjectUniformSize);
					// Bounds check against actual buffer size
					Runtime.Assert(offset + ObjectUniformSize <= buffer.Size, scope $"DepthPrepass object uniform write (offset {offset} + size {ObjectUniformSize}) exceeds buffer size ({buffer.Size})");
					Internal.MemCpy((uint8*)bufferPtr + offset, &objectUniforms, ObjectUniformSize);

					objectIndex++;
				}
			}

			// Skinned meshes
			for (let batch in mBatcher.SkinnedBatches)
			{
				if (batch.CommandCount == 0)
					continue;

				for (int32 i = 0; i < batch.CommandCount; i++)
				{
					if (objectIndex >= MaxObjectsPerFrame)
						break;

					let cmd = skinnedCommands[batch.CommandStart + i];

					ObjectUniforms objectUniforms = .()
					{
						WorldMatrix = cmd.WorldMatrix,
						PrevWorldMatrix = cmd.PrevWorldMatrix,
						NormalMatrix = cmd.NormalMatrix,
						ObjectID = (uint32)objectIndex,
						MaterialID = 0,
						_Padding = default
					};

					let offset = (uint64)(objectIndex * (int32)AlignedObjectUniformSize);
					Runtime.Assert(offset + ObjectUniformSize <= buffer.Size, scope $"DepthPrepass skinned object uniform write (offset {offset} + size {ObjectUniformSize}) exceeds buffer size ({buffer.Size})");
					Internal.MemCpy((uint8*)bufferPtr + offset, &objectUniforms, ObjectUniformSize);

					objectIndex++;
				}
			}

			buffer.Unmap();
		}
	}

	private void ExecuteDepthPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view, int32 frameIndex)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Track object index for uniform buffer dynamic offsets
		var objectIndex = (int32)0;

		// Use instanced path if available and has instance groups
		if (InstancingActive && mDepthInstancedPipeline != null && mBatcher.OpaqueInstanceGroups.Length > 0)
		{
			ExecuteInstancedDepthPass(encoder, frameIndex);
			// Instanced path doesn't use uniform buffer for static meshes,
			// but skinned uniforms are still uploaded after static in PrepareObjectUniforms
			objectIndex = (int32)mBatcher.DrawCommands.Length;
		}
		else
		{
			// Fall back to non-instanced path
			ExecuteNonInstancedDepthPass(encoder, frameIndex, ref objectIndex);
		}

		// Render skinned meshes (always non-instanced)
		RenderSkinnedMeshesDepth(encoder, world, frameIndex, ref objectIndex);
	}

	private void ExecuteInstancedDepthPass(IRenderPassEncoder encoder, int32 frameIndex)
	{
		// Set instanced depth pipeline
		encoder.SetPipeline(mDepthInstancedPipeline);

		// Get instance buffer for this frame
		let instanceBuffer = mInstanceBufferManager.GetBuffer(frameIndex);
		if (instanceBuffer == null)
			return;

		// Bind depth bind group for camera uniforms (dynamic offset 0 - object uniforms not used with instancing)
		let bindGroup = mDepthBindGroups[frameIndex];
		if (bindGroup != null)
		{
			uint32[1] dynamicOffsets = .(0);
			encoder.SetBindGroup(0, bindGroup, dynamicOffsets);
		}

		// Render opaque instance groups
		for (let group in mBatcher.OpaqueInstanceGroups)
		{
			if (group.InstanceCount == 0)
				continue;

			// Get mesh data
			if (let mesh = Renderer.ResourceManager.GetMesh(group.GPUMesh))
			{
				// Bind vertex buffers: slot 0 = mesh, slot 1 = instance data
				encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
				encoder.SetVertexBuffer(1, instanceBuffer, (uint64)(group.InstanceStart * (int32)InstanceData.Size));

				if (mesh.IndexBuffer != null)
				{
					encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
					encoder.DrawIndexed(mesh.IndexCount, (uint32)group.InstanceCount, 0, 0, 0);
				}
				else
				{
					encoder.Draw(mesh.VertexCount, (uint32)group.InstanceCount, 0, 0);
				}

				Renderer.Stats.DrawCalls++;
				Renderer.Stats.InstanceCount += group.InstanceCount;
			}
		}
	}

	private void ExecuteNonInstancedDepthPass(IRenderPassEncoder encoder, int32 frameIndex, ref int32 objectIndex)
	{
		// Set depth pipeline
		if (mDepthPipeline != null)
			encoder.SetPipeline(mDepthPipeline);

		// Get draw commands from batcher (uniforms already uploaded in PrepareObjectUniforms)
		let commands = mBatcher.DrawCommands;

		// Get current frame's bind group
		let bindGroup = mDepthBindGroups[frameIndex];

		// Render opaque batches with dynamic offsets
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
					if (bindGroup != null)
					{
						uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
						encoder.SetBindGroup(0, bindGroup, dynamicOffsets);
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

	private void RenderSkinnedMeshesDepth(IRenderPassEncoder encoder, RenderWorld world, int32 frameIndex, ref int32 objectIndex)
	{
		// Get GPU skinning feature to access skinned vertex buffers
		let skinningFeature = Renderer.GetFeature<GPUSkinningFeature>();
		if (skinningFeature == null)
			return;

		// Switch to non-instanced pipeline for skinned meshes
		// (instanced pipeline may still be bound from previous pass)
		if (mDepthPipeline != null)
			encoder.SetPipeline(mDepthPipeline);

		let skinnedCommands = mBatcher.SkinnedCommands;

		// Get current frame's bind group
		let bindGroup = mDepthBindGroups[frameIndex];

		for (let batch in mBatcher.SkinnedBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= MaxObjectsPerFrame)
					break;

				let cmd = skinnedCommands[batch.CommandStart + i];

				// Get the skinned vertex buffer from GPU skinning feature
				let skinnedVertexBuffer = skinningFeature.GetSkinnedVertexBuffer(cmd.MeshHandle);
				if (skinnedVertexBuffer == null)
					continue;

				// Bind depth bind group with dynamic offset
				if (bindGroup != null)
				{
					uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
					encoder.SetBindGroup(0, bindGroup, dynamicOffsets);
				}

				// Bind the skinned vertex buffer
				encoder.SetVertexBuffer(0, skinnedVertexBuffer, 0);

				// Get original mesh for index buffer (indices don't change with skinning)
				if (let mesh = Renderer.ResourceManager.GetMesh(cmd.GPUMesh))
				{
					if (mesh.IndexBuffer != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					}
					else
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
					}

					Renderer.Stats.DrawCalls++;
				}

				objectIndex++;
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
