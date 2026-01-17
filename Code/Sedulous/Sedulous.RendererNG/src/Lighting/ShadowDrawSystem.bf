namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Configuration for shadow rendering.
struct ShadowConfig
{
	public uint32 CascadeCount = 4;
	public uint32 CascadeResolution = 2048;
	public uint32 AtlasSize = 4096;
	public uint32 MinLocalShadowSize = 256;
	public uint32 MaxLocalShadowSize = 1024;
	public float MaxShadowDistance = 200.0f;

	public static Self Default() => .();
}

/// Statistics for shadow rendering.
struct ShadowStats
{
	public uint32 CascadeDraws;
	public uint32 LocalShadowDraws;
	public uint32 TotalShadowCasters;
	public float CascadeUpdateTime;
	public float LocalShadowUpdateTime;
}

/// Shadow caster callback delegate.
delegate void ShadowCasterCallback(Matrix viewProjection, BoundingBox frustumBounds);

/// Manages shadow map rendering for the scene.
class ShadowDrawSystem : IDisposable
{
	private IDevice mDevice;
	private ShadowConfig mConfig;

	// Shadow systems
	private CascadedShadowMaps mCascadeShadows ~ delete _;
	private ShadowAtlas mShadowAtlas ~ delete _;

	// Sampler for shadow sampling
	private ISampler mShadowSampler ~ delete _;

	// Current frame data
	private Matrix mCameraView;
	private Matrix mCameraProj;
	private Vector3 mSunDirection;
	private float mNearPlane;
	private float mFarPlane;

	// Statistics
	public ShadowStats Stats { get; private set; }

	/// Creates shadow draw system with given configuration.
	public this(ShadowConfig config = .())
	{
		mConfig = config;
	}

	/// Initializes shadow resources.
	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create cascaded shadow maps
		mCascadeShadows = new CascadedShadowMaps(mConfig.CascadeCount, mConfig.CascadeResolution);
		if (mCascadeShadows.Initialize(device) case .Err)
			return .Err;

		// Create shadow atlas
		mShadowAtlas = new ShadowAtlas(mConfig.AtlasSize, mConfig.MinLocalShadowSize, mConfig.MaxLocalShadowSize);
		if (mShadowAtlas.Initialize(device) case .Err)
			return .Err;

		// Create shadow sampler (comparison sampler for shadow PCF)
		var samplerDesc = SamplerDescriptor();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Nearest;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		samplerDesc.AddressModeW = .ClampToEdge;
		samplerDesc.Compare = .LessEqual;
		samplerDesc.Label = "ShadowSampler";

		switch (device.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler):
			mShadowSampler = sampler;
		case .Err:
			return .Err;
		}

		return .Ok;
	}

	/// Sets camera parameters for shadow calculation.
	public void SetCamera(Matrix view, Matrix projection, float nearPlane, float farPlane)
	{
		mCameraView = view;
		mCameraProj = projection;
		mNearPlane = nearPlane;
		mFarPlane = Math.Min(farPlane, mConfig.MaxShadowDistance);
	}

	/// Sets sun direction for cascaded shadows.
	public void SetSunDirection(Vector3 direction)
	{
		mSunDirection = Vector3.Normalize(direction);
	}

	/// Begins shadow pass for a new frame.
	public void BeginFrame()
	{
		mShadowAtlas.BeginFrame();
		Stats = .();
	}

	/// Updates cascaded shadow maps.
	public void UpdateCascades()
	{
		mCascadeShadows.Update(mCameraView, mCameraProj, mNearPlane, mFarPlane, mSunDirection);
	}

	/// Allocates shadow map region for a local light.
	/// Returns shadow index to store in LightData, or -1 if no shadow.
	public uint32 AllocateLocalShadow(uint32 lightIndex, float lightRange)
	{
		// Compute shadow map size based on light importance/range
		uint32 size = ComputeLocalShadowSize(lightRange);
		return mShadowAtlas.AllocateRegion(lightIndex, size);
	}

	/// Sets view-projection for a local shadow.
	public void SetLocalShadowMatrix(uint32 shadowIndex, Matrix viewProjection, float nearPlane, float farPlane)
	{
		mShadowAtlas.SetShadowData(shadowIndex, viewProjection, nearPlane, farPlane);
	}

	/// Uploads all shadow data to GPU.
	public void Upload()
	{
		mShadowAtlas.Upload();
	}

	/// Gets view-projection for a cascade.
	public Matrix GetCascadeViewProjection(uint32 cascade)
	{
		return mCascadeShadows.GetCascadeViewProjection(cascade);
	}

	/// Gets cascade split distance.
	public float GetCascadeSplit(uint32 index)
	{
		return mCascadeShadows.GetSplitDistance(index);
	}

	/// Gets cascade view for rendering (depth target).
	public ITextureView GetCascadeDepthView(uint32 cascade)
	{
		return mCascadeShadows.GetCascadeView(cascade);
	}

	/// Gets atlas regions for rendering local shadows.
	public Span<ShadowAtlasRegion> GetLocalShadowRegions()
	{
		return mShadowAtlas.Regions;
	}

	/// Compute local shadow size based on light range.
	private uint32 ComputeLocalShadowSize(float range)
	{
		// Larger lights get higher resolution shadows
		if (range > 50.0f)
			return mConfig.MaxLocalShadowSize;
		else if (range > 20.0f)
			return 512;
		else
			return mConfig.MinLocalShadowSize;
	}

	/// Creates a spot light view-projection matrix.
	public static Matrix CreateSpotLightViewProjection(Vector3 position, Vector3 direction, float range, float outerAngle)
	{
		Vector3 up = Math.Abs(direction.Y) > 0.99f ? Vector3.UnitX : Vector3.UnitY;
		Matrix view = Matrix.CreateLookAt(position, position + direction, up);
		Matrix proj = Matrix.CreatePerspectiveFieldOfView(outerAngle * 2, 1.0f, 0.1f, range);
		return view * proj;
	}

	/// Creates point light view-projection matrices (6 faces for cubemap).
	public static void CreatePointLightViewProjections(Vector3 position, float range, ref Matrix[6] outMatrices)
	{
		// Face directions and up vectors for cubemap
		Vector3[6] directions = .(
			.( 1, 0, 0), // +X
			.(-1, 0, 0), // -X
			.( 0, 1, 0), // +Y
			.( 0,-1, 0), // -Y
			.( 0, 0, 1), // +Z
			.( 0, 0,-1)  // -Z
		);

		Vector3[6] ups = .(
			.(0, 1, 0), // +X
			.(0, 1, 0), // -X
			.(0, 0,-1), // +Y
			.(0, 0, 1), // -Y
			.(0, 1, 0), // +Z
			.(0, 1, 0)  // -Z
		);

		Matrix proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 2, 1.0f, 0.1f, range);

		for (int i = 0; i < 6; i++)
		{
			Matrix view = Matrix.CreateLookAt(position, position + directions[i], ups[i]);
			outMatrices[i] = view * proj;
		}
	}

	// Accessors
	public CascadedShadowMaps CascadeShadows => mCascadeShadows;
	public ShadowAtlas ShadowAtlas => mShadowAtlas;
	public ISampler ShadowSampler => mShadowSampler;
	public uint32 CascadeCount => mConfig.CascadeCount;
	public ShadowConfig Config => mConfig;

	/// Gets cascade shadow map array view for shader sampling.
	public ITextureView CascadeArrayView => mCascadeShadows.ArrayView;

	/// Gets cascade uniform buffer.
	public IBuffer CascadeBuffer => mCascadeShadows.CascadeBuffer;

	/// Gets shadow atlas view for shader sampling.
	public ITextureView AtlasView => mShadowAtlas.AtlasView;

	/// Gets shadow atlas texture (for rendering).
	public ITexture AtlasTexture => mShadowAtlas.AtlasTexture;

	/// Gets local shadow data buffer.
	public IBuffer LocalShadowBuffer => mShadowAtlas.ShadowDataBuffer;

	/// Gets statistics.
	public void GetStats(String outStats)
	{
		outStats.AppendF("Shadow Draw System:\n");

		let cascadeStats = scope String();
		mCascadeShadows.GetStats(cascadeStats);
		outStats.Append(cascadeStats);

		let atlasStats = scope String();
		mShadowAtlas.GetStats(atlasStats);
		outStats.Append(atlasStats);
	}

	public void Dispose()
	{
		// Resources cleaned up by destructor
	}

	// ========================================================================
	// Render Graph Integration
	// ========================================================================

	/// Adds cascade shadow map rendering passes to the render graph.
	/// Creates one pass per cascade that renders shadow casters.
	/// Returns the cascade depth handles for later passes to sample.
	public void AddCascadePasses(
		RenderGraph graph,
		MeshDrawSystem meshDrawSystem,
		IPipelineLayout shadowPipelineLayout,
		RGResourceHandle[] outCascadeHandles)
	{
		for (uint32 i = 0; i < mConfig.CascadeCount && i < outCascadeHandles.Count; i++)
		{
			// Create transient depth texture for this cascade
			let cascadeDepth = graph.CreateTexture(
				scope $"CascadeDepth{i}",
				TextureResourceDesc.DepthStencil(mConfig.CascadeResolution, mConfig.CascadeResolution, .Depth32Float));

			outCascadeHandles[i] = cascadeDepth;

			ShadowPassData passData;
			passData.DrawSystem = this;
			passData.MeshDrawSystem = meshDrawSystem;
			passData.PipelineLayout = shadowPipelineLayout;
			passData.CascadeIndex = i;

			graph.AddGraphicsPass(scope $"ShadowCascade{i}")
				.SetDepthAttachment(cascadeDepth, 1.0f, .Clear, .Store)
				.SetExecute(new (encoder) => {
					// Shadow casters render to depth-only
					passData.MeshDrawSystem.RenderShadowBatches(encoder, passData.PipelineLayout);
				});
		}
	}

	/// Adds a single cascade shadow map pass (for more control).
	public PassBuilder AddCascadePass(
		RenderGraph graph,
		uint32 cascadeIndex,
		RGResourceHandle cascadeDepth,
		MeshDrawSystem meshDrawSystem,
		IPipelineLayout shadowPipelineLayout)
	{
		ShadowPassData passData;
		passData.DrawSystem = this;
		passData.MeshDrawSystem = meshDrawSystem;
		passData.PipelineLayout = shadowPipelineLayout;
		passData.CascadeIndex = cascadeIndex;

		return graph.AddGraphicsPass(scope $"ShadowCascade{cascadeIndex}")
			.SetDepthAttachment(cascadeDepth, 1.0f, .Clear, .Store)
			.SetExecute(new (encoder) => {
				passData.MeshDrawSystem.RenderShadowBatches(encoder, passData.PipelineLayout);
			});
	}

	/// Adds local shadow rendering passes to the render graph.
	/// Creates passes for each allocated shadow region.
	public void AddLocalShadowPasses(
		RenderGraph graph,
		RGResourceHandle atlasDepth,
		MeshDrawSystem meshDrawSystem,
		IPipelineLayout shadowPipelineLayout)
	{
		let regions = GetLocalShadowRegions();
		if (regions.Length == 0)
			return;

		for (int i = 0; i < regions.Length; i++)
		{
			let region = regions[i];
			if (region.LightIndex == ShadowAtlasRegion.Invalid)
				continue;

			ShadowPassData passData;
			passData.DrawSystem = this;
			passData.MeshDrawSystem = meshDrawSystem;
			passData.PipelineLayout = shadowPipelineLayout;
			passData.RegionIndex = (uint32)i;

			// Each local shadow renders to a region of the atlas
			// The viewport/scissor is set in the execute callback
			graph.AddGraphicsPass(scope $"LocalShadow{i}")
				.SetDepthAttachment(atlasDepth, .Load, .Store)  // Load to preserve other regions
				.SetExecute(new (encoder) => {
					// Set viewport for this region
					// todo: set the viewport here
					passData.MeshDrawSystem.RenderShadowBatches(encoder, passData.PipelineLayout);
				});
		}
	}

	/// Creates a shadow atlas resource in the render graph.
	public RGResourceHandle CreateAtlasResource(RenderGraph graph)
	{
		return graph.CreateTexture(
			"ShadowAtlas",
			TextureResourceDesc.DepthStencil(mConfig.AtlasSize, mConfig.AtlasSize, .Depth32Float));
	}
}
