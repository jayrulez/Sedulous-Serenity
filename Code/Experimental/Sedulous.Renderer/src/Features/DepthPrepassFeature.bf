namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Depth prepass feature — populates the depth buffer before the forward pass,
/// eliminating overdraw in the expensive PBR lighting calculations.
class DepthPrepassFeature : IRenderFeature
{
	private IDevice mDevice;
	private GPUResourceManager mResources;
	private RenderPipelineCache mPipelineCache;
	private RenderSystem mSystem;

	private MaterialDefinition mDepthMaterialDef;
	private IRenderPipeline mDepthPipeline;
	private IRenderPipeline mGPUDrivenDepthPipeline;

	/// The depth texture created this frame (valid after OnAddPasses).
	public RGTexture DepthTexture;


	public StringView Name => "DepthPrepass";
	public bool SupportsProbeCapture => true;

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;
		mResources = initCtx.Resources;
		mPipelineCache = initCtx.Pipelines;
		mSystem = initCtx.System;

		// Register depth prepass shader (loaded from search paths)
		if (initCtx.Shaders.RegisterShader("depth_prepass") case .Err)
			return .Err;

		// Create depth-only material definition (no properties, no textures)
		mDepthMaterialDef = new MaterialDefinition();
		mDepthMaterialDef.Name = new String("DepthOnly");
		mDepthMaterialDef.ShaderName = new String("depth_prepass");
		mDepthMaterialDef.BlendMode = .Opaque;
		mDepthMaterialDef.CullMode = .Back;
		mDepthMaterialDef.DepthMode = .ReadWrite;

		// Empty material layout (depth shader doesn't use material set)
		if (mDepthMaterialDef.BuildLayout(mDevice) case .Err)
			return .Err;

		return .Ok;
	}

	public void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
	{
		let world = mSystem.ActiveWorld;
		if (world == null) return;

		let resources = mResources;
		let device = mDevice;
		let system = mSystem;
		let renderW = viewCtx.RenderWidth;
		let renderH = viewCtx.RenderHeight;

		graph.AddPass("DepthPrepass", .Graphics, scope [&] (builder) =>
		{
			// Create transient depth texture
			DepthTexture = builder.CreateTexture(
				RGTextureDesc.DepthBuffer(.Depth32Float, renderW, renderH, 1, "SceneDepth"));

			builder.WriteDepthStencil(DepthTexture, .Clear, .Store, 1.0f);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);

				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
				rp.SetScissor(0, 0, renderW, renderH);

				ExecuteDepthPass(rp, system, resources, device);
				DrawSkinnedDepth(rp, system, resources);

				rp.End();
			});
		});

		// Hi-Z pyramid generation — mip 0 reads depth as SampledTexture,
		// mip 1+ reads/writes Hi-Z mips as StorageTexture (GENERAL layout).
		mSystem.HiZ.AddGraphPass(graph, DepthTexture, renderW, renderH);
	}

	private void ExecuteDepthPass(IRenderPassEncoder rp, RenderSystem system, GPUResourceManager resources, IDevice device)
	{
		let gpuScene = system.GPUScene;
		let indirectDraws = system.IndirectDraws;
		let sceneBindGroup = system.SceneBindGroup;
		let drawGroupRanges = gpuScene.DrawGroupRanges;

		// Ensure pipelines are created
		if (mGPUDrivenDepthPipeline == null)
		{
			var meshLayout = VertexLayoutHelper.GetStaticMeshLayout();
			var objIdxLayout = VertexLayoutHelper.GetObjectIndexLayout();
			VertexBufferLayout[2] layouts = .(meshLayout, objIdxLayout);

			let pipelineResult = mPipelineCache.GetOrCreate(
				mDepthMaterialDef,
				Span<VertexBufferLayout>(&layouts[0], 2),
				system.SceneBindGroupLayout,
				.Undefined,
				.Depth32Float,
				1,
				.DepthOnly | .GPUDriven,
				system.GPUDrivenObjectLayout);

			if (pipelineResult case .Ok(let p))
				mGPUDrivenDepthPipeline = p;
		}

		if (mDepthPipeline == null)
		{
			var vertexLayout = VertexLayoutHelper.GetStaticMeshLayout();
			let pipelineResult = mPipelineCache.GetOrCreate(
				mDepthMaterialDef,
				Span<VertexBufferLayout>(&vertexLayout, 1),
				system.SceneBindGroupLayout,
				.Undefined,
				.Depth32Float,
				1,
				.DepthOnly,
				system.ObjectBindGroupLayout);

			if (pipelineResult case .Ok(let p))
				mDepthPipeline = p;
		}

		if (mGPUDrivenDepthPipeline == null || drawGroupRanges.Count == 0) return;

		let indirectBuffer = indirectDraws.GetIndirectBuffer(system.FrameIndex);

		rp.SetPipeline(mGPUDrivenDepthPipeline);
		if (sceneBindGroup != null)
			rp.SetBindGroup(0, sceneBindGroup);

		let gpuObjBG = system.GPUDrivenObjectBindGroup;
		if (gpuObjBG != null)
			rp.SetBindGroup(1, gpuObjBG);

		rp.SetVertexBuffer(1, system.IdentityInstanceBuffer, 0);

		// One multi-draw indirect per draw group — skip transparent materials
		for (let range in drawGroupRanges)
		{
			if (range.CommandCount == 0) continue;

			// Don't write depth for transparent objects
			let matInst = system.GetMaterialInstance(range.MaterialHandle);
			if (matInst != null && matInst.Definition.BlendMode != .Opaque) continue;

			let mesh = resources.GetMesh(range.MeshHandle);
			if (mesh == null) continue;

			rp.SetVertexBuffer(0, mesh.VertexBuffer, 0);
			if (mesh.IndexBuffer != null)
				rp.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);

			let cmdOffset = (uint64)(range.CommandOffset * DrawIndexedIndirectCommand.Stride);
			rp.DrawIndexedIndirect(indirectBuffer, cmdOffset, range.CommandCount,
				(uint32)DrawIndexedIndirectCommand.Stride);
		}
	}

	private void DrawSkinnedDepth(IRenderPassEncoder rp, RenderSystem system, GPUResourceManager resources)
	{
		let skinning = system.Skinning;
		if (skinning.OpaqueDraws.Count == 0) return;
		if (mDepthPipeline == null) return;

		let world = system.ActiveWorld;
		let objectUniforms = system.ObjectUniforms;
		let objectBindGroup = system.ObjectBindGroup;

		// Switch to CPU-path pipeline (different layout than GPU-driven)
		rp.SetPipeline(mDepthPipeline);
		if (system.SceneBindGroup != null)
			rp.SetBindGroup(0, system.SceneBindGroup);

		for (let draw in skinning.OpaqueDraws)
		{
			let proxy = world.SkinnedMeshes.Get(draw.ProxyHandle);
			if (proxy == null) continue;

			let mesh = resources.GetMesh(draw.MeshHandle);
			if (mesh == null) continue;
			if (draw.SubMeshIndex >= (uint32)mesh.SubMeshes.Count) continue;
			let subMesh = mesh.SubMeshes[draw.SubMeshIndex];

			rp.SetVertexBuffer(0, draw.OutputVertexBuffer, 0);

			var objUniforms = ObjectUniforms();
			objUniforms.WorldMatrix = proxy.Transform;
			objUniforms.PrevWorldMatrix = proxy.PrevTransform;
			Matrix.Invert(proxy.Transform, out objUniforms.NormalMatrix);
			objUniforms.NormalMatrix = Matrix.Transpose(objUniforms.NormalMatrix);

			let dynamicOffset = objectUniforms.AllocateObject(objUniforms);
			if (dynamicOffset == uint32.MaxValue) return;

			uint32[1] offsets = .(dynamicOffset);
			rp.SetBindGroup(1, objectBindGroup, Span<uint32>(&offsets[0], 1));

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
		// Pipeline is owned by RenderPipelineCache, not us
		mDepthPipeline = null;

		if (mDepthMaterialDef != null)
		{
			mDepthMaterialDef.Release(device);
			delete mDepthMaterialDef;
		}
	}
}
