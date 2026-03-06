namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU parameters for depth of field (must match dof.frag.hlsl cbuffer).
[CRepr]
struct DOFParams
{
	public float FocusDistance;
	public float FocusRange;
	public float BokehSize;
	public float NearPlane;
	public float FarPlane;
	public float TexelSizeX;
	public float TexelSizeY;
	public float _Pad;

	public static int Size => 32;
}

/// Post-process effect that applies depth of field blur.
/// Uses single-pass Poisson disc gather with circle-of-confusion from depth.
public class DOFEffect : IPostProcessEffect
{
	private RenderSystem mRenderSystem;
	private IDevice mDevice;

	private IRenderPipeline mPipeline ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IBuffer mParamsBuffer ~ delete _;
	private ISampler mLinearSampler ~ delete _;
	private ISampler mPointSampler ~ delete _;

	private IBindGroup[RenderConfig.FrameBufferCount] mBindGroups;

	private bool mEnabled = true;

	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "DOF";

	public int Priority => 210;

	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Linear sampler for color
		SamplerDescriptor linearDesc = .();
		linearDesc.Label = "DOF Linear Sampler";
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

		// Point sampler for depth (exact texel lookups)
		SamplerDescriptor pointDesc = .();
		pointDesc.Label = "DOF Point Sampler";
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

		// Params buffer
		BufferDescriptor bufDesc = .();
		bufDesc.Label = "DOF Params";
		bufDesc.Size = (uint64)DOFParams.Size;
		bufDesc.Usage = .Uniform;
		bufDesc.MemoryAccess = .Upload;

		switch (device.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Bind group layout: b0=params, t0=source, t1=depth, s0=linear, s1=point
		BindGroupLayoutEntry[5] layoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler },
			.() { Binding = 1, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDescriptor layoutDesc = .();
		layoutDesc.Label = "DOF BindGroup Layout";
		layoutDesc.Entries = layoutEntries;

		switch (device.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor plDesc = .(layouts);
		switch (device.CreatePipelineLayout(&plDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		if (CreatePipeline(device) case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreatePipeline(IDevice device)
	{
		if (mRenderSystem?.ShaderSystem == null)
			return .Ok;

		let shaderResult = mRenderSystem.ShaderSystem.GetShaderPair("dof");
		if (shaderResult case .Err)
			return .Ok;

		let (vertShader, fragShader) = shaderResult.Value;

		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = "DOF Pipeline",
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

		let world = mRenderSystem?.ActiveWorld;
		if (world == null || !world.DOFEnabled)
			return;

		if (!depthHandle.IsValid)
			return;

		// Upload params
		var dofParams = DOFParams();
		dofParams.FocusDistance = world.DOFFocusDistance;
		dofParams.FocusRange = world.DOFFocusRange;
		dofParams.BokehSize = world.DOFBokehSize;
		dofParams.NearPlane = view.NearPlane;
		dofParams.FarPlane = view.FarPlane;
		dofParams.TexelSizeX = 1.0f / (float)view.Width;
		dofParams.TexelSizeY = 1.0f / (float)view.Height;

		mDevice.Queue.WriteMappedBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&dofParams, DOFParams.Size)
		);

		RenderGraph graphRef = graph;
		RGResourceHandle inputCopy = inputHandle;
		RGResourceHandle depthCopy = depthHandle;

		graph.AddGraphicsPass("PostProcess_DOF")
			.ReadTexture(inputHandle)
			.ReadTexture(depthHandle)
			.WriteColor(outputHandle, .DontCare, .Store)
			.NeverCull()
			.SetExecuteCallback(new [=] (encoder) => {
				let inputView = graphRef.GetTextureView(inputCopy);
				let depthView = graphRef.GetDepthOnlyTextureView(depthCopy);
				ExecutePass(encoder, view, inputView, depthView);
			});
	}

	private void ExecutePass(IRenderPassEncoder encoder, RenderView view,
		ITextureView inputView, ITextureView depthView)
	{
		if (inputView == null || depthView == null)
			return;

		let frameIndex = FrameIndex;

		if (mBindGroups[frameIndex] != null)
		{
			delete mBindGroups[frameIndex];
			mBindGroups[frameIndex] = null;
		}

		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(0, mParamsBuffer, 0, (uint64)DOFParams.Size),
			BindGroupEntry.Texture(0, inputView),
			BindGroupEntry.Texture(1, depthView),
			BindGroupEntry.Sampler(0, mLinearSampler),
			BindGroupEntry.Sampler(1, mPointSampler)
		);

		BindGroupDescriptor bgDesc = .();
		bgDesc.Label = "DOF BindGroup";
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
