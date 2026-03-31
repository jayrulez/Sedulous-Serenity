namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU parameters for color grading (must match color_grading.frag.hlsl cbuffer).
[CRepr]
struct ColorGradingParams
{
	public float LUTSize;
	public float InvLUTSize;
	public float _Pad0;
	public float _Pad1;

	public static int Size => 16;
}

/// Post-process effect that applies color grading via a 3D LUT.
/// The LUT is stored as a 2D atlas: 32 slices of 32x32 = 1024x32 RGBA8.
/// A neutral identity LUT is generated at init; apps can override via RenderWorld.ColorGradingLUT.
public class ColorGradingEffect : IPostProcessEffect
{
	private const int32 LUTSize = 32;

	private RenderSystem mRenderSystem;
	private IDevice mDevice;
	private IQueue mQueue;

	private IRenderPipeline mPipeline;
	private IPipelineLayout mPipelineLayout;
	private IBindGroupLayout mBindGroupLayout;
	private IBuffer mParamsBuffer;
	private ISampler mLinearSampler;
	private ISampler mLUTSampler;

	// Neutral identity LUT
	private ITexture mNeutralLUT;
	private ITextureView mNeutralLUTView;

	private IBindGroup[RenderConfig.FrameBufferCount] mBindGroups;

	private bool mEnabled = true;

	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "ColorGrading";

	public int Priority => 420;

	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;
		mQueue = device.GetQueue(.Graphics);

		// Linear sampler for source
		SamplerDesc linearDesc = .();
		linearDesc.Label = "ColorGrading Linear Sampler";
		linearDesc.AddressU = .ClampToEdge;
		linearDesc.AddressV = .ClampToEdge;
		linearDesc.AddressW = .ClampToEdge;
		linearDesc.MinFilter = .Linear;
		linearDesc.MagFilter = .Linear;
		linearDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(linearDesc))
		{
		case .Ok(let sampler): mLinearSampler = sampler;
		case .Err: return .Err;
		}

		// LUT sampler (linear clamp for smooth interpolation between LUT entries)
		SamplerDesc lutDesc = .();
		lutDesc.Label = "ColorGrading LUT Sampler";
		lutDesc.AddressU = .ClampToEdge;
		lutDesc.AddressV = .ClampToEdge;
		lutDesc.AddressW = .ClampToEdge;
		lutDesc.MinFilter = .Linear;
		lutDesc.MagFilter = .Linear;
		lutDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(lutDesc))
		{
		case .Ok(let sampler): mLUTSampler = sampler;
		case .Err: return .Err;
		}

		// Params buffer
		BufferDesc bufDesc = .();
		bufDesc.Label = "ColorGrading Params";
		bufDesc.Size = (uint64)ColorGradingParams.Size;
		bufDesc.Usage = .Uniform;
		bufDesc.Memory = .CpuToGpu;

		switch (device.CreateBuffer(bufDesc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Bind group layout: b0=params, t0=source, t1=LUT, s0=linear, s1=LUTsampler
		BindGroupLayoutEntry[5] layoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler },
			.() { Binding = 1, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDesc layoutDesc = .();
		layoutDesc.Label = "ColorGrading BindGroup Layout";
		layoutDesc.Entries = layoutEntries;

		switch (device.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDesc plDesc = .(layouts);
		switch (device.CreatePipelineLayout(plDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		if (CreatePipeline(device) case .Err)
			return .Err;

		// Generate neutral identity LUT
		GenerateNeutralLUT(device);

		return .Ok;
	}

	private void GenerateNeutralLUT(IDevice device)
	{
		// 1024x32 RGBA8 atlas: 32 slices of 32x32
		let atlasWidth = (uint32)(LUTSize * LUTSize); // 1024
		let atlasHeight = (uint32)LUTSize;              // 32

		// Generate identity LUT data: output color = input color
		uint8[] data = new uint8[atlasWidth * atlasHeight * 4];
		defer delete data;

		for (int32 b = 0; b < LUTSize; b++) // blue = slice index
		{
			for (int32 g = 0; g < LUTSize; g++) // green = row within slice
			{
				for (int32 r = 0; r < LUTSize; r++) // red = column within slice
				{
					int32 x = b * LUTSize + r;
					int32 y = g;
					int32 idx = (y * (int32)atlasWidth + x) * 4;
					data[idx + 0] = (uint8)((r * 255) / (LUTSize - 1));
					data[idx + 1] = (uint8)((g * 255) / (LUTSize - 1));
					data[idx + 2] = (uint8)((b * 255) / (LUTSize - 1));
					data[idx + 3] = 255;
				}
			}
		}

		// Create texture
		TextureDesc texDesc = .();
		texDesc.Width = atlasWidth;
		texDesc.Height = atlasHeight;
		texDesc.Depth = 1;
		texDesc.Format = .RGBA8Unorm;
		texDesc.Usage = .Sampled | .CopyDst;
		texDesc.Dimension = .Texture2D;
		texDesc.MipLevelCount = 1;
		texDesc.SampleCount = 1;
		texDesc.Label = "ColorGrading Neutral LUT";

		if (device.CreateTexture(texDesc) case .Ok(let tex))
			mNeutralLUT = tex;
		else
			return;

		// Upload data
		TextureDataLayout layout = .() { BytesPerRow = atlasWidth * 4, RowsPerImage = atlasHeight };
		Extent3D size = .(atlasWidth, atlasHeight, 1);
		TransferHelper.WriteTextureSync(mQueue, mDevice, mNeutralLUT, Span<uint8>(&data[0], data.Count), layout, size, 0, 0);

		// Create view
		TextureViewDesc viewDesc = .();
		viewDesc.Format = .RGBA8Unorm;
		viewDesc.Dimension = .Texture2D;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = 1;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = 1;
		viewDesc.Aspect = .All;

		if (device.CreateTextureView(mNeutralLUT, viewDesc) case .Ok(let view))
			mNeutralLUTView = view;
	}

	private Result<void> CreatePipeline(IDevice device)
	{
		if (mRenderSystem?.ShaderSystem == null)
			return .Ok;

		let shaderResult = mRenderSystem.ShaderSystem.GetShaderPair("color_grading");
		if (shaderResult case .Err)
			return .Ok;

		let (vertShader, fragShader) = shaderResult.Value;

		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "ColorGrading Pipeline",
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

		switch (device.CreateRenderPipeline(pipelineDesc))
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
			if (mBindGroups[i] != null) mDevice.DestroyBindGroup(ref mBindGroups[i]);
		}

		if (mNeutralLUTView != null) mDevice.DestroyTextureView(ref mNeutralLUTView);
		if (mNeutralLUT != null) mDevice.DestroyTexture(ref mNeutralLUT);
		if (mPipeline != null) mDevice.DestroyRenderPipeline(ref mPipeline);
		if (mPipelineLayout != null) mDevice.DestroyPipelineLayout(ref mPipelineLayout);
		if (mBindGroupLayout != null) mDevice.DestroyBindGroupLayout(ref mBindGroupLayout);
		if (mParamsBuffer != null) mDevice.DestroyBuffer(ref mParamsBuffer);
		if (mLinearSampler != null) mDevice.DestroySampler(ref mLinearSampler);
		if (mLUTSampler != null) mDevice.DestroySampler(ref mLUTSampler);
	}

	public void AddPasses(
		RenderGraph graph,
		ViewContext view,
		RGHandle inputHandle,
		RGHandle outputHandle,
		RGHandle depthHandle)
	{
		if (mPipeline == null)
			return;

		let world = mRenderSystem?.ActiveWorld;
		if (world == null || !world.ColorGradingEnabled)
			return;

		// Use world LUT if available, otherwise neutral
		ITextureView lutView = null;
		if (world.ColorGradingLUT != null)
			lutView = world.ColorGradingLUT;
		else
			lutView = mNeutralLUTView;

		if (lutView == null)
			return;

		// Upload params
		var cgParams = ColorGradingParams();
		cgParams.LUTSize = (float)LUTSize;
		cgParams.InvLUTSize = 1.0f / (float)LUTSize;

		TransferHelper.WriteMappedBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&cgParams, ColorGradingParams.Size)
		);

		RenderGraph graphRef = graph;
		RGHandle inputCopy = inputHandle;
		ITextureView lutViewCopy = lutView;

		graph.AddRenderPass("PostProcess_ColorGrading", scope (builder) => {
				builder.ReadTexture(inputHandle);
				builder.SetColorTarget(0, outputHandle, .DontCare, .Store);
				builder.NeverCull();
				builder.SetExecute(new [=] (encoder) => {
					let inputView = graphRef.GetTextureView(inputCopy);
					ExecutePass(encoder, view, inputView, lutViewCopy);
				});
			});
	}

	private void ExecutePass(IRenderPassEncoder encoder, ViewContext view,
		ITextureView inputView, ITextureView lutView)
	{
		if (inputView == null || lutView == null)
			return;

		let frameIndex = FrameIndex;

		if (mBindGroups[frameIndex] != null)
		{
			mDevice.DestroyBindGroup(ref mBindGroups[frameIndex]);
		}

		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(/*0,*/mParamsBuffer, 0, (uint64)ColorGradingParams.Size),
			BindGroupEntry.Texture(/*0,*/inputView),
			BindGroupEntry.Texture(/*1,*/lutView),
			BindGroupEntry.Sampler(/*0,*/mLinearSampler),
			BindGroupEntry.Sampler(/*1,*/mLUTSampler)
		);

		BindGroupDesc bgDesc = .();
		bgDesc.Label = "ColorGrading BindGroup";
		bgDesc.Layout = mBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): mBindGroups[frameIndex] = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissor(0, 0, view.Width, view.Height);

		encoder.SetPipeline(mPipeline);
		encoder.SetBindGroup(0, mBindGroups[frameIndex], default);
		encoder.Draw(3, 1, 0, 0);

		if (mRenderSystem != null)
			mRenderSystem.Stats.DrawCalls++;
	}
}
