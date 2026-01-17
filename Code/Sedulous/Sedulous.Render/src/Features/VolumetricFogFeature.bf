namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Volumetric fog parameters.
[CRepr]
public struct VolumetricFogParams
{
	/// Fog color.
	public Vector3 FogColor;
	public float FogDensity;

	/// Height fog settings.
	public float HeightFalloff;
	public float HeightOffset;
	public float ScatteringCoeff;
	public float AbsorptionCoeff;

	/// Phase function (Henyey-Greenstein).
	public float PhaseG;
	public float MaxDistance;
	public float TemporalBlend;
	public float Padding;

	/// Froxel grid dimensions.
	public uint32 FroxelsX;
	public uint32 FroxelsY;
	public uint32 FroxelsZ;
	public uint32 Padding2;

	/// Default settings.
	public static Self Default => .()
	{
		FogColor = .(0.5f, 0.6f, 0.7f),
		FogDensity = 0.02f,
		HeightFalloff = 0.1f,
		HeightOffset = 0.0f,
		ScatteringCoeff = 0.5f,
		AbsorptionCoeff = 0.1f,
		PhaseG = 0.7f,
		MaxDistance = 200.0f,
		TemporalBlend = 0.9f,
		FroxelsX = 160,
		FroxelsY = 90,
		FroxelsZ = 64
	};

	/// Size in bytes.
	public static int Size => 64;
}

/// Volumetric fog render feature.
/// Uses froxel-based ray marching with temporal reprojection.
public class VolumetricFogFeature : RenderFeatureBase
{
	// Froxel volume textures
	private ITexture mScatteringVolume ~ delete _;
	private ITextureView mScatteringVolumeView ~ delete _;
	private ITexture mIntegratedVolume ~ delete _;
	private ITextureView mIntegratedVolumeView ~ delete _;
	private ITexture mHistoryVolume ~ delete _;
	private ITextureView mHistoryVolumeView ~ delete _;

	// Compute pipelines
	private IComputePipeline mInjectLightPipeline ~ delete _;
	private IComputePipeline mScatterPipeline ~ delete _;
	private IComputePipeline mIntegratePipeline ~ delete _;

	// Apply pipeline
	private IRenderPipeline mApplyPipeline ~ delete _;

	// Bind groups
	private IBindGroupLayout mComputeBindGroupLayout ~ delete _;
	private IBindGroupLayout mApplyBindGroupLayout ~ delete _;
	private IBindGroup mComputeBindGroup ~ delete _;
	private IBindGroup mApplyBindGroup ~ delete _;

	// Parameters
	private VolumetricFogParams mParams = .Default;
	private IBuffer mParamsBuffer ~ delete _;

	// Fullscreen quad
	private IBuffer mFullscreenQuadVB ~ delete _;

	// Temporal history
	private Matrix mPrevViewProjection;

	/// Feature name.
	public override StringView Name => "VolumetricFog";

	/// Gets or sets the fog parameters.
	public ref VolumetricFogParams Params => ref mParams;

	/// Depends on forward opaque for depth and lighting data.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
	}

	protected override Result<void> OnInitialize()
	{
		// Create froxel volume textures
		if (CreateFroxelVolumes() case .Err)
			return .Err;

		// Create parameter buffer
		if (CreateParamsBuffer() case .Err)
			return .Err;

		// Create fullscreen quad
		if (CreateFullscreenQuad() case .Err)
			return .Err;

		// Create pipelines
		if (CreateComputePipelines() case .Err)
			return .Err;

		return .Ok;
	}

	protected override void OnShutdown()
	{
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		if (!view.PostProcess.EnableVolumetricFog)
			return;

		// Get existing resources
		let colorHandle = graph.GetResource("SceneColor");
		let depthHandle = graph.GetResource("SceneDepth");

		if (!colorHandle.IsValid || !depthHandle.IsValid)
			return;

		// Update params
		UpdateParams(view);

		// Add froxel injection pass (inject light into volume)
		graph.AddComputePass("VolumetricFog_Inject")
			.ReadTexture(depthHandle)
			.SetComputeCallback(new (encoder) => {
				ExecuteInjectPass(encoder, view, world);
			});

		// Add scattering pass
		graph.AddComputePass("VolumetricFog_Scatter")
			.SetComputeCallback(new (encoder) => {
				ExecuteScatterPass(encoder);
			});

		// Add integration pass (ray march through volume)
		graph.AddComputePass("VolumetricFog_Integrate")
			.SetComputeCallback(new (encoder) => {
				ExecuteIntegratePass(encoder);
			});

		// Add apply pass (composite fog into scene)
		graph.AddGraphicsPass("VolumetricFog_Apply")
			.WriteColor(colorHandle, .Load, .Store)
			.SetExecuteCallback(new (encoder) => {
				ExecuteApplyPass(encoder, view);
			});

		// Store for temporal reprojection
		mPrevViewProjection = view.ViewProjectionMatrix;
	}

	private Result<void> CreateFroxelVolumes()
	{
		var froxelDesc = TextureDescriptor()
		{
			Label = "Scattering Volume",
			Width = mParams.FroxelsX,
			Height = mParams.FroxelsY,
			Depth = mParams.FroxelsZ,
			Format = .RGBA16Float,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture3D,
			Usage = .Sampled | .Storage
		};

		// Scattering volume
		switch (Renderer.Device.CreateTexture(&froxelDesc))
		{
		case .Ok(let tex): mScatteringVolume = tex;
		case .Err: return .Err;
		}

		TextureViewDescriptor viewDesc = .()
		{
			Label = "Scattering Volume View",
			Dimension = .Texture3D
		};

		switch (Renderer.Device.CreateTextureView(mScatteringVolume, &viewDesc))
		{
		case .Ok(let view): mScatteringVolumeView = view;
		case .Err: return .Err;
		}

		// Integrated volume
		froxelDesc.Label = "Integrated Volume";
		switch (Renderer.Device.CreateTexture(&froxelDesc))
		{
		case .Ok(let tex): mIntegratedVolume = tex;
		case .Err: return .Err;
		}

		viewDesc.Label = "Integrated Volume View";
		switch (Renderer.Device.CreateTextureView(mIntegratedVolume, &viewDesc))
		{
		case .Ok(let view): mIntegratedVolumeView = view;
		case .Err: return .Err;
		}

		// History volume for temporal reprojection
		froxelDesc.Label = "History Volume";
		switch (Renderer.Device.CreateTexture(&froxelDesc))
		{
		case .Ok(let tex): mHistoryVolume = tex;
		case .Err: return .Err;
		}

		viewDesc.Label = "History Volume View";
		switch (Renderer.Device.CreateTextureView(mHistoryVolume, &viewDesc))
		{
		case .Ok(let view): mHistoryVolumeView = view;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateParamsBuffer()
	{
		BufferDescriptor desc = .()
		{
			Label = "Volumetric Fog Params",
			Size = (uint64)VolumetricFogParams.Size,
			Usage = .Uniform | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&desc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateFullscreenQuad()
	{
		float[12] vertices = .(
			-1.0f, -1.0f, 0.0f, 0.0f,
			 3.0f, -1.0f, 2.0f, 0.0f,
			-1.0f,  3.0f, 0.0f, 2.0f
		);

		BufferDescriptor desc = .()
		{
			Label = "Fullscreen Triangle",
			Size = sizeof(decltype(vertices)),
			Usage = .Vertex | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&desc))
		{
		case .Ok(let buf):
			mFullscreenQuadVB = buf;
			Renderer.Device.Queue.WriteBuffer(mFullscreenQuadVB, 0, Span<uint8>((uint8*)&vertices[0], sizeof(decltype(vertices))));
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateComputePipelines()
	{
		// Bind group layout
		BindGroupLayoutEntry[6] entries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .StorageTexture }, // Scattering volume (write)
			.() { Binding = 1, Visibility = .Compute, Type = .StorageTexture }, // Integrated volume (write)
			.() { Binding = 2, Visibility = .Compute, Type = .SampledTexture }, // History volume (read)
			.() { Binding = 3, Visibility = .Compute, Type = .SampledTexture }, // Depth buffer (read)
			.() { Binding = 4, Visibility = .Compute, Type = .Sampler },        // Sampler
			.() { Binding = 5, Visibility = .Compute, Type = .UniformBuffer }   // Params
		);

		BindGroupLayoutDescriptor layoutDesc = .()
		{
			Label = "VolumetricFog Compute BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mComputeBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layouts
		IPipelineLayout computePipelineLayout = null;
		{
			IBindGroupLayout[1] layouts = .(mComputeBindGroupLayout);
			PipelineLayoutDescriptor computePlDesc = .(layouts);
			switch (Renderer.Device.CreatePipelineLayout(&computePlDesc))
			{
			case .Ok(let layout): computePipelineLayout = layout;
			case .Err: return .Err;
			}
		}

		// Create compute pipelines with shaders
		if (Renderer.ShaderSystem != null)
		{
			// Inject light pipeline
			let injectResult = Renderer.ShaderSystem.GetShader("volumetric_inject", .Compute);
			if (injectResult case .Ok(let shader))
			{
				ComputePipelineDescriptor desc = .(computePipelineLayout, shader.Module);
				desc.Label = "Volumetric Inject Pipeline";

				switch (Renderer.Device.CreateComputePipeline(&desc))
				{
				case .Ok(let pipeline): mInjectLightPipeline = pipeline;
				case .Err: // Non-fatal
				}
			}

			// Scatter pipeline
			let scatterResult = Renderer.ShaderSystem.GetShader("volumetric_scatter", .Compute);
			if (scatterResult case .Ok(let scatterShader))
			{
				ComputePipelineDescriptor desc = .(computePipelineLayout, scatterShader.Module);
				desc.Label = "Volumetric Scatter Pipeline";

				switch (Renderer.Device.CreateComputePipeline(&desc))
				{
				case .Ok(let pipeline): mScatterPipeline = pipeline;
				case .Err: // Non-fatal
				}
			}

			// Integration is done inline with scatter, so use the same pipeline
			mIntegratePipeline = mScatterPipeline;

			// Apply bind group layout
			BindGroupLayoutEntry[4] applyEntries = .(
				.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture }, // Scene color
				.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture }, // Depth
				.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture }, // Integrated volume
				.() { Binding = 3, Visibility = .Fragment, Type = .Sampler }
			);

			BindGroupLayoutDescriptor applyLayoutDesc = .()
			{
				Label = "VolumetricFog Apply BindGroup Layout",
				Entries = applyEntries
			};

			switch (Renderer.Device.CreateBindGroupLayout(&applyLayoutDesc))
			{
			case .Ok(let layout): mApplyBindGroupLayout = layout;
			case .Err: return .Err;
			}

			// Create apply pipeline layout
			IBindGroupLayout[1] applyLayouts = .(mApplyBindGroupLayout);
			PipelineLayoutDescriptor applyPLDesc = .(applyLayouts);
			IPipelineLayout applyPipelineLayout = null;
			switch (Renderer.Device.CreatePipelineLayout(&applyPLDesc))
			{
			case .Ok(let layout): applyPipelineLayout = layout;
			case .Err: return .Err;
			}

			// Apply render pipeline uses the fragment shader from volumetric_apply.frag.hlsl
			// which has inline vertex shader with VSMain entry point
			let applyFragResult = Renderer.ShaderSystem.GetShader("volumetric_apply", .Fragment);
			if (applyFragResult case .Ok(let fragShader))
			{
				// Color targets
				ColorTargetState[1] colorTargets = .(
					.(.RGBA16Float)
				);

				// For volumetric apply, the vertex shader generates fullscreen triangle
				// We need to provide a dummy vertex shader or use the same file with different entry point
				RenderPipelineDescriptor applyDesc = .()
				{
					Label = "Volumetric Apply Pipeline",
					Layout = applyPipelineLayout,
					Vertex = .()
					{
						Shader = .(fragShader.Module, "VSMain"), // The file has both VSMain and PSMain
						Buffers = default // No vertex buffers - SV_VertexID
					},
					Fragment = .()
					{
						Shader = .(fragShader.Module, "PSMain"),
						Targets = colorTargets
					},
					Primitive = .()
					{
						Topology = .TriangleList,
						FrontFace = .CCW,
						CullMode = .None
					},
					DepthStencil = null, // No depth testing for fullscreen pass
					Multisample = .()
					{
						Count = 1,
						Mask = uint32.MaxValue
					}
				};

				switch (Renderer.Device.CreateRenderPipeline(&applyDesc))
				{
				case .Ok(let pipeline): mApplyPipeline = pipeline;
				case .Err: // Non-fatal
				}
			}
		}

		return .Ok;
	}

	private void UpdateParams(RenderView view)
	{
		// Update froxel dimensions based on view
		mParams.FroxelsX = Math.Max(1, view.Width / 8);
		mParams.FroxelsY = Math.Max(1, view.Height / 8);
		mParams.FroxelsZ = 64;

		Renderer.Device.Queue.WriteBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&mParams, VolumetricFogParams.Size)
		);
	}

	private void ExecuteInjectPass(IComputePassEncoder encoder, RenderView view, RenderWorld world)
	{
		if (mInjectLightPipeline == null)
			return;

		encoder.SetPipeline(mInjectLightPipeline);
		if (mComputeBindGroup != null)
			encoder.SetBindGroup(0, mComputeBindGroup, default);

		// Dispatch for each froxel
		let dispatchX = (mParams.FroxelsX + 7) / 8;
		let dispatchY = (mParams.FroxelsY + 7) / 8;
		let dispatchZ = (mParams.FroxelsZ + 7) / 8;
		encoder.Dispatch(dispatchX, dispatchY, dispatchZ);

		Renderer.Stats.ComputeDispatches++;
	}

	private void ExecuteScatterPass(IComputePassEncoder encoder)
	{
		if (mScatterPipeline == null)
			return;

		encoder.SetPipeline(mScatterPipeline);
		if (mComputeBindGroup != null)
			encoder.SetBindGroup(0, mComputeBindGroup, default);

		// Scatter light through volume
		let dispatchX = (mParams.FroxelsX + 7) / 8;
		let dispatchY = (mParams.FroxelsY + 7) / 8;
		let dispatchZ = (mParams.FroxelsZ + 7) / 8;
		encoder.Dispatch(dispatchX, dispatchY, dispatchZ);

		Renderer.Stats.ComputeDispatches++;
	}

	private void ExecuteIntegratePass(IComputePassEncoder encoder)
	{
		if (mIntegratePipeline == null)
			return;

		encoder.SetPipeline(mIntegratePipeline);
		if (mComputeBindGroup != null)
			encoder.SetBindGroup(0, mComputeBindGroup, default);

		// Integrate along view rays
		let dispatchX = (mParams.FroxelsX + 7) / 8;
		let dispatchY = (mParams.FroxelsY + 7) / 8;
		encoder.Dispatch(dispatchX, dispatchY, 1);

		Renderer.Stats.ComputeDispatches++;
	}

	private void ExecuteApplyPass(IRenderPassEncoder encoder, RenderView view)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		if (mApplyPipeline != null)
			encoder.SetPipeline(mApplyPipeline);

		if (mApplyBindGroup != null)
			encoder.SetBindGroup(0, mApplyBindGroup, default);

		// Draw fullscreen
		if (mFullscreenQuadVB != null)
		{
			encoder.SetVertexBuffer(0, mFullscreenQuadVB, 0);
			encoder.Draw(3, 1, 0, 0);
			Renderer.Stats.DrawCalls++;
		}
	}
}
