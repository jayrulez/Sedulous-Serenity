namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Forward opaque rendering feature — PBR metallic/roughness with Cook-Torrance BRDF.
/// Phase 5 initial: single hardcoded directional light, no shadows, no IBL.
class ForwardOpaqueFeature : IRenderFeature
{
	private IDevice mDevice;
	private GPUResourceManager mResources;
	private RenderPipelineCache mPipelineCache;
	private RenderSystem mSystem;

	/// The HDR scene color texture created this frame (valid after OnAddPasses).
	public RGTexture SceneColorTexture;

	/// Thin G-buffer: RG=octahedral normal, B=roughness, A=metallic.
	public RGTexture GBufferTexture;

	public StringView Name => "ForwardOpaque";
	public bool SupportsProbeCapture => true;

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;
		mResources = initCtx.Resources;
		mPipelineCache = initCtx.Pipelines;
		mSystem = initCtx.System;

		// Register forward PBR shader (loaded from search paths)
		if (initCtx.Shaders.RegisterShader("forward_pbr") case .Err)
			return .Err;

		return .Ok;
	}

	public void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
	{
		let world = mSystem.ActiveWorld;
		if (world == null) return;

		let depthPrepass = mSystem.GetFeature<DepthPrepassFeature>();
		if (depthPrepass == null) return;
		let depthTex = depthPrepass.DepthTexture;
		if (!depthTex.IsValid) return;

		let resources = mResources;
		let device = mDevice;
		let system = mSystem;
		let pipelineCache = mPipelineCache;
		let renderW = viewCtx.RenderWidth;
		let renderH = viewCtx.RenderHeight;

		graph.AddPass("ForwardOpaque", .Graphics, scope [&] (builder) =>
		{
			// Create HDR scene color texture
			SceneColorTexture = builder.CreateTexture(
				RGTextureDesc.RenderTarget(.RGBA16Float, renderW, renderH, 1, "SceneColor"));

			// Create thin G-buffer (normals + roughness + metallic)
			GBufferTexture = builder.CreateTexture(
				RGTextureDesc.RenderTarget(.RGBA8Unorm, renderW, renderH, 1, "GBuffer"));

			builder.WriteRenderTarget(SceneColorTexture, 0, .Clear, .Store,
				ClearColor(0.05f, 0.05f, 0.08f, 1.0f));
			builder.WriteRenderTarget(GBufferTexture, 1, .Clear, .Store,
				ClearColor(0.0f, 0.0f, 0.0f, 0.0f));

			// Read depth from prepass (read-only depth test)
			builder.ReadDepthStencil(depthTex);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);

				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
				rp.SetScissor(0, 0, renderW, renderH);

				ExecuteForwardPass(rp, system, resources, device, pipelineCache);
				DrawSkinnedMeshes(rp, system, resources, device, pipelineCache);

				rp.End();
			});
		});
	}

	private void ExecuteForwardPass(IRenderPassEncoder rp, RenderSystem system,
		GPUResourceManager resources, IDevice device, RenderPipelineCache pipelineCache)
	{
		let gpuScene = system.GPUScene;
		let indirectDraws = system.IndirectDraws;
		let frameIndex = system.FrameIndex;
		let drawGroupRanges = gpuScene.DrawGroupRanges;

		if (drawGroupRanges.Count == 0) return;

		let gpuObjBG = system.GPUDrivenObjectBindGroup;
		let indirectBuffer = indirectDraws.GetIndirectBuffer(frameIndex);

		MaterialInstanceHandle prevMaterial = .Invalid;

		for (let range in drawGroupRanges)
		{
			if (range.CommandCount == 0) continue;

			// Only draw opaque materials in this pass
			let matInst = system.GetMaterialInstance(range.MaterialHandle);
			if (matInst == null) continue;
			if (matInst.Definition.BlendMode != .Opaque) continue;

			let mesh = resources.GetMesh(range.MeshHandle);
			if (mesh == null) continue;

			// Material change
			if (range.MaterialHandle != prevMaterial)
			{
				if (matInst != null)
				{
					if (matInst.IsDirty(frameIndex))
						matInst.RebuildBindGroup(device, frameIndex);

					var meshLayout = VertexLayoutHelper.GetStaticMeshLayout();
					var objIdxLayout = VertexLayoutHelper.GetObjectIndexLayout();
					VertexBufferLayout[2] layouts = .(meshLayout, objIdxLayout);

					let pipeResult = pipelineCache.GetOrCreate(
						matInst.Definition,
						Span<VertexBufferLayout>(&layouts[0], 2),
						system.SceneBindGroupLayout,
						.RGBA16Float,
						.Depth32Float,
						1,
						.GPUDriven,
						system.GPUDrivenObjectLayout,
						.RGBA8Unorm);  // G-buffer RT1

					if (pipeResult case .Ok(let pipeline))
						rp.SetPipeline(pipeline);

					if (system.SceneBindGroup != null)
						rp.SetBindGroup(0, system.SceneBindGroup);

					let matBindGroup = matInst.GetBindGroup(frameIndex);
					if (matBindGroup != null)
						rp.SetBindGroup(1, matBindGroup);

					if (gpuObjBG != null)
						rp.SetBindGroup(2, gpuObjBG);

					rp.SetVertexBuffer(1, system.IdentityInstanceBuffer, 0);
				}
				prevMaterial = range.MaterialHandle;
			}

			rp.SetVertexBuffer(0, mesh.VertexBuffer, 0);
			if (mesh.IndexBuffer != null)
				rp.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);

			// Multi-draw indirect: one command per object in this group.
			// Invisible objects have instanceCount=0 (GPU cull set it).
			let cmdOffset = (uint64)(range.CommandOffset * DrawIndexedIndirectCommand.Stride);
			rp.DrawIndexedIndirect(indirectBuffer, cmdOffset, range.CommandCount,
				(uint32)DrawIndexedIndirectCommand.Stride);
		}

	}

	private void DrawSkinnedMeshes(IRenderPassEncoder rp, RenderSystem system,
		GPUResourceManager resources, IDevice device, RenderPipelineCache pipelineCache)
	{
		let skinning = system.Skinning;
		if (skinning.OpaqueDraws.Count == 0) return;

		let world = system.ActiveWorld;
		let objectUniforms = system.ObjectUniforms;
		let frameIndex = system.FrameIndex;

		MaterialInstanceHandle prevMaterial = .Invalid;

		for (let draw in skinning.OpaqueDraws)
		{
			let proxy = world.SkinnedMeshes.Get(draw.ProxyHandle);
			if (proxy == null) continue;

			let mesh = resources.GetMesh(draw.MeshHandle);
			if (mesh == null) continue;
			if (draw.SubMeshIndex >= (uint32)mesh.SubMeshes.Count) continue;
			let subMesh = mesh.SubMeshes[draw.SubMeshIndex];

			// Material binding (same pattern as static meshes)
			if (draw.MaterialHandle != prevMaterial)
			{
				let matInst = system.GetMaterialInstance(draw.MaterialHandle);
				if (matInst != null)
				{
					if (matInst.IsDirty(frameIndex))
						matInst.RebuildBindGroup(device, frameIndex);

					var vertexLayout = VertexLayoutHelper.GetStaticMeshLayout();
					let pipeResult = pipelineCache.GetOrCreate(
						matInst.Definition,
						Span<VertexBufferLayout>(&vertexLayout, 1),
						system.SceneBindGroupLayout,
						.RGBA16Float,
						.Depth32Float,
						1,
						.None,
						system.ObjectBindGroupLayout,
						.RGBA8Unorm);

					if (pipeResult case .Ok(let pipeline))
						rp.SetPipeline(pipeline);

					if (system.SceneBindGroup != null)
						rp.SetBindGroup(0, system.SceneBindGroup);

					let matBindGroup = matInst.GetBindGroup(frameIndex);
					if (matBindGroup != null)
						rp.SetBindGroup(1, matBindGroup);
				}
				prevMaterial = draw.MaterialHandle;
			}

			// Use skinned output VB instead of mesh.VertexBuffer
			rp.SetVertexBuffer(0, draw.OutputVertexBuffer, 0);

			var objUniforms = ObjectUniforms();
			objUniforms.WorldMatrix = proxy.Transform;
			objUniforms.PrevWorldMatrix = proxy.PrevTransform;
			Matrix.Invert(proxy.Transform, out objUniforms.NormalMatrix);
			objUniforms.NormalMatrix = Matrix.Transpose(objUniforms.NormalMatrix);

			let dynamicOffset = objectUniforms.AllocateObject(objUniforms);
			if (dynamicOffset == uint32.MaxValue) return;

			uint32[1] offsets = .(dynamicOffset);
			rp.SetBindGroup(2, system.ObjectBindGroup, Span<uint32>(&offsets[0], 1));

			if (mesh.IndexBuffer != null && subMesh.IndexCount > 0)
			{
				rp.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);
				rp.DrawIndexed(subMesh.IndexCount, 1, subMesh.IndexStart, subMesh.BaseVertex, 0);
			}
			else
			{
				rp.Draw(subMesh.IndexCount > 0 ? subMesh.IndexCount : mesh.VertexCount, 1, 0, 0);
			}
		}
	}

	public void OnPostRender() { }

	public void OnShutdown(IDevice device)
	{
		// Pipelines owned by cache, materials owned by caller
	}
}
