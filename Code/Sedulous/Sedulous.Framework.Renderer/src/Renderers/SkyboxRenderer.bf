namespace Sedulous.Framework.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Renders a skybox using a cubemap texture.
class SkyboxRenderer
{
	private IDevice mDevice;
	private ITexture mCubemap;
	private ITextureView mCubemapView;
	private ISampler mSampler;
	private bool mOwnsCubemap = false;

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
}
