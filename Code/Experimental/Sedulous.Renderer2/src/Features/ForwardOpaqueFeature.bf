namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Profiler;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.RenderGraph;

/// Forward opaque PBR render feature.
/// Renders all opaque geometry with physically-based shading, clustered lighting,
/// and IBL. Uses shared scene bind group layout from RenderSystem.
/// Pipelines are created lazily per material variant via RenderPipelineCache.
public class ForwardOpaqueFeature : RenderFeatureBase
{
	// Render graph handles
	private RGHandle mColorHandle;
	private RGHandle mGBufferHandle;

	// Constants
	private static int MaxObjectsPerFrame => RenderConfig.MaxOpaqueObjectsPerFrame;
	private static uint64 AlignedObjectUniformSize => SharedBindGroupLayouts.AlignedObjectUniformSize;

	public override StringView Name => "ForwardOpaque";

	/// The HDR color texture handle (other features read it for post-processing)
	public RGHandle ColorHandle => mColorHandle;

	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("DepthPrepass");
	}

	protected override Result<void> OnInitialize()
	{
		// No eager pipeline creation — pipelines created lazily per material via PipelineCache
		return .Ok;
	}

	protected override void OnShutdown()
	{
		// Pipelines owned by PipelineCache, not this feature
	}

	public override void AddPasses(Sedulous.RenderGraph.RenderGraph graph, RenderFrameContext frameCtx, ViewContext viewCtx)
	{
		using (SProfiler.Begin("ForwardOpaque.AddPasses"))
		{
			let depthFeature = Renderer.GetFeature<DepthPrepassFeature>();
			if (depthFeature == null) return;

			let depthHandle = depthFeature.DepthHandle;

			// Create HDR color target
			mColorHandle = graph.CreateTransient("SceneColor", RGTextureDesc(.RGBA16Float, .FullSize)
			{
				Usage = .RenderTarget | .Sampled | .CopySrc
			});

			// Create thin GBuffer (normals + roughness + metallic) — shader writes to Location 1
			mGBufferHandle = graph.CreateTransient("GBuffer", RGTextureDesc(.RGBA8Unorm, .FullSize)
			{
				Usage = .RenderTarget | .Sampled
			});

			let colorHandle = mColorHandle;
			let gbufferHandle = mGBufferHandle;
			let feature = this;
			let frameIndex = Renderer.FrameIndex;
			let viewWidth = viewCtx.RenderWidth;
			let viewHeight = viewCtx.RenderHeight;

			graph.AddRenderPass("ForwardOpaque", scope (builder) =>
			{
				builder.SetColorTarget(0, colorHandle, .Clear, .Store, ClearColor(0.5f, 0, 0, 1)); // DEBUG: dark red to see if draws produce anything
				builder.SetColorTarget(1, gbufferHandle, .Clear, .Store, ClearColor(0, 0, 0, 0));
				builder.SetDepthTarget(depthHandle, .Clear, .Store); // DEBUG: clear depth to 1.0 to rule out depth test
				builder.NeverCull();
				builder.SetExecute(new [=](encoder) => {
					feature.ExecuteForwardPass(encoder, viewWidth, viewHeight, frameIndex);
				});
			});
		}
	}

	/// Gets the appropriate pipeline for a material, using the shared scene layout.
	/// Follows Serenity's pattern: RenderPipelineCache.GetPipelineForMaterial()
	private IRenderPipeline GetPipelineForMaterial(MaterialInstance material)
	{
		let pipelineCache = Renderer.PipelineCache;
		let materialSystem = Renderer.MaterialSystem;
		let sceneLayout = Renderer.SharedLayouts.SceneLayout;
		if (pipelineCache == null || sceneLayout == null || materialSystem == null)
			return null;

		let baseMaterial = material?.Material;
		if (baseMaterial == null)
			return null;

		IBindGroupLayout materialLayout = null;
		if (materialSystem.GetOrCreateLayout(baseMaterial) case .Ok(let layout))
			materialLayout = layout;
		else
			return null;

		// Non-instanced vertex layout
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		if (pipelineCache.GetPipelineForMaterial(
			material,
			vertexBuffers,
			sceneLayout,
			materialLayout,
			.RGBA16Float,
			Renderer.DepthFormat,
			1,
			.None,
			.ReadOnly,
			.LessEqual,
			null, null,
			.RGBA8Unorm) case .Ok(let pipeline))  // RGBA8Unorm = GBuffer RT1
		{
			return pipeline;
		}

		return null;
	}

	private void ExecuteForwardPass(IRenderPassEncoder encoder, uint32 viewWidth, uint32 viewHeight, int32 frameIndex)
	{
		using (SProfiler.Begin("ForwardOpaque.Execute"))
		{
			let batcher = Renderer.Batcher;
			let resourceManager = Renderer.ResourceManager;
			let materialSystem = Renderer.MaterialSystem;

			encoder.SetViewport(0, 0, (float)viewWidth, (float)viewHeight, 0.0f, 1.0f);
			encoder.SetScissor(0, 0, viewWidth, viewHeight);

			// Bind shared scene bind group (Set 0)
			let sceneBindGroup = Renderer.SharedLayouts.GetSceneBindGroup(frameIndex);

			// Draw opaque batches
			let commands = batcher.DrawCommands;
			var objectIndex = (int32)0;
			MaterialInstance currentMaterial = null;

			for (let batch in batcher.OpaqueBatches)
			{
				if (batch.CommandCount == 0) continue;

				for (int32 i = 0; i < batch.CommandCount; i++)
				{
					if (objectIndex >= MaxObjectsPerFrame) break;
					let cmd = commands[batch.CommandStart + i];

					if (let mesh = resourceManager.GetMesh(cmd.GPUMesh))
					{
						// Get material for this mesh
						let world = World;
						MaterialInstance mat = materialSystem?.DefaultMaterialInstance;
						if (world != null && cmd.MeshHandle.IsValid)
						{
							if (let proxy = world.GetStaticMesh(cmd.MeshHandle))
							{
								if (proxy.MaterialCount > 0 && proxy.Materials[0] != null)
									mat = proxy.Materials[0];
							}
						}

						// Switch pipeline on material change
						if (mat != currentMaterial)
						{
							let pipeline = GetPipelineForMaterial(mat);
							if (pipeline != null)
								encoder.SetPipeline(pipeline);

							// Bind scene bind group (Set 0) with dynamic offset
							if (sceneBindGroup != null)
							{
								uint32[1] dynamicOffsets = .(0);
								encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
							}

							// Bind material bind group (Set 1)
							if (mat != null && materialSystem != null)
							{
								if (materialSystem.PrepareInstance(mat) case .Ok(let matBindGroup))
									encoder.SetBindGroup(1, matBindGroup);
							}

							currentMaterial = mat;
						}

						// Update dynamic offset for this object's transforms
						if (sceneBindGroup != null)
						{
							uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
							encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
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
								Renderer.Stats.DrawCalls++;
							}
						}
						else
						{
							encoder.Draw(mesh.VertexCount, 1, 0, 0);
							Renderer.Stats.DrawCalls++;
						}

						objectIndex++;
					}
				}
			}

			// Skinned meshes
			RenderSkinnedMeshes(encoder, frameIndex, ref objectIndex, ref currentMaterial);
		}
	}

	private void RenderSkinnedMeshes(IRenderPassEncoder encoder, int32 frameIndex, ref int32 objectIndex, ref MaterialInstance currentMaterial)
	{
		let skinningSystem = Renderer.SkinningSystem;
		let world = World;
		if (skinningSystem == null || world == null) return;

		let batcher = Renderer.Batcher;
		let resourceManager = Renderer.ResourceManager;
		let materialSystem = Renderer.MaterialSystem;
		let sceneBindGroup = Renderer.SharedLayouts.GetSceneBindGroup(frameIndex);
		let skinnedCommands = batcher.SkinnedCommands;

		for (let batch in batcher.SkinnedBatches)
		{
			if (batch.CommandCount == 0) continue;

			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= MaxObjectsPerFrame) break;
				let cmd = skinnedCommands[batch.CommandStart + i];

				let skinnedVertexBuffer = skinningSystem.GetSkinnedVertexBuffer(world, cmd.MeshHandle);
				if (skinnedVertexBuffer == null) continue;

				// Get material
				MaterialInstance mat = materialSystem?.DefaultMaterialInstance;
				if (cmd.MeshHandle.IsValid)
				{
					if (let proxy = world.GetSkinnedMesh(cmd.MeshHandle))
					{
						if (proxy.MaterialCount > 0 && proxy.Materials[0] != null)
							mat = proxy.Materials[0];
					}
				}

				if (mat != currentMaterial)
				{
					let pipeline = GetPipelineForMaterial(mat);
					if (pipeline != null)
						encoder.SetPipeline(pipeline);

					if (sceneBindGroup != null)
					{
						uint32[1] dynamicOffsets = .(0);
						encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
					}

					if (mat != null && materialSystem != null)
					{
						let matBindGroup = mat.BindGroup;
						if (matBindGroup != null)
							encoder.SetBindGroup(1, matBindGroup);
					}

					currentMaterial = mat;
				}

				if (sceneBindGroup != null)
				{
					uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
					encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
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
							Renderer.Stats.DrawCalls++;
						}
					}
					else
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
						Renderer.Stats.DrawCalls++;
					}
				}

				objectIndex++;
			}
		}
	}
}
