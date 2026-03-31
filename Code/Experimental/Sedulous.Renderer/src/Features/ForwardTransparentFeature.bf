namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Forward transparent rendering feature — PBR with alpha blending.
/// Renders transparent objects back-to-front on top of the opaque scene color.
/// Uses the same forward_pbr shader as opaque, with blend state from each material.
class ForwardTransparentFeature : IRenderFeature
{
	private IDevice mDevice;
	private GPUResourceManager mResources;
	private RenderPipelineCache mPipelineCache;
	private RenderSystem mSystem;

	public StringView Name => "ForwardTransparent";

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;
		mResources = initCtx.Resources;
		mPipelineCache = initCtx.Pipelines;
		mSystem = initCtx.System;

		// forward_pbr shader is already registered by ForwardOpaqueFeature
		return .Ok;
	}

	public void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
	{
		let world = mSystem.ActiveWorld;
		if (world == null) return;

		// Check if any transparent draw groups exist (GPU-driven path)
		bool hasTransparent = mSystem.Skinning.TransparentDraws.Count > 0;
		if (!hasTransparent)
		{
			for (let range in mSystem.GPUScene.DrawGroupRanges)
			{
				let mat = mSystem.GetMaterialInstance(range.MaterialHandle);
				if (mat != null && mat.Definition.BlendMode != .Opaque)
				{
					hasTransparent = true;
					break;
				}
			}
		}
		if (!hasTransparent) return;

		// Need the opaque feature's scene color and the depth prepass texture
		let opaqueFeature = mSystem.GetFeature<ForwardOpaqueFeature>();
		if (opaqueFeature == null) return;
		let sceneColor = opaqueFeature.SceneColorTexture;
		if (!sceneColor.IsValid) return;

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

		let gBuffer = opaqueFeature.GBufferTexture;

		graph.AddPass("ForwardTransparent", .Graphics, scope [&] (builder) =>
		{
			// Write on top of opaque scene color (load existing, don't clear)
			builder.WriteRenderTarget(sceneColor, 0, .Load, .Store);
			// Write to G-buffer (load existing from opaque pass)
			if (gBuffer.IsValid)
				builder.WriteRenderTarget(gBuffer, 1, .Load, .Store);

			// Read depth from prepass (read-only depth test, no write)
			builder.ReadDepthStencil(depthTex);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);

				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
				rp.SetScissor(0, 0, renderW, renderH);

				ExecuteTransparentPass(rp, system, resources, device, pipelineCache);
				DrawSkinnedTransparent(rp, system, resources, device, pipelineCache);

				rp.End();
			});
		});
	}

	private void ExecuteTransparentPass(IRenderPassEncoder rp, RenderSystem system,
		GPUResourceManager resources, IDevice device, RenderPipelineCache pipelineCache)
	{
		// TODO: Transparent objects need back-to-front sorting which doesn't fit the
		// GPU-driven indirect draw model well. For now, use the same indirect approach
		// as opaque (GPU culling handles visibility, but sort order may be incorrect).
		// Proper transparent GPU-driven requires OIT or per-pixel sorting.
		let gpuScene = system.GPUScene;
		let indirectDraws = system.IndirectDraws;
		let frameIndex = system.FrameIndex;
		let drawGroupRanges = gpuScene.DrawGroupRanges;

		// Filter to transparent draw groups only
		let gpuObjBG = system.GPUDrivenObjectBindGroup;
		let indirectBuffer = indirectDraws.GetIndirectBuffer(frameIndex);

		MaterialInstanceHandle prevMaterial = .Invalid;

		for (let range in drawGroupRanges)
		{
			if (range.CommandCount == 0) continue;

			// Only draw transparent materials in this pass
			let matInst = system.GetMaterialInstance(range.MaterialHandle);
			if (matInst == null) continue;
			if (matInst.Definition.BlendMode == .Opaque) continue;

			let mesh = resources.GetMesh(range.MeshHandle);
			if (mesh == null) continue;

			if (range.MaterialHandle != prevMaterial)
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
					.RGBA8Unorm);

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

				prevMaterial = range.MaterialHandle;
			}

			rp.SetVertexBuffer(0, mesh.VertexBuffer, 0);
			if (mesh.IndexBuffer != null)
				rp.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);

			let cmdOffset = (uint64)(range.CommandOffset * DrawIndexedIndirectCommand.Stride);
			rp.DrawIndexedIndirect(indirectBuffer, cmdOffset, range.CommandCount,
				(uint32)DrawIndexedIndirectCommand.Stride);
		}

	}

	private void DrawSkinnedTransparent(IRenderPassEncoder rp, RenderSystem system,
		GPUResourceManager resources, IDevice device, RenderPipelineCache pipelineCache)
	{
		let skinning = system.Skinning;
		if (skinning.TransparentDraws.Count == 0) return;

		let world = system.ActiveWorld;
		let objectUniforms = system.ObjectUniforms;
		let frameIndex = system.FrameIndex;

		MaterialInstanceHandle prevMaterial = .Invalid;

		for (let draw in skinning.TransparentDraws)
		{
			let proxy = world.SkinnedMeshes.Get(draw.ProxyHandle);
			if (proxy == null) continue;

			let mesh = resources.GetMesh(draw.MeshHandle);
			if (mesh == null) continue;
			if (draw.SubMeshIndex >= (uint32)mesh.SubMeshes.Count) continue;
			let subMesh = mesh.SubMeshes[draw.SubMeshIndex];

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
	}
}
