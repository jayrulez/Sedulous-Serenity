namespace RendererSandbox;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Renderer;
using Sedulous.Core.Mathematics;

/// Simple render feature that draws a colored triangle.
/// Exercises: ShaderLibrary, MaterialDefinition, MaterialInstance,
/// RenderPipelineCache, GPUResourceManager, and the render graph.
class TriangleFeature : IRenderFeature
{
	private const StringView ShaderSource =
		"""
		struct VSInput
		{
			float3 Position : TEXCOORD0;
			float3 Color    : TEXCOORD1;
		};

		struct PSInput
		{
			float4 Position : SV_Position;
			float3 Color    : TEXCOORD0;
		};

		cbuffer MaterialProps : register(b0, space1)
		{
			float4 Tint;
		};

		PSInput VSMain(VSInput input)
		{
			PSInput output;
			output.Position = float4(input.Position, 1.0);
			output.Color = input.Color;
			return output;
		}

		float4 PSMain(PSInput input) : SV_Target
		{
			return float4(input.Color * Tint.rgb, Tint.a);
		}
		""";

	private GPUMeshHandle mTriangleMesh;
	private MaterialDefinition mMaterialDef;
	private MaterialInstance mMaterialInst;
	private IBindGroupLayout mSceneLayout;
	private GPUResourceManager mResources;
	private RenderPipelineCache mPipelineCache;
	private IDevice mDevice;

	public StringView Name => "Triangle";

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;
		mResources = initCtx.Resources;
		mPipelineCache = initCtx.Pipelines;

		// Register shader
		initCtx.Shaders.RegisterShader("Triangle", ShaderSource);

		// Upload triangle mesh
		float[18] vertices = .(
			// Position        Color
			 0.0f,  0.5f, 0.0f,   1.0f, 0.0f, 0.0f,  // top - red
			 0.5f, -0.5f, 0.0f,   0.0f, 1.0f, 0.0f,  // right - green
			-0.5f, -0.5f, 0.0f,   0.0f, 0.0f, 1.0f   // left - blue
		);

		uint16[3] indices = .(0, 1, 2);

		GPUSubMesh[1] subMeshes = .(.()
		{
			IndexStart = 0,
			IndexCount = 3,
			BaseVertex = 0,
			MaterialSlot = 0
		});

		let meshBounds = BoundingBox(Vector3(-0.5f, -0.5f, 0.0f), Vector3(0.5f, 0.5f, 0.0f));
		let meshResult = initCtx.Resources.UploadMesh(
			Span<uint8>((uint8*)&vertices, sizeof(float[18])),
			3,   // vertex count
			24,  // stride: 6 floats * 4 bytes
			Span<uint8>((uint8*)&indices, sizeof(uint16[3])),
			3,   // index count
			.UInt16,
			subMeshes,
			default,  // no LODs
			meshBounds,
			false,    // not skinned
			initCtx.TransferBatch);

		if (meshResult case .Err)
			return .Err;
		mTriangleMesh = meshResult.Value;

		// Create material definition
		mMaterialDef = new MaterialDefinition();
		mMaterialDef.Name = new String("TriangleMat");
		mMaterialDef.ShaderName = new String("Triangle");
		mMaterialDef.BlendMode = .Opaque;
		mMaterialDef.CullMode = .None;
		mMaterialDef.DepthMode = .Disabled;

		// Add tint property (float4)
		mMaterialDef.AddScalarProperty("Tint", .Float4);

		// Create a minimal scene bind group layout (empty — we don't use scene uniforms)
		let sceneLayoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Label = "EmptySceneLayout"
		});
		if (sceneLayoutResult case .Err)
			return .Err;
		mSceneLayout = sceneLayoutResult.Value;

		// Build material bind group layout
		if (mMaterialDef.BuildLayout(mDevice) case .Err)
			return .Err;

		// Create material instance
		mMaterialInst = new MaterialInstance();
		if (mMaterialInst.Initialize(mDevice, mMaterialDef) case .Err)
			return .Err;

		// Set tint to white
		mMaterialInst.SetFloat4("Tint", 1.0f, 1.0f, 1.0f, 1.0f);

		Console.WriteLine("TriangleFeature: initialized");
		return .Ok;
	}

	public void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
	{
		let mesh = mResources.GetMesh(mTriangleMesh);
		if (mesh == null)
			return;

		let vertexBuffer = mesh.VertexBuffer;
		let indexBuffer = mesh.IndexBuffer;
		let backbuffer = viewCtx.RenderTarget;
		let renderW = viewCtx.RenderWidth;
		let renderH = viewCtx.RenderHeight;
		let device = mDevice;
		let materialDef = mMaterialDef;
		let materialInst = mMaterialInst;
		let pipelineCache = mPipelineCache;
		let sceneLayout = mSceneLayout;
		let frameIndex = (int)(frameCtx.FrameNumber % RenderConfig.FrameBufferCount);

		graph.AddPass("TriangleDraw", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(backbuffer, 0, .Clear, .Store,
				ClearColor(0.1f, 0.1f, 0.15f, 1.0f));
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				// Rebuild bind group if dirty for this frame slot
				if (materialInst.IsDirty(frameIndex))
					materialInst.RebuildBindGroup(device, frameIndex);

				// Vertex layout for pipeline creation
				var attrs = VertexAttribute[2](
					.() { Format = .Float32x3, Offset = 0, ShaderLocation = 0 },
					.() { Format = .Float32x3, Offset = 12, ShaderLocation = 1 }
				);
				var vertexLayout = VertexBufferLayout()
				{
					Stride = 24,
					StepMode = .Vertex,
					Attributes = Span<VertexAttribute>(&attrs[0], 2)
				};

				// Get or create pipeline
				let pipelineResult = pipelineCache.GetOrCreate(
					materialDef,
					Span<VertexBufferLayout>(&vertexLayout, 1),
					sceneLayout,
					.BGRA8UnormSrgb,
					.Undefined,
					1,
					.None);

				if (pipelineResult case .Err)
					return;

				let pipeline = pipelineResult.Value;

				// Begin render pass
				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);

				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
				rp.SetScissor(0, 0, renderW, renderH);
				rp.SetPipeline(pipeline);
				let matBindGroup = materialInst.GetBindGroup(frameIndex);
				if (matBindGroup != null)
					rp.SetBindGroup(1, matBindGroup);
				rp.SetVertexBuffer(0, vertexBuffer, 0);
				rp.SetIndexBuffer(indexBuffer, .UInt16, 0);
				rp.DrawIndexed(3, 1, 0, 0, 0);

				rp.End();
			});
		});
	}

	/// Animate the tint color.
	public void AnimateTint(float time)
	{
		let r = (Math.Sin(time * 2.0f) * 0.5f + 0.5f);
		let g = (Math.Sin(time * 3.0f) * 0.5f + 0.5f);
		let b = (Math.Sin(time * 5.0f) * 0.5f + 0.5f);
		mMaterialInst.SetFloat4("Tint", r, g, b, 1.0f);
	}

	public void OnPostRender() { }

	public void OnShutdown(IDevice device)
	{
		if (mMaterialInst != null)
		{
			mMaterialInst.Release(device);
			delete mMaterialInst;
		}
		if (mMaterialDef != null)
		{
			mMaterialDef.Release(device);
			delete mMaterialDef;
		}
		if (mSceneLayout != null)
			device.DestroyBindGroupLayout(ref mSceneLayout);
	}
}
