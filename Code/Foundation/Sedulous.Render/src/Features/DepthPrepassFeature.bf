namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.Profiler;
using Sedulous.RenderGraph;

/// Depth prepass render feature.
/// Renders depth-only for all opaque geometry to enable:
/// - Early-Z rejection in forward pass
/// - Hi-Z pyramid generation for occlusion culling
public class DepthPrepassFeature : RenderFeatureBase
{
	// Resources
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mDepthBindGroups;  // Per-frame, per-view bind groups
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers; // Per-frame uniform buffers
	private IRenderPipeline mDepthPipeline;
	private IRenderPipeline mDepthSkinnedPipeline;
	private IRenderPipeline mDepthInstancedPipeline;

	// Instance buffer manager for GPU instancing
	private InstanceBufferManager mInstanceBufferManager ~ { if (_ != null) { _.Shutdown(); delete _; } };
	private bool mInstancingEnabled = false;
	private bool mWorldInstancingEnabled = true;

	// Constants for per-object uniforms
	private static int MaxObjectsPerFrame => RenderConfig.MaxOpaqueObjectsPerFrame;
	private const uint64 ObjectUniformAlignment = 256;
	private const uint64 ObjectUniformSize = 144; // 2 matrices (128) + 2 uint32 (8) + 2 float (8)
	private const uint64 AlignedObjectUniformSize = ((ObjectUniformSize + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

	// Visibility and batching now owned by RenderSystem
	// Access via Renderer.Visibility and Renderer.Batcher

	// Hi-Z resources
	private HiZOcclusionCuller mHiZCuller ~ delete _;

	// Configuration
	private bool mEnableHiZ = true;
	private bool mEnableInstancing = true;

	/// Feature name.
	public override StringView Name => "DepthPrepass";

	/// Gets the Hi-Z culler.
	public HiZOcclusionCuller HiZCuller => mHiZCuller;

	/// Gets the visibility resolver (owned by RenderSystem).
	public VisibilityResolver Visibility => Renderer.Visibility;

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

	/// Gets whether instancing is currently active (enabled, available, and world allows it).
	public bool InstancingActive => mEnableInstancing && mInstancingEnabled && mWorldInstancingEnabled;

	/// Gets the instance buffer for a frame (for use by other features).
	public IBuffer GetInstanceBuffer(int32 frameIndex) => mInstanceBufferManager?.GetBuffer(frameIndex);

	/// Gets the draw batcher (owned by RenderSystem).
	public DrawBatcher Batcher => Renderer.Batcher;

	/// Depends on GPU skinning (skinned vertex buffers must be ready).
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("GPUSkinning");
	}

	protected override Result<void> OnInitialize(InitContext initCtx)
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
	private IPipelineLayout mPipelineLayout;

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
		PipelineLayoutDesc layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(layoutDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Vertex layout - Mesh format matches Sedulous.Geometry.StaticMesh
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Depth pipeline descriptor
		RenderPipelineDesc pipelineDesc = .()
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
			DepthStencil = DepthStencilState.DepthDefault(Renderer.DepthFormat),
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(pipelineDesc))
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
		// - Mesh buffer uses full Mesh format (48 bytes) with all attributes
		// - Instance data starts at location 5 (after Color=3, Tangent=4)
		Sedulous.RHI.VertexAttribute[5] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),            // Position
			.(VertexFormat.Float3, 12, 1),           // Normal
			.(VertexFormat.Float2, 24, 2),           // UV
			.(VertexFormat.UByte4Normalized, 32, 3), // Color
			.(VertexFormat.Float3, 36, 4)            // Tangent
		);
		Sedulous.RHI.VertexAttribute[4] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 5),   // WorldRow0
			.(VertexFormat.Float4, 16, 6),  // WorldRow1
			.(VertexFormat.Float4, 32, 7),  // WorldRow2
			.(VertexFormat.Float4, 48, 8)   // WorldRow3
		);
		VertexBufferLayout[2] vertexBuffers = .(
			.(48, meshAttrs, .Vertex),
			.(64, instanceAttrs, .Instance)
		);

		// Instanced depth pipeline descriptor
		RenderPipelineDesc pipelineDesc = .()
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
			DepthStencil = DepthStencilState.DepthDefault(Renderer.DepthFormat),
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(pipelineDesc))
		{
		case .Ok(let pipeline): mDepthInstancedPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		let device = Renderer.Device;

		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mDepthBindGroups[i] != null) { device.DestroyBindGroup(ref mDepthBindGroups[i]); }
		}
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mObjectUniformBuffers[i] != null) { device.DestroyBuffer(ref mObjectUniformBuffers[i]); }
		}

		if (mHiZCuller != null)
			mHiZCuller.Dispose();

		device.DestroyBindGroupLayout(ref mBindGroupLayout);
		device.DestroyRenderPipeline(ref mDepthPipeline);
		device.DestroyRenderPipeline(ref mDepthSkinnedPipeline);
		device.DestroyRenderPipeline(ref mDepthInstancedPipeline);
		device.DestroyPipelineLayout(ref mPipelineLayout);
	}

	/// Prepares shared frame data: object uniforms, instance data.
	/// Visibility and batching now handled by RenderSystem before this is called.
	public override void PrepareFrame(Span<RenderView> views, RenderWorld world, int32 frameIndex)
	{
		using (SProfiler.Begin("DepthPrepass.PrepareFrame"))
		{
			mWorldInstancingEnabled = world.InstancingEnabled;

			// Upload object uniforms (shared across views)
			using (SProfiler.Begin("PrepareUniforms"))
				PrepareObjectUniforms(frameIndex);

			// Upload instance data if instancing is active
			if (InstancingActive && mInstanceBufferManager != null)
			{
				using (SProfiler.Begin("UploadInstanceData"))
					mInstanceBufferManager.UploadInstanceData(frameIndex, Batcher);
			}
		}
	}

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderWorld world)
	{
		using (SProfiler.Begin("DepthPrepass.AddPasses"))
		{
			// Create/get depth buffer (per-view dimensions)
			let depthDesc = RGTextureDesc(Renderer.DepthFormat, view.Width, view.Height) { Usage = .DepthStencil | .Sampled };
			let depthHandle = graph.CreateTransient("SceneDepth", depthDesc);

			let frameIndex = view.FrameIndex;
			let bgIndex = view.GetBindGroupIndex();

			// Visibility and batching handled by RenderSystem before AddPasses.
			// Single-view path: upload object uniforms and instance data here.
			if (view.ViewCount <= 1)
			{
				mWorldInstancingEnabled = world.InstancingEnabled;

				using (SProfiler.Begin("PrepareUniforms"))
					PrepareObjectUniforms(frameIndex);

				if (InstancingActive && mInstanceBufferManager != null)
				{
					using (SProfiler.Begin("UploadInstanceData"))
						mInstanceBufferManager.UploadInstanceData(frameIndex, Batcher);
				}
			}

			// Create/update bind group for current frame+view if needed
			if (mDepthBindGroups[bgIndex] == null)
				CreateDepthBindGroup(frameIndex, view);

			// Add depth prepass
			graph.AddRenderPass("DepthPrepass", scope (builder) => {
				builder.SetDepthTarget(depthHandle, .Clear, .Store);
				builder.NeverCull();
				builder.SetExecute(new /*[&, =frameIndex, =bgIndex]*/(encoder) => {
					ExecuteDepthPass(encoder, world, view, frameIndex, bgIndex);
				});
			});

			// Add Hi-Z generation pass if enabled
			if (mEnableHiZ && mHiZCuller.IsInitialized && mHiZCuller.GPUBuildAvailable)
			{
				// Hi-Z needs the depth buffer as input
				// Capture graph and depth handle for use in callback
				RenderGraph graphRef = graph;
				RGHandle depthRef = depthHandle;

				graph.AddComputePass("HiZGenerate", scope (builder) => {
					builder.ReadTexture(depthHandle);
					builder.SetComputeExecute(new [=](encoder) => {
						let depthView = graphRef.GetTextureView(depthRef);
						ExecuteHiZGeneration(encoder, depthView);
					});
				});
			}
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

		BindGroupLayoutDesc desc = .()
		{
			Label = "DepthPrepass BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(desc))
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
			BufferDesc bufDesc = .()
			{
				Label = "DepthPrepass Object Uniforms",
				Size = (uint64)bufferSize,
				Usage = .Uniform,
				Memory = .CpuToGpu // CPU-mappable
			};

			switch (Renderer.Device.CreateBuffer(bufDesc))
			{
			case .Ok(let buffer): mObjectUniformBuffers[i] = buffer;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private void CreateDepthBindGroup(int32 frameIndex, ViewContext view)
	{
		let bgIndex = view.GetBindGroupIndex();

		// Destroy old bind group if exists
		if (mDepthBindGroups[bgIndex] != null)
		{
			Renderer.Device.DestroyBindGroup(ref mDepthBindGroups[bgIndex]);
		}

		// Camera buffer is per-view (SceneUniformBuffer uses active view index)
		let cameraBuffer = view.SceneUniformBuffer;
		let objectBuffer = mObjectUniformBuffers[frameIndex];
		if (cameraBuffer == null || objectBuffer == null)
			return;

		// Build bind group entries
		BindGroupEntry[2] entries = .(
			BindGroupEntry.Buffer(/*0,*/cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Buffer(/*1,*/objectBuffer, 0, AlignedObjectUniformSize)
		);

		BindGroupDesc bgDesc = .()
		{
			Label = "DepthPrepass BindGroup",
			Layout = mBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(bgDesc) case .Ok(let bg))
			mDepthBindGroups[bgIndex] = bg;
	}

	private void PrepareObjectUniforms(int32 frameIndex)
	{
		// Upload object transforms to the uniform buffer BEFORE the render pass
		// Use Map/Unmap to avoid command buffer creation
		let skinnedCommands = Batcher.SkinnedCommands;

		// Use the current frame's buffer
		let buffer = mObjectUniformBuffers[frameIndex];
		if (buffer == null)
			return;

		if (let bufferPtr = buffer.Map())
		{
			int32 objectIndex = 0;

			// Static meshes - SKIP if instancing is active (instance buffer has transforms)
			if (!InstancingActive)
			{
				let commands = Batcher.DrawCommands;
				for (let batch in Batcher.OpaqueBatches)
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

							ObjectID = (uint32)objectIndex,
							MaterialID = 0,
							_Padding = default
						};

						// Copy to mapped buffer at aligned offset
						let offset = (uint64)(objectIndex * (int32)AlignedObjectUniformSize);
						Runtime.Assert(offset + ObjectUniformSize <= buffer.Size, scope $"DepthPrepass object uniform write (offset {offset} + size {ObjectUniformSize}) exceeds buffer size ({buffer.Size})");
						Internal.MemCpy((uint8*)bufferPtr + offset, &objectUniforms, ObjectUniformSize);

						objectIndex++;
					}
				}
			}

			// Skinned meshes - always need uniforms (not instanced)
			for (let batch in Batcher.SkinnedBatches)
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

	private void ExecuteDepthPass(IRenderPassEncoder encoder, RenderWorld world, ViewContext view, int32 frameIndex, int32 bgIndex)
	{
		using (SProfiler.Begin("DepthPrepass.Execute"))
		{
			// Set viewport — render to per-view SceneDepth texture at (0,0), not swapchain offset
			encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
			encoder.SetScissor(0, 0, view.Width, view.Height);

			// Track object index for uniform buffer dynamic offsets
			var objectIndex = (int32)0;

			// Use instanced path if available and has instance groups
			if (InstancingActive && mDepthInstancedPipeline != null && Batcher.OpaqueInstanceGroups.Length > 0)
			{
				using (SProfiler.Begin("InstancedDraw"))
					ExecuteInstancedDepthPass(encoder, frameIndex, bgIndex);
				// Instanced path doesn't use uniform buffer for static meshes,
				// skinned uniforms start at index 0 (we skipped static mesh uploads)
				objectIndex = 0;
			}
			else
			{
				// Fall back to non-instanced path
				using (SProfiler.Begin("NonInstancedDraw"))
					ExecuteNonInstancedDepthPass(encoder, frameIndex, bgIndex, ref objectIndex);
			}

			// Render skinned meshes (always non-instanced)
			using (SProfiler.Begin("SkinnedMeshes"))
				RenderSkinnedMeshesDepth(encoder, world, frameIndex, bgIndex, ref objectIndex);
		}
	}

	private void ExecuteInstancedDepthPass(IRenderPassEncoder encoder, int32 frameIndex, int32 bgIndex)
	{
		// Set instanced depth pipeline
		encoder.SetPipeline(mDepthInstancedPipeline);

		// Get instance buffer for this frame
		let instanceBuffer = mInstanceBufferManager.GetBuffer(frameIndex);
		if (instanceBuffer == null)
			return;

		// Bind depth bind group for camera uniforms (dynamic offset 0 - object uniforms not used with instancing)
		let bindGroup = mDepthBindGroups[bgIndex];
		if (bindGroup != null)
		{
			uint32[1] dynamicOffsets = .(0);
			encoder.SetBindGroup(0, bindGroup, dynamicOffsets);
		}

		// Render opaque instance groups
		for (let group in Batcher.OpaqueInstanceGroups)
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

					if (mesh.SubMeshes != null)
					{
						// Resolve LOD submesh range
						uint32 subStart = 0;
						uint32 subCount = (uint32)mesh.SubMeshes.Count;
						if (mesh.LODLevels != null && group.LODLevel < mesh.LODCount)
						{
							subStart = mesh.LODLevels[group.LODLevel].SubMeshStart;
							subCount = mesh.LODLevels[group.LODLevel].SubMeshCount;
						}

						for (uint32 si = subStart; si < subStart + subCount && si < (uint32)mesh.SubMeshes.Count; si++)
						{
							let sub = mesh.SubMeshes[si];
							encoder.DrawIndexed(sub.IndexCount, (uint32)group.InstanceCount, sub.IndexStart, sub.BaseVertex, 0);
							Renderer.Stats.DrawCalls++;
						}
					}
				}
				else
				{
					encoder.Draw(mesh.VertexCount, (uint32)group.InstanceCount, 0, 0);
					Renderer.Stats.DrawCalls++;
				}

				Renderer.Stats.InstanceCount += group.InstanceCount;
			}
		}
	}

	private void ExecuteNonInstancedDepthPass(IRenderPassEncoder encoder, int32 frameIndex, int32 bgIndex, ref int32 objectIndex)
	{
		// Set depth pipeline
		if (mDepthPipeline != null)
			encoder.SetPipeline(mDepthPipeline);

		// Get draw commands from batcher (uniforms already uploaded in PrepareObjectUniforms)
		let commands = Batcher.DrawCommands;

		// Get current frame+view's bind group
		let bindGroup = mDepthBindGroups[bgIndex];

		// Render opaque batches with dynamic offsets
		for (let batch in Batcher.OpaqueBatches)
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

					if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

						// Resolve LOD submesh range
						uint32 subStart = 0;
						uint32 subCount = (uint32)mesh.SubMeshes.Count;
						if (mesh.LODLevels != null && cmd.LODLevel < mesh.LODCount)
						{
							subStart = mesh.LODLevels[cmd.LODLevel].SubMeshStart;
							subCount = mesh.LODLevels[cmd.LODLevel].SubMeshCount;
						}

						for (uint32 si = subStart; si < subStart + subCount && si < (uint32)mesh.SubMeshes.Count; si++)
						{
							let sub = mesh.SubMeshes[si];
							encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);
							Renderer.Stats.DrawCalls++;
						}
					}
					else if (mesh.IndexBuffer == null)
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
						Renderer.Stats.DrawCalls++;
					}

					objectIndex++;
				}
			}
		}
	}

	private void RenderSkinnedMeshesDepth(IRenderPassEncoder encoder, RenderWorld world, int32 frameIndex, int32 bgIndex, ref int32 objectIndex)
	{
		// Get skinning system to access skinned vertex buffers
		let skinningSystem = Renderer.SkinningSystem;
		if (skinningSystem == null)
			return;

		// Switch to non-instanced pipeline for skinned meshes
		// (instanced pipeline may still be bound from previous pass)
		if (mDepthPipeline != null)
			encoder.SetPipeline(mDepthPipeline);

		let skinnedCommands = Batcher.SkinnedCommands;

		// Get current frame+view's bind group
		let bindGroup = mDepthBindGroups[bgIndex];

		for (let batch in Batcher.SkinnedBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= MaxObjectsPerFrame)
					break;

				let cmd = skinnedCommands[batch.CommandStart + i];

				// Get the skinned vertex buffer from skinning system
				let skinnedVertexBuffer = skinningSystem.GetSkinnedVertexBuffer(world, cmd.MeshHandle);
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
					if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
						for (let sub in mesh.SubMeshes)
						{
							encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);
							Renderer.Stats.DrawCalls++;
						}
					}
					else if (mesh.IndexBuffer == null)
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
						Renderer.Stats.DrawCalls++;
					}
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
