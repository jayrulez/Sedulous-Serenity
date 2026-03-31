namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Profiler;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.RenderGraph;

/// Depth prepass render feature.
/// Renders depth-only for all opaque geometry to enable:
/// - Early-Z rejection in forward pass
/// - Hi-Z pyramid generation for occlusion culling
public class DepthPrepassFeature : RenderFeatureBase
{
	// Pipelines (owned by this feature)
	private IRenderPipeline mDepthPipeline;
	private IRenderPipeline mDepthSkinnedPipeline;
	private IRenderPipeline mDepthInstancedPipeline;
	private IPipelineLayout mPipelineLayout;

	// Instance buffer manager for GPU instancing
	private InstanceBufferManager mInstanceBufferManager ~ { if (_ != null) { _.Shutdown(); delete _; } };
	private bool mInstancingEnabled = false;
	private bool mWorldInstancingEnabled = true;

	// Constants — reference shared values
	private static int MaxObjectsPerFrame => RenderConfig.MaxOpaqueObjectsPerFrame;
	private static uint64 AlignedObjectUniformSize => SharedBindGroupLayouts.AlignedObjectUniformSize;

	// Visibility and batching — owned by RenderSystem, shared across features

	// Hi-Z resources
	private HiZOcclusionCuller mHiZCuller ~ delete _;

	// Render graph handles (set per-frame in AddPasses)
	private RGHandle mDepthHandle;

	// Configuration
	private bool mEnableHiZ = true;
	private bool mEnableInstancing = true;

	private int32 mCurrentFrameIndex;

	/// Feature name.
	public override StringView Name => "DepthPrepass";

	/// The depth texture handle created by this feature (other features read it).
	public RGHandle DepthHandle => mDepthHandle;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => mCurrentFrameIndex;

	/// Gets bind group array index for current frame and view.
	private int32 GetBindGroupIndex(int32 frameIndex, int32 viewIndex = 0) => frameIndex * RenderConfig.MaxViews + viewIndex;

	/// Gets the Hi-Z culler.
	public HiZOcclusionCuller HiZCuller => mHiZCuller;

	/// Gets the visibility resolver (shared from RenderSystem).
	public VisibilityResolver Visibility => Renderer.Visibility;

	/// Gets or sets whether Hi-Z occlusion culling is enabled.
	public bool EnableHiZ { get => mEnableHiZ; set => mEnableHiZ = value; }

	/// Gets or sets whether GPU instancing is enabled.
	public bool EnableInstancing { get => mEnableInstancing; set => mEnableInstancing = value; }

	/// Gets whether instancing is currently active.
	public bool InstancingActive => mEnableInstancing && mInstancingEnabled && mWorldInstancingEnabled;

	/// Gets the instance buffer for a frame (for use by other features).
	public IBuffer GetInstanceBuffer(int32 frameIndex) => mInstanceBufferManager?.GetBuffer(frameIndex);

	/// Gets the draw batcher (shared from RenderSystem).
	public DrawBatcher Batcher => Renderer.Batcher;

	/// Depends on GPU skinning (skinned vertex buffers must be ready).
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("GPUSkinning");
	}

	protected override Result<void> OnInitialize()
	{
		// Initialize Hi-Z culler
		mHiZCuller = new HiZOcclusionCuller();
		if (Renderer.ShaderSystem != null)
		{
			if (mHiZCuller.Initialize(Renderer.Device, 1920, 1080, Renderer.ShaderSystem) case .Err)
				return .Err;
		}

		// Layouts and object buffers are shared via Renderer.SharedLayouts

		// Create depth pipelines
		if (CreateDepthPipelines() case .Err)
			return .Err;

		// Initialize instance buffer manager for GPU instancing
		if (mEnableInstancing)
		{
			mInstanceBufferManager = new InstanceBufferManager();
			if (mInstanceBufferManager.Initialize(Renderer.Device) case .Ok)
			{
				if (CreateInstancedDepthPipeline() case .Ok)
					mInstancingEnabled = true;
			}
		}

		return .Ok;
	}

	private Result<void> CreateDepthPipelines()
	{
		if (Renderer.ShaderSystem == null)
			return .Ok; // Shaders not available, pipelines created lazily

		let shaderPairResult = Renderer.ShaderSystem.GetShaderPair("depth");
		if (shaderPairResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderPairResult.Value;

		// Create pipeline layout from shared depth pass layout
		IBindGroupLayout[1] layouts = .(Renderer.SharedLayouts.DepthPassLayout);
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
				Targets = default
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
		if (Renderer.ShaderSystem == null || mPipelineLayout == null)
			return .Err;

		let shaderPairResult = Renderer.ShaderSystem.GetShaderPair("depth", .Instanced);
		if (shaderPairResult case .Err)
			return .Err;
		let (vertShader, fragShader) = shaderPairResult.Value;

		VertexBufferLayout[2] vertexBuffers = default;
		VertexLayoutHelper.CreateInstancedMeshLayout(.Mesh, out vertexBuffers);

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
				Targets = default
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

		// Bind groups and object buffers owned by SharedLayouts — not destroyed here

		if (mHiZCuller != null)
			mHiZCuller.Dispose();

		device.DestroyRenderPipeline(ref mDepthPipeline);
		device.DestroyRenderPipeline(ref mDepthSkinnedPipeline);
		device.DestroyRenderPipeline(ref mDepthInstancedPipeline);
		device.DestroyPipelineLayout(ref mPipelineLayout);
	}

	// Multi-view visibility is now handled by RenderSystem.PrepareView()

	public override void PrepareFrame(int32 frameIndex)
	{
		mCurrentFrameIndex = frameIndex;
	}

	public override void AddPasses(Sedulous.RenderGraph.RenderGraph graph, RenderFrameContext frameCtx, ViewContext viewCtx)
	{
		using (SProfiler.Begin("DepthPrepass.AddPasses"))
		{
			let world = World;

			mDepthHandle = graph.CreateTransient("SceneDepth", RGTextureDesc(Renderer.DepthFormat, .FullSize)
			{
				Usage = .DepthStencil | .Sampled
			});

			let frameIndex = FrameIndex;

			// Visibility and batching are done by RenderSystem.PrepareView().
			// We just upload object uniforms and instance data here.
			if (world != null)
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

			let depthHandle = mDepthHandle;
			let feature = this;
			let viewWidth = viewCtx.RenderWidth;
			let viewHeight = viewCtx.RenderHeight;

			graph.AddRenderPass("DepthPrepass", scope (builder) =>
			{
				builder.SetDepthTarget(depthHandle, .Clear, .Store, 1.0f);
				builder.NeverCull();
				builder.SetExecute(new [=](encoder) => {
					feature.ExecuteDepthPass(encoder, viewWidth, viewHeight, frameIndex);
				});
			});

			// Hi-Z generation pass
			if (mEnableHiZ && mHiZCuller != null && mHiZCuller.IsInitialized && mHiZCuller.GPUBuildAvailable)
			{
				let graphRef = graph;
				let depthRef = depthHandle;

				graph.AddComputePass("HiZGenerate", scope (builder) =>
				{
					builder.ReadTexture(depthRef);
					builder.SetComputeExecute(new [=](encoder) => {
						let depthView = graphRef.GetTextureView(depthRef);
						feature.ExecuteHiZGeneration(encoder, depthView);
					});
				});
			}
		}
	}

	private void PrepareObjectUniforms(int32 frameIndex)
	{
		let skinnedCommands = Batcher.SkinnedCommands;
		let buffer = Renderer.SharedLayouts.GetObjectUniformBuffer(frameIndex);
		if (buffer == null) return;

		if (let bufferPtr = buffer.Map())
		{
			int32 objectIndex = 0;

			if (!InstancingActive)
			{
				let commands = Batcher.DrawCommands;
				for (let batch in Batcher.OpaqueBatches)
				{
					if (batch.CommandCount == 0) continue;
					for (int32 i = 0; i < batch.CommandCount; i++)
					{
						if (objectIndex >= MaxObjectsPerFrame) break;
						let cmd = commands[batch.CommandStart + i];

						ObjectUniforms uniforms = .()
						{
							WorldMatrix = cmd.WorldMatrix,
							PrevWorldMatrix = cmd.PrevWorldMatrix,
							ObjectID = (uint32)objectIndex,
							MaterialID = 0,
							_Padding = default
						};

						let offset = (uint64)(objectIndex * (int32)AlignedObjectUniformSize);
						Internal.MemCpy((uint8*)bufferPtr + offset, &uniforms, SharedBindGroupLayouts.ObjectUniformSize);
						objectIndex++;
					}
				}
			}

			for (let batch in Batcher.SkinnedBatches)
			{
				if (batch.CommandCount == 0) continue;
				for (int32 i = 0; i < batch.CommandCount; i++)
				{
					if (objectIndex >= MaxObjectsPerFrame) break;
					let cmd = skinnedCommands[batch.CommandStart + i];

					ObjectUniforms uniforms = .()
					{
						WorldMatrix = cmd.WorldMatrix,
						PrevWorldMatrix = cmd.PrevWorldMatrix,
						ObjectID = (uint32)objectIndex,
						MaterialID = 0,
						_Padding = default
					};

					let offset = (uint64)(objectIndex * (int32)AlignedObjectUniformSize);
					Internal.MemCpy((uint8*)bufferPtr + offset, &uniforms, SharedBindGroupLayouts.ObjectUniformSize);
					objectIndex++;
				}
			}

			buffer.Unmap();
		}
	}

	private void ExecuteDepthPass(IRenderPassEncoder encoder, uint32 viewWidth, uint32 viewHeight, int32 frameIndex)
	{
		using (SProfiler.Begin("DepthPrepass.Execute"))
		{
			let world = World;
			encoder.SetViewport(0, 0, (float)viewWidth, (float)viewHeight, 0.0f, 1.0f);
			encoder.SetScissor(0, 0, viewWidth, viewHeight);

			var objectIndex = (int32)0;

			if (InstancingActive && mDepthInstancedPipeline != null && Batcher.OpaqueInstanceGroups.Length > 0)
			{
				using (SProfiler.Begin("InstancedDraw"))
					ExecuteInstancedDepthPass(encoder, frameIndex);
				objectIndex = 0;
			}
			else
			{
				using (SProfiler.Begin("NonInstancedDraw"))
					ExecuteNonInstancedDepthPass(encoder, world, frameIndex, ref objectIndex);
			}

			using (SProfiler.Begin("SkinnedMeshes"))
				RenderSkinnedMeshesDepth(encoder, world, frameIndex, ref objectIndex);
		}
	}

	private void ExecuteInstancedDepthPass(IRenderPassEncoder encoder, int32 frameIndex)
	{
		encoder.SetPipeline(mDepthInstancedPipeline);

		let instanceBuffer = mInstanceBufferManager?.GetBuffer(frameIndex);
		if (instanceBuffer == null) return;

		let bindGroup = Renderer.SharedLayouts.GetDepthPassBindGroup(frameIndex);
		if (bindGroup != null)
		{
			uint32[1] dynamicOffsets = .(0);
			encoder.SetBindGroup(0, bindGroup, dynamicOffsets);
		}

		let resourceManager = Renderer.ResourceManager;
		for (let group in Batcher.OpaqueInstanceGroups)
		{
			if (group.InstanceCount == 0) continue;

			if (let mesh = resourceManager.GetMesh(group.GPUMesh))
			{
				encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
				encoder.SetVertexBuffer(1, instanceBuffer, (uint64)(group.InstanceStart * (int32)VertexLayoutHelper.InstanceDataStride));

				if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
				{
					encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);

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
					}
				}
				else
				{
					encoder.Draw(mesh.VertexCount, (uint32)group.InstanceCount, 0, 0);
				}
			}
		}
	}

	private void ExecuteNonInstancedDepthPass(IRenderPassEncoder encoder, RenderWorld world, int32 frameIndex, ref int32 objectIndex)
	{
		if (mDepthPipeline != null)
			encoder.SetPipeline(mDepthPipeline);

		let commands = Batcher.DrawCommands;
		let bindGroup = Renderer.SharedLayouts.GetDepthPassBindGroup(frameIndex);
		let resourceManager = Renderer.ResourceManager;

		for (let batch in Batcher.OpaqueBatches)
		{
			if (batch.CommandCount == 0) continue;

			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= MaxObjectsPerFrame) break;
				let cmd = commands[batch.CommandStart + i];

				if (let mesh = resourceManager.GetMesh(cmd.GPUMesh))
				{
					if (bindGroup != null)
					{
						uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
						encoder.SetBindGroup(0, bindGroup, dynamicOffsets);
					}

					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);

					if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);

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
						}
					}
					else
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
					}

					objectIndex++;
				}
			}
		}
	}

	private void RenderSkinnedMeshesDepth(IRenderPassEncoder encoder, RenderWorld world, int32 frameIndex, ref int32 objectIndex)
	{
		let skinningSystem = Renderer.SkinningSystem;
		if (skinningSystem == null) return;

		if (mDepthPipeline != null)
			encoder.SetPipeline(mDepthPipeline);

		let skinnedCommands = Batcher.SkinnedCommands;
		let bindGroup = Renderer.SharedLayouts.GetDepthPassBindGroup(frameIndex);
		let resourceManager = Renderer.ResourceManager;

		for (let batch in Batcher.SkinnedBatches)
		{
			if (batch.CommandCount == 0) continue;

			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= MaxObjectsPerFrame) break;
				let cmd = skinnedCommands[batch.CommandStart + i];

				let skinnedVertexBuffer = skinningSystem.GetSkinnedVertexBuffer(world, cmd.MeshHandle);
				if (skinnedVertexBuffer == null) continue;

				if (bindGroup != null)
				{
					uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
					encoder.SetBindGroup(0, bindGroup, dynamicOffsets);
				}

				encoder.SetVertexBuffer(0, skinnedVertexBuffer, 0);

				if (let mesh = resourceManager.GetMesh(cmd.GPUMesh))
				{
					if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);
						for (let sub in mesh.SubMeshes)
						{
							encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);
						}
					}
					else
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
					}
				}

				objectIndex++;
			}
		}
	}

	private void ExecuteHiZGeneration(IComputePassEncoder encoder, ITextureView depthView)
	{
		if (depthView == null) return;
		mHiZCuller.BuildPyramid(encoder, depthView);
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
}
