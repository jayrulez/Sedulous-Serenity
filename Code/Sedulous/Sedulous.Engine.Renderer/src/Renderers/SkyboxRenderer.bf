namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Renders a skybox using a cubemap texture.
/// Owns the cubemap resources, pipeline, and handles rendering.
class SkyboxRenderer
{
	private const int32 MAX_FRAMES = 2;

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;

	// Cubemap resources
	private ITexture mCubemap;
	private ITextureView mCubemapView;
	private ISampler mSampler;
	private bool mOwnsCubemap = false;

	// Pipeline resources
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IRenderPipeline mPipeline ~ delete _;
	private IBindGroup[MAX_FRAMES] mBindGroups ~ { for (var bg in _) delete bg; };

	// Per-frame camera buffers (references, not owned)
	private IBuffer[MAX_FRAMES] mCameraBuffers;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mInitialized = false;

	public ITextureView CubemapView => mCubemapView;
	public ISampler Sampler => mSampler;

	public this(IDevice device)
	{
		mDevice = device;
		CreateSampler();
	}

	public ~this()
	{
		if (mSampler != null) delete mSampler;
		if (mOwnsCubemap)
		{
			if (mCubemapView != null) delete mCubemapView;
			if (mCubemap != null) delete mCubemap;
		}
	}

	/// Initializes the skybox renderer with pipeline resources.
	/// Must be called after creating the cubemap (CreateGradientSky, etc.).
	public Result<void> Initialize(ShaderLibrary shaderLibrary,
		IBuffer[MAX_FRAMES] cameraBuffers, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		if (mDevice == null || !IsValid)
			return .Err;

		mShaderLibrary = shaderLibrary;
		mCameraBuffers = cameraBuffers;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		if (CreatePipeline() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	private Result<void> CreatePipeline()
	{
		// Load skybox shaders
		let vertResult = mShaderLibrary.GetShader("skybox", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = mShaderLibrary.GetShader("skybox", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// Bind group layout: b0=camera, t0=cubemap, s0=sampler
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .TextureCube),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mPipelineLayout = pipelineLayout;

		// Create per-frame bind groups
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			BindGroupEntry[3] entries = .(
				BindGroupEntry.Buffer(0, mCameraBuffers[i]),
				BindGroupEntry.Texture(0, mCubemapView),
				BindGroupEntry.Sampler(0, mSampler)
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mBindGroups[i] = group;
		}

		// No vertex buffers - uses fullscreen triangle with SV_VertexID
		ColorTargetState[1] colorTargets = .(.(mColorFormat));

		// Depth test enabled but no write - skybox is always at far plane
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .LessEqual;
		depthState.Format = mDepthFormat;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = .()  // No vertex buffers
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
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (mDevice.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mPipeline = pipeline;

		return .Ok;
	}

	/// Renders the skybox.
	/// Should be called first in the render pass (before geometry).
	public void Render(IRenderPassEncoder renderPass, int32 frameIndex)
	{
		if (!mInitialized || mPipeline == null || !IsValid)
			return;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroups[frameIndex]);
		renderPass.Draw(3, 1, 0, 0);  // Fullscreen triangle
	}

	private void CreateSampler()
	{
		SamplerDescriptor samplerDesc = .();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		samplerDesc.AddressModeW = .ClampToEdge;

		if (mDevice.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mSampler = sampler;
	}

	/// Sets an external cubemap texture (does not take ownership).
	public void SetCubemap(ITextureView cubemapView)
	{
		if (mOwnsCubemap)
		{
			if (mCubemapView != null) delete mCubemapView;
			if (mCubemap != null) delete mCubemap;
			mOwnsCubemap = false;
		}

		mCubemapView = cubemapView;
		mCubemap = null;
	}

	/// Creates a solid color cubemap (useful for testing or procedural skies).
	public bool CreateSolidColorCubemap(Color color)
	{
		// Clean up existing owned cubemap
		if (mOwnsCubemap)
		{
			if (mCubemapView != null) delete mCubemapView;
			if (mCubemap != null) delete mCubemap;
		}

		// Create a 1x1 cubemap with solid color using the Cubemap helper
		TextureDescriptor texDesc = .Cubemap(1, .RGBA8Unorm, .Sampled | .CopyDst);

		if (mDevice.CreateTexture(&texDesc) not case .Ok(let texture))
			return false;

		mCubemap = texture;
		mOwnsCubemap = true;

		// Upload color data to each face separately
		uint8[4] faceData = .(color.R, color.G, color.B, color.A);

		TextureDataLayout layout = .()
		{
			Offset = 0,
			BytesPerRow = 4,
			RowsPerImage = 1
		};

		Extent3D size = .(1, 1, 1);
		Span<uint8> data = .(&faceData, 4);

		// Upload each face separately
		for (uint32 face = 0; face < 6; face++)
		{
			mDevice.Queue.WriteTexture(mCubemap, data, &layout, &size, 0, face);
		}

		// Create cube view
		TextureViewDescriptor viewDesc = .();
		viewDesc.Format = .RGBA8Unorm;
		viewDesc.Dimension = .TextureCube;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = 1;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = 6;

		if (mDevice.CreateTextureView(mCubemap, &viewDesc) case .Ok(let view))
			mCubemapView = view;
		else
			return false;

		return true;
	}

	/// Creates a procedural gradient sky cubemap with separate ground color.
	/// topColor: Color at zenith (straight up)
	/// horizonColor: Color at the horizon
	/// groundColor: Color when looking down (optional, defaults to darker horizon)
	public bool CreateGradientSky(Color topColor, Color horizonColor, int32 resolution = 64)
	{
		// Use a darker version of horizon for ground by default
		Color groundColor = Color(
			(uint8)(horizonColor.R / 3),
			(uint8)(horizonColor.G / 3),
			(uint8)(horizonColor.B / 3),
			255
		);
		return CreateGradientSkyWithGround(topColor, horizonColor, groundColor, resolution);
	}

	/// Creates a procedural gradient sky cubemap with explicit ground color.
	/// topColor: Color at zenith (straight up)
	/// horizonColor: Color at the horizon
	/// groundColor: Color when looking down
	public bool CreateGradientSkyWithGround(Color topColor, Color horizonColor, Color groundColor, int32 resolution = 64)
	{
		if (mOwnsCubemap)
		{
			if (mCubemapView != null) delete mCubemapView;
			if (mCubemap != null) delete mCubemap;
		}

		// Create cubemap texture using the Cubemap helper
		TextureDescriptor texDesc = .Cubemap((uint32)resolution, .RGBA8Unorm, .Sampled | .CopyDst);

		if (mDevice.CreateTexture(&texDesc) not case .Ok(let texture))
			return false;

		mCubemap = texture;
		mOwnsCubemap = true;

		// Generate gradient data for each face and upload separately
		int32 faceSize = resolution * resolution * 4;
		uint8[] faceData = new uint8[faceSize];
		defer delete faceData;

		TextureDataLayout layout = .()
		{
			Offset = 0,
			BytesPerRow = (uint32)(resolution * 4),
			RowsPerImage = (uint32)resolution
		};

		Extent3D size = .((uint32)resolution, (uint32)resolution, 1);

		// Cubemap face order: +X, -X, +Y, -Y, +Z, -Z
		for (int32 face = 0; face < 6; face++)
		{
			// Generate gradient for this face
			for (int32 y = 0; y < resolution; y++)
			{
				Color c;

				if (face == 2) // +Y (top/zenith)
				{
					c = topColor;
				}
				else if (face == 3) // -Y (bottom/ground)
				{
					c = groundColor;
				}
				else
				{
					// Side faces: gradient from ground -> horizon -> top
					// y=0 is top of texture, y=resolution-1 is bottom
					float t = (float)y / (float)(resolution - 1);

					if (t < 0.5f)
					{
						// Upper half: top to horizon
						float u = t * 2.0f;  // 0 to 1 for upper half
						c = topColor.Interpolate(horizonColor, u);
					}
					else
					{
						// Lower half: horizon to ground
						float u = (t - 0.5f) * 2.0f;  // 0 to 1 for lower half
						c = horizonColor.Interpolate(groundColor, u);
					}
				}

				for (int32 x = 0; x < resolution; x++)
				{
					int32 idx = (y * resolution + x) * 4;
					faceData[idx + 0] = c.R;
					faceData[idx + 1] = c.G;
					faceData[idx + 2] = c.B;
					faceData[idx + 3] = c.A;
				}
			}

			// Upload this face
			Span<uint8> data = .(faceData.Ptr, faceSize);
			mDevice.Queue.WriteTexture(mCubemap, data, &layout, &size, 0, (uint32)face);
		}

		// Create view
		TextureViewDescriptor viewDesc = .();
		viewDesc.Format = .RGBA8Unorm;
		viewDesc.Dimension = .TextureCube;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = 1;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = 6;

		if (mDevice.CreateTextureView(mCubemap, &viewDesc) case .Ok(let view))
			mCubemapView = view;
		else
			return false;

		return true;
	}

	/// Returns true if the skybox has a valid cubemap.
	public bool IsValid => mCubemapView != null;

	/// Returns true if the skybox renderer is fully initialized with pipeline.
	public bool IsInitialized => mInitialized && mPipeline != null;
}
