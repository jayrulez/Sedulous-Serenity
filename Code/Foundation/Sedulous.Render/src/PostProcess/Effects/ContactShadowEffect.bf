namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

/// GPU parameters for contact shadows (must match contact_shadows.frag.hlsl cbuffer).
[CRepr]
struct ContactShadowParams
{
	public Matrix ProjectionMatrix;      // 64
	public Matrix InvProjectionMatrix;   // 64
	public Vector3 LightDirViewSpace;    // 12
	public float ContactShadowLength;    // 4
	public float TexelSizeX;             // 4
	public float TexelSizeY;             // 4
	public float NearPlane;              // 4
	public float FarPlane;               // 4

	public static int Size => 160;
}

/// Post-process effect that adds screen-space contact shadows.
/// Short-range ray march toward the main directional light for fine shadow detail.
public class ContactShadowEffect : IPostProcessEffect
{
	private RenderSystem mRenderSystem;
	private IDevice mDevice;

	// Pipeline resources
	private IRenderPipeline mPipeline ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IBuffer mParamsBuffer ~ delete _;
	private ISampler mPointSampler ~ delete _;

	// Per-frame bind groups
	private IBindGroup[RenderConfig.FrameBufferCount] mBindGroups;

	private bool mEnabled = true;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	/// Creates a new contact shadow effect.
	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "ContactShadows";

	public int Priority => 50; // Pre-lighting range

	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create point sampler
		SamplerDesc samplerDesc = .();
		samplerDesc.Label = "ContactShadow Point Sampler";
		samplerDesc.AddressU = .ClampToEdge;
		samplerDesc.AddressV = .ClampToEdge;
		samplerDesc.AddressW = .ClampToEdge;
		samplerDesc.MinFilter = .Nearest;
		samplerDesc.MagFilter = .Nearest;
		samplerDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(samplerDesc))
		{
		case .Ok(let sampler): mPointSampler = sampler;
		case .Err: return .Err;
		}

		// Create params buffer
		BufferDesc bufDesc = .();
		bufDesc.Label = "ContactShadow Params";
		bufDesc.Size = (uint64)ContactShadowParams.Size;
		bufDesc.Usage = .Uniform;
		bufDesc.MemoryAccess = .CpuToGpu;

		switch (device.CreateBuffer(bufDesc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Create bind group layout: b0=params, t0=sceneColor, t1=depth, t2=gbuffer, s0=point sampler
		BindGroupLayoutEntry[5] layoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDesc layoutDesc = .();
		layoutDesc.Label = "ContactShadow BindGroup Layout";
		layoutDesc.Entries = layoutEntries;

		switch (device.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDesc plDesc = .(layouts);
		switch (device.CreatePipelineLayout(plDesc))
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

		let shaderResult = mRenderSystem.ShaderSystem.GetShaderPair("contact_shadows");
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "ContactShadow Pipeline",
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
			if (mBindGroups[i] != null)
			{
				delete mBindGroups[i];
				mBindGroups[i] = null;
			}
		}
	}

	/// Finds the main directional light direction from the active world.
	private bool GetDirectionalLightDirection(out Vector3 direction)
	{
		direction = .(0, -1, 0); // Default downward
		let world = mRenderSystem?.ActiveWorld;
		if (world == null)
			return false;

		bool found = false;
		world.ForEachLight(scope [&] (handle, proxy) =>
		{
			if (!found && proxy.Type == .Directional && proxy.IsEnabled)
			{
				direction = proxy.Direction;
				found = true;
			}
		});

		return found;
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

		// Check enabled on world
		let world = mRenderSystem?.ActiveWorld;
		if (world == null || !world.ContactShadowsEnabled)
			return;

		// Look up GBuffer for normals (required)
		let gbufferHandle = graph.GetResource("SceneNormalRoughness");
		if (!gbufferHandle.IsValid)
			return;

		// Get directional light direction
		Vector3 lightDir;
		if (!GetDirectionalLightDirection(out lightDir))
			return;

		// Transform light direction to view space
		// ViewMatrix transforms world→view, for directions use the upper 3x3
		Vector3 lightDirView = Vector3.TransformNormal(lightDir, view.ViewMatrix);
		lightDirView = Vector3.Normalize(lightDirView);

		// Compute inverse projection
		var invProj = view.ProjectionMatrix;
		Matrix.Invert(view.ProjectionMatrix, out invProj);

		// Upload params
		var csParams = ContactShadowParams();
		csParams.ProjectionMatrix = view.ProjectionMatrix;
		csParams.InvProjectionMatrix = invProj;
		csParams.LightDirViewSpace = lightDirView;
		csParams.ContactShadowLength = world.ContactShadowLength;
		csParams.TexelSizeX = 1.0f / (float)view.Width;
		csParams.TexelSizeY = 1.0f / (float)view.Height;
		csParams.NearPlane = view.NearPlane;
		csParams.FarPlane = view.FarPlane;

		mDevice.Queue.WriteMappedBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&csParams, ContactShadowParams.Size)
		);

		// Capture for callback
		RenderGraph graphRef = graph;
		RGResourceHandle inputCopy = inputHandle;
		RGResourceHandle depthCopy = depthHandle;
		RGResourceHandle gbufferCopy = gbufferHandle;

		graph.AddGraphicsPass("PostProcess_ContactShadows")
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

		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(0, mParamsBuffer, 0, (uint64)ContactShadowParams.Size),
			BindGroupEntry.Texture(0, inputView),
			BindGroupEntry.Texture(1, depthView),
			BindGroupEntry.Texture(2, gbufferView),
			BindGroupEntry.Sampler(0, mPointSampler)
		);

		BindGroupDesc bgDesc = .();
		bgDesc.Label = "ContactShadow BindGroup";
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
