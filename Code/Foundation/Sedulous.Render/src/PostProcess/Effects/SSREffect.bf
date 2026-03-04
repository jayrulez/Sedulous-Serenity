namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

/// GPU parameters for SSR (must match ssr.frag.hlsl cbuffer).
[CRepr]
struct SSRParams
{
	public Matrix ProjectionMatrix;      // 64
	public Matrix InvProjectionMatrix;   // 64
	public float TexelSizeX;             // 4
	public float TexelSizeY;             // 4
	public float Intensity;              // 4
	public float MaxDistance;             // 4
	public float NearPlane;              // 4
	public float FarPlane;               // 4
	public int32 MaxSteps;               // 4
	public float StepSize;               // 4
	public float Thickness;              // 4
	public Vector3 _Pad;                 // 12

	public static int Size => 176;
}

/// Post-process effect that applies screen-space reflections.
/// Linear ray marching against the depth buffer with binary refinement.
public class SSREffect : IPostProcessEffect
{
	private RenderSystem mRenderSystem;
	private IDevice mDevice;

	// Pipeline resources
	private IRenderPipeline mPipeline ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IBuffer mParamsBuffer ~ delete _;
	private ISampler mLinearSampler ~ delete _;
	private ISampler mPointSampler ~ delete _;

	// Per-frame bind groups
	private IBindGroup[RenderConfig.FrameBufferCount] mBindGroups;

	private bool mEnabled = true;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	/// Creates a new SSR effect.
	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "SSR";

	public int Priority => 110; // Lighting effects range, after SSAO

	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create linear sampler (for scene color sampling at hit UV)
		SamplerDescriptor linearDesc = .();
		linearDesc.Label = "SSR Linear Sampler";
		linearDesc.AddressModeU = .ClampToEdge;
		linearDesc.AddressModeV = .ClampToEdge;
		linearDesc.AddressModeW = .ClampToEdge;
		linearDesc.MinFilter = .Linear;
		linearDesc.MagFilter = .Linear;
		linearDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(&linearDesc))
		{
		case .Ok(let sampler): mLinearSampler = sampler;
		case .Err: return .Err;
		}

		// Create point sampler (for depth sampling)
		SamplerDescriptor pointDesc = .();
		pointDesc.Label = "SSR Point Sampler";
		pointDesc.AddressModeU = .ClampToEdge;
		pointDesc.AddressModeV = .ClampToEdge;
		pointDesc.AddressModeW = .ClampToEdge;
		pointDesc.MinFilter = .Nearest;
		pointDesc.MagFilter = .Nearest;
		pointDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(&pointDesc))
		{
		case .Ok(let sampler): mPointSampler = sampler;
		case .Err: return .Err;
		}

		// Create params buffer
		BufferDescriptor bufDesc = .();
		bufDesc.Label = "SSR Params";
		bufDesc.Size = (uint64)SSRParams.Size;
		bufDesc.Usage = .Uniform;
		bufDesc.MemoryAccess = .Upload;

		switch (device.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Create bind group layout: b0=params, t0=sceneColor, t1=depth, t2=gbuffer, s0=linear, s1=point
		BindGroupLayoutEntry[6] layoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler },
			.() { Binding = 1, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDescriptor layoutDesc = .();
		layoutDesc.Label = "SSR BindGroup Layout";
		layoutDesc.Entries = layoutEntries;

		switch (device.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor plDesc = .(layouts);
		switch (device.CreatePipelineLayout(&plDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline
		if (CreatePipeline(device) case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreatePipeline(IDevice device)
	{
		if (mRenderSystem?.ShaderSystem == null)
			return .Ok;

		let shaderResult = mRenderSystem.ShaderSystem.GetShaderPair("ssr");
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = "SSR Pipeline",
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = default
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = null,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		switch (device.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	public void Shutdown()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mBindGroups[i] != null)
			{
				delete mBindGroups[i];
				mBindGroups[i] = null;
			}
		}
	}

	public void AddPasses(
		RenderGraph graph,
		RenderView view,
		RGResourceHandle inputHandle,
		RGResourceHandle outputHandle,
		RGResourceHandle depthHandle)
	{
		if (mPipeline == null)
			return;

		// Check SSR enabled on world
		let world = mRenderSystem?.ActiveWorld;
		if (world == null || !world.SSREnabled)
			return;

		// SSR requires GBuffer for normals and roughness — skip if unavailable
		let gbufferHandle = graph.GetResource("SceneNormalRoughness");
		if (!gbufferHandle.IsValid)
			return;

		// Compute inverse projection
		var invProj = view.ProjectionMatrix;
		Matrix.Invert(view.ProjectionMatrix, out invProj);

		// Upload params
		var ssrParams = SSRParams();
		ssrParams.ProjectionMatrix = view.ProjectionMatrix;
		ssrParams.InvProjectionMatrix = invProj;
		ssrParams.TexelSizeX = 1.0f / (float)view.Width;
		ssrParams.TexelSizeY = 1.0f / (float)view.Height;
		ssrParams.Intensity = world.SSRIntensity;
		ssrParams.MaxDistance = 100.0f;
		ssrParams.NearPlane = view.NearPlane;
		ssrParams.FarPlane = view.FarPlane;
		ssrParams.MaxSteps = 64;
		ssrParams.StepSize = 0.1f;
		ssrParams.Thickness = 0.5f;

		mDevice.Queue.WriteBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&ssrParams, SSRParams.Size)
		);

		// Capture for callback
		RenderGraph graphRef = graph;
		RGResourceHandle inputCopy = inputHandle;
		RGResourceHandle depthCopy = depthHandle;
		RGResourceHandle gbufferCopy = gbufferHandle;

		graph.AddGraphicsPass("PostProcess_SSR")
			.ReadTexture(inputHandle)
			.ReadTexture(depthHandle)
			.ReadTexture(gbufferHandle)
			.WriteColor(outputHandle, .DontCare, .Store)
			.NeverCull()
			.SetExecuteCallback(new [=] (encoder) => {
				let inputView = graphRef.GetTextureView(inputCopy);
				let depthView = graphRef.GetDepthOnlyTextureView(depthCopy);
				let gbufferView = graphRef.GetTextureView(gbufferCopy);
				ExecutePass(encoder, view, inputView, depthView, gbufferView);
			});
	}

	private void ExecutePass(IRenderPassEncoder encoder, RenderView view,
		ITextureView inputView, ITextureView depthView, ITextureView gbufferView)
	{
		if (inputView == null || depthView == null || gbufferView == null)
			return;

		let frameIndex = FrameIndex;

		// Recreate bind group per frame (input is transient)
		if (mBindGroups[frameIndex] != null)
		{
			delete mBindGroups[frameIndex];
			mBindGroups[frameIndex] = null;
		}

		BindGroupEntry[6] entries = .(
			BindGroupEntry.Buffer(0, mParamsBuffer, 0, (uint64)SSRParams.Size),
			BindGroupEntry.Texture(0, inputView),
			BindGroupEntry.Texture(1, depthView),
			BindGroupEntry.Texture(2, gbufferView),
			BindGroupEntry.Sampler(0, mLinearSampler),
			BindGroupEntry.Sampler(1, mPointSampler)
		);

		BindGroupDescriptor bgDesc = .();
		bgDesc.Label = "SSR BindGroup";
		bgDesc.Layout = mBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(&bgDesc))
		{
		case .Ok(let bg): mBindGroups[frameIndex] = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		encoder.SetPipeline(mPipeline);
		encoder.SetBindGroup(0, mBindGroups[frameIndex], default);
		encoder.Draw(3, 1, 0, 0);

		if (mRenderSystem != null)
			mRenderSystem.Stats.DrawCalls++;
	}
}
