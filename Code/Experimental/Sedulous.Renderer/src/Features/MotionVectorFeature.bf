namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Motion vector generation feature.
/// Combines per-object motion vectors (static + skinned meshes) with
/// a full-screen camera-motion pass for sky/background pixels.
class MotionVectorFeature : IRenderFeature
{
	private IDevice mDevice;
	private RenderSystem mSystem;
	private RenderPipelineCache mPipelineCache;

	// Full-screen camera motion pass (sky/background)
	private IRenderPipeline mFullscreenPipeline;
	private IPipelineLayout mFullscreenPipelineLayout;
	private IBindGroupLayout mDepthBindGroupLayout;
	private IBindGroup[RenderConfig.FrameBufferCount] mDepthBindGroups;
	private ISampler mPointSampler;

	// Per-object motion vector material definitions
	private MaterialDefinition mStaticMotionDef;
	private MaterialDefinition mSkinnedMotionDef;

	/// The motion vector texture created this frame (valid after OnAddPasses).
	public RGTexture MotionVectorTexture;

	public StringView Name => "MotionVectors";

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;
		mSystem = initCtx.System;
		mPipelineCache = initCtx.Pipelines;

		// Register shaders
		if (initCtx.Shaders.RegisterShader("motion_vectors") case .Err)
			return .Err;
		if (initCtx.Shaders.RegisterShader("motion_vectors_object") case .Err)
			return .Err;

		// --- Full-screen pass resources ---

		let samplerResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Nearest,
			MagFilter = .Nearest,
			MipmapFilter = .Nearest,
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			Label = "MotionVectors_PointSampler"
		});
		if (samplerResult case .Err)
			return .Err;
		mPointSampler = samplerResult.Value;

		BindGroupLayoutEntry[2] depthEntries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(1, .Fragment)
		);
		let layoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = depthEntries,
			Label = "MotionVectors_DepthLayout"
		});
		if (layoutResult case .Err)
			return .Err;
		mDepthBindGroupLayout = layoutResult.Value;

		IBindGroupLayout[2] fsLayouts = .(mSystem.SceneBindGroupLayout, mDepthBindGroupLayout);
		let fsPipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = fsLayouts,
			Label = "MotionVectors_FullscreenPipelineLayout"
		});
		if (fsPipeLayoutResult case .Err)
			return .Err;
		mFullscreenPipelineLayout = fsPipeLayoutResult.Value;

		let fsVS = initCtx.Shaders.GetCompiledShader("motion_vectors", .Vertex);
		if (fsVS case .Err) return .Err;
		let fsPS = initCtx.Shaders.GetCompiledShader("motion_vectors", .Fragment);
		if (fsPS case .Err) return .Err;

		var colorTarget = ColorTargetState() { Format = .RG16Float };
		let fsPipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mFullscreenPipelineLayout,
			Vertex = .() { Shader = .(fsVS.Value, "VSMain" ) },
			Fragment = .() { Shader = .(fsPS.Value, "PSMain"), Targets = Span<ColorTargetState>(&colorTarget, 1) },
			Primitive = PrimitiveState() { Topology = .TriangleList },
			Label = "MotionVectors_FullscreenPipeline"
		});
		if (fsPipeResult case .Err) return .Err;
		mFullscreenPipeline = fsPipeResult.Value;

		// --- Per-object motion vector material definitions ---

		// Static mesh motion vectors (uses PrevWorldMatrix * position)
		mStaticMotionDef = new MaterialDefinition();
		mStaticMotionDef.Name = new String("MotionVectorsStatic");
		mStaticMotionDef.ShaderName = new String("motion_vectors_object");
		mStaticMotionDef.BlendMode = .Opaque;
		mStaticMotionDef.CullMode = .Back;
		mStaticMotionDef.DepthMode = .ReadOnly;
		if (mStaticMotionDef.BuildLayout(mDevice) case .Err) return .Err;

		// Skinned mesh motion vectors (uses PrevPosition from second VB)
		mSkinnedMotionDef = new MaterialDefinition();
		mSkinnedMotionDef.Name = new String("MotionVectorsSkinned");
		mSkinnedMotionDef.ShaderName = new String("motion_vectors_object");
		mSkinnedMotionDef.BlendMode = .Opaque;
		mSkinnedMotionDef.CullMode = .Back;
		mSkinnedMotionDef.DepthMode = .ReadOnly;
		if (mSkinnedMotionDef.BuildLayout(mDevice) case .Err) return .Err;

		return .Ok;
	}

	public void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
	{
		let depthPrepass = mSystem.GetFeature<DepthPrepassFeature>();
		if (depthPrepass == null) return;
		let depthTex = depthPrepass.DepthTexture;
		if (!depthTex.IsValid) return;

		let system = mSystem;
		let device = mDevice;
		let pipelineCache = mPipelineCache;
		let pointSampler = mPointSampler;
		let depthBindGroupLayout = mDepthBindGroupLayout;
		let fullscreenPipeline = mFullscreenPipeline;
		let renderW = viewCtx.RenderWidth;
		let renderH = viewCtx.RenderHeight;
		let frameIndex = system.FrameIndex;

		graph.AddPass("MotionVectors", .Graphics, scope [&] (builder) =>
		{
			MotionVectorTexture = builder.CreateTexture(
				RGTextureDesc.RenderTarget(.RG16Float, renderW, renderH, 1, "MotionVectors"));

			builder.WriteRenderTarget(MotionVectorTexture, 0, .Clear, .Store,
				ClearColor(0.0f, 0.0f, 0.0f, 0.0f));

			builder.ReadDepthStencil(depthTex);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);

				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
				rp.SetScissor(0, 0, renderW, renderH);

				// Phase 1: Per-object motion vectors (static meshes)
				DrawStaticMeshMotion(rp, system, pipelineCache, device);

				// Phase 2: Per-vertex motion vectors (skinned meshes)
				DrawSkinnedMeshMotion(rp, system, pipelineCache, device);

				rp.End();
			});
		});

		// Full-screen camera motion pass (sky/background pixels where depth == 1.0)
		graph.AddPass("MotionVectorsSky", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(MotionVectorTexture, 0, .Load, .Store);
			builder.ReadTexture(depthTex, .Fragment);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let resolvedDepthView = registry.GetTextureView(depthTex);
				if (resolvedDepthView == null) return;

				if (mDepthBindGroups[frameIndex] != null)
					device.DestroyBindGroup(ref mDepthBindGroups[frameIndex]);

				BindGroupEntry[2] entries = .(
					BindGroupEntry.Texture(resolvedDepthView),
					BindGroupEntry.Sampler(pointSampler)
				);
				let bgResult = device.CreateBindGroup(BindGroupDesc()
				{
					Layout = depthBindGroupLayout,
					Entries = entries,
					Label = "MotionVectors_DepthBindGroup"
				});
				if (bgResult case .Err) return;
				mDepthBindGroups[frameIndex] = bgResult.Value;

				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);

				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
				rp.SetScissor(0, 0, renderW, renderH);
				rp.SetPipeline(fullscreenPipeline);

				if (system.SceneBindGroup != null)
					rp.SetBindGroup(0, system.SceneBindGroup);
				rp.SetBindGroup(1, mDepthBindGroups[frameIndex]);

				rp.Draw(3, 1, 0, 0);
				rp.End();
			});
		});
	}

	private void DrawStaticMeshMotion(IRenderPassEncoder rp, RenderSystem system,
		RenderPipelineCache pipelineCache, IDevice device)
	{
		let batcher = system.Batcher;
		let world = system.ActiveWorld;
		let resources = system.Resources;
		let objectUniforms = system.ObjectUniforms;

		if (batcher.OpaqueBatches.Count == 0) return;

		// Get or create static motion vector pipeline
		var vertexLayout = VertexLayoutHelper.GetStaticMeshLayout();
		let pipeResult = pipelineCache.GetOrCreate(
			mStaticMotionDef,
			Span<VertexBufferLayout>(&vertexLayout, 1),
			system.SceneBindGroupLayout,
			.RG16Float,
			.Depth32Float,
			1,
			.None,
			system.ObjectBindGroupLayout);

		if (pipeResult case .Err) return;
		rp.SetPipeline(pipeResult.Value);

		if (system.SceneBindGroup != null)
			rp.SetBindGroup(0, system.SceneBindGroup);

		for (int i = 0; i < batcher.OpaqueBatches.Count; i++)
		{
			let batch = batcher.OpaqueBatches[i];
			let group = batcher.InstanceGroups[batch.GroupIndex];

			let mesh = resources.GetMesh(batch.MeshHandle);
			if (mesh == null) continue;
			if (batch.SubMeshIndex >= (uint32)mesh.SubMeshes.Count) continue;
			let subMesh = mesh.SubMeshes[batch.SubMeshIndex];

			rp.SetVertexBuffer(0, mesh.VertexBuffer, 0);
			if (mesh.IndexBuffer != null)
				rp.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);

			for (uint32 j = 0; j < group.Count; j++)
			{
				let proxyHandle = batcher.InstanceProxies[group.StartIndex + j];
				let proxy = world.StaticMeshes.Get(proxyHandle);
				if (proxy == null) continue;
				if (!proxy.Flags.HasFlag(.MotionVectors)) continue;

				var objUniforms = ObjectUniforms();
				objUniforms.WorldMatrix = proxy.Transform;
				objUniforms.PrevWorldMatrix = proxy.Transform; // Static meshes don't move yet
				Matrix.Invert(proxy.Transform, out objUniforms.NormalMatrix);
				objUniforms.NormalMatrix = Matrix.Transpose(objUniforms.NormalMatrix);

				let dynamicOffset = objectUniforms.AllocateObject(objUniforms);
				if (dynamicOffset == uint32.MaxValue) return;

				uint32[1] offsets = .(dynamicOffset);
				rp.SetBindGroup(1, system.ObjectBindGroup, Span<uint32>(&offsets[0], 1));

				rp.DrawIndexed(subMesh.IndexCount, 1, subMesh.IndexStart, subMesh.BaseVertex, 0);
			}
		}
	}

	private void DrawSkinnedMeshMotion(IRenderPassEncoder rp, RenderSystem system,
		RenderPipelineCache pipelineCache, IDevice device)
	{
		let skinning = system.Skinning;
		if (skinning.OpaqueDraws.Count == 0) return;

		let world = system.ActiveWorld;
		let resources = system.Resources;
		let objectUniforms = system.ObjectUniforms;

		// Get or create skinned motion vector pipeline (two vertex buffers)
		var meshLayout = VertexLayoutHelper.GetStaticMeshLayout();
		var prevPosLayout = VertexLayoutHelper.GetPrevPositionLayout();
		VertexBufferLayout[2] skinnedLayouts = .(meshLayout, prevPosLayout);

		let pipeResult = pipelineCache.GetOrCreate(
			mSkinnedMotionDef,
			Span<VertexBufferLayout>(&skinnedLayouts[0], 2),
			system.SceneBindGroupLayout,
			.RG16Float,
			.Depth32Float,
			1,
			.Skinned,
			system.ObjectBindGroupLayout);

		if (pipeResult case .Err) return;
		rp.SetPipeline(pipeResult.Value);

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

			// Slot 0: current skinned vertices (48 bytes)
			rp.SetVertexBuffer(0, draw.OutputVertexBuffer, 0);
			// Slot 1: previous-frame skinned positions (12 bytes)
			rp.SetVertexBuffer(1, draw.PrevPositionBuffer, 0);

			var objUniforms = ObjectUniforms();
			objUniforms.WorldMatrix = proxy.Transform;
			objUniforms.PrevWorldMatrix = proxy.PrevTransform;
			Matrix.Invert(proxy.Transform, out objUniforms.NormalMatrix);
			objUniforms.NormalMatrix = Matrix.Transpose(objUniforms.NormalMatrix);

			let dynamicOffset = objectUniforms.AllocateObject(objUniforms);
			if (dynamicOffset == uint32.MaxValue) return;

			uint32[1] offsets = .(dynamicOffset);
			rp.SetBindGroup(1, system.ObjectBindGroup, Span<uint32>(&offsets[0], 1));

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
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mDepthBindGroups[i] != null)
				device.DestroyBindGroup(ref mDepthBindGroups[i]);
		}

		if (mFullscreenPipeline != null)
			device.DestroyRenderPipeline(ref mFullscreenPipeline);
		if (mFullscreenPipelineLayout != null)
			device.DestroyPipelineLayout(ref mFullscreenPipelineLayout);
		if (mDepthBindGroupLayout != null)
			device.DestroyBindGroupLayout(ref mDepthBindGroupLayout);
		if (mPointSampler != null)
			device.DestroySampler(ref mPointSampler);

		if (mStaticMotionDef != null)
		{
			mStaticMotionDef.Release(device);
			delete mStaticMotionDef;
		}
		if (mSkinnedMotionDef != null)
		{
			mSkinnedMotionDef.Release(device);
			delete mSkinnedMotionDef;
		}
	}
}
