namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Profiler;

/// Shared default textures and samplers used by all render features.
/// Created once during RenderSystem init. Features reference these
/// instead of creating their own fallback resources.
public class SharedResources
{
	// --- Dummy shadow map ---
	// Dummy shadow map array for when shadows are disabled
	public ITexture DummyShadowMapArray ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView DummyShadowMapArrayView ~ { var v = _; mDevice?.DestroyTextureView(ref v); };

	// --- IBL fallback resources (used when SkyFeature has no IBL maps) ---
	public ITexture FallbackIrradianceCubemap ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView FallbackIrradianceCubemapView ~ { var v = _; mDevice?.DestroyTextureView(ref v); };
	public ITexture FallbackPrefilteredCubemap ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView FallbackPrefilteredCubemapView ~ { var v = _; mDevice?.DestroyTextureView(ref v); };
	public ITexture FallbackBRDFLut ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView FallbackBRDFLutView ~ { var v = _; mDevice?.DestroyTextureView(ref v); };

	// --- IBL sampler ---
	public ISampler IBLSampler ~ { var s = _; mDevice?.DestroySampler(ref s); };

	// --- Dummy uniform buffer (fits largest consumer: ProbeUniforms = 1424 bytes) ---
	public IBuffer DummyUniformBuffer ~ { var b = _; mDevice?.DestroyBuffer(ref b); };

	// --- Shadow comparison sampler ---
	public ISampler ShadowSampler ~ { var s = _; mDevice?.DestroySampler(ref s); };

	private IDevice mDevice;

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Initialize all shared resources.
	/// IBL texture uploads go through the provided transfer batch.
	/// Shadow map clear uses a command pool + WaitIdle (will be improved in Phase 7).
	public Result<void> Initialize(ITransferBatch transferBatch)
	{
		using (SProfiler.Begin("SharedResources"))
		{
			Try!(CreateDummyShadowMap());
			Try!(CreateIBLFallbackResources(transferBatch));
			Try!(CreateDummyUniformBuffer());
			Try!(CreateSamplers());
		}
		return .Ok;
	}

	private Result<void> CreateDummyShadowMap()
	{
		// Create a small 4x4 depth array texture with 4 layers for use when shadows are disabled
		// This satisfies the shader's expectation of Texture2DArray for ShadowMap
		// Using 4x4 instead of 1x1 to avoid sampling artifacts with comparison sampler
		TextureDesc texDesc = .()
		{
			Label = "Dummy Shadow Map Array",
			Dimension = .Texture2D,
			Width = 4,
			Height = 4,
			Depth = 1,
			Format = .Depth32Float,
			MipLevelCount = 1,
			ArrayLayerCount = 4, // Match cascade count
			SampleCount = 1,
			Usage = .DepthStencil | .Sampled
		};

		switch (mDevice.CreateTexture(texDesc))
		{
		case .Ok(let tex): DummyShadowMapArray = tex;
		case .Err: return .Err;
		}

		// Create array view for sampling
		TextureViewDesc viewDesc = .()
		{
			Label = "Dummy Shadow Map Array View",
			Format = .Depth32Float,
			Dimension = .Texture2DArray,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 4,
			Aspect = .DepthOnly
		};

		switch (mDevice.CreateTextureView(DummyShadowMapArray, viewDesc))
		{
		case .Ok(let view): DummyShadowMapArrayView = view;
		case .Err: return .Err;
		}

		// Initialize to max depth (1.0 = fully lit, no shadow) via a clear render pass
		// This transitions the texture out of UNDEFINED layout
		ClearDummyShadowMap();

		return .Ok;
	}

	private void ClearDummyShadowMap()
	{
		if (DummyShadowMapArray == null)
			return;

		// Create temporary views for all layers
		ITextureView[4] layerViews = .(null, null, null, null);
		defer
		{
			for (var view in ref layerViews)
				if (view != null)
					mDevice.DestroyTextureView(ref view);
		}

		for (uint32 layer = 0; layer < 4; layer++)
		{
			TextureViewDesc layerViewDesc = .()
			{
				Label = "Dummy Shadow Layer View",
				Format = .Depth32Float,
				Dimension = .Texture2D,
				BaseMipLevel = 0,
				MipLevelCount = 1,
				BaseArrayLayer = layer,
				ArrayLayerCount = 1,
				Aspect = .DepthOnly
			};

			if (mDevice.CreateTextureView(DummyShadowMapArray, layerViewDesc) case .Ok(let view))
				layerViews[layer] = view;
		}

		// Use a single command encoder to clear all layers and transition
		var cmdPool = mDevice.CreateCommandPool(.Graphics).Value;
		if (cmdPool == null)
			return;
		var encoder = cmdPool.CreateEncoder().Value;
		if (encoder == null)
		{
			mDevice.DestroyCommandPool(ref cmdPool);
			return;
		}

		// Clear each layer with a render pass
		for (uint32 layer = 0; layer < 4; layer++)
		{
			if (layerViews[layer] == null)
				continue;

			RenderPassDesc rpDesc = .()
			{
				Label = "Clear Dummy Shadow Layer",
				DepthStencilAttachment = .()
				{
					View = layerViews[layer],
					DepthLoadOp = .Clear,
					DepthStoreOp = .Store,
					DepthClearValue = 1.0f // Max depth = no shadow
				}
			};

			let pass = encoder.BeginRenderPass(rpDesc);
			if (pass != null)
			{
				pass.End();
				//delete pass;
			}
		}

		// Transition whole texture to ShaderReadOnly after all clears
		encoder.TransitionTexture(DummyShadowMapArray, .DepthStencilWrite, .ShaderRead);

		let cmdBuffer = encoder.Finish();
		if (cmdBuffer != null)
		{
			mDevice.GetQueue(.Graphics).Submit(cmdBuffer);
			// Wait for GPU to finish before we delete the views
			mDevice.WaitIdle();
		}
		cmdPool.DestroyEncoder(ref encoder);
		cmdPool.Reset();
		mDevice.DestroyCommandPool(ref cmdPool);
	}

	private Result<void> CreateIBLFallbackResources(ITransferBatch transferBatch)
	{
		// Create 1x1 fallback irradiance cubemap (white = neutral ambient)
		{
			TextureDesc texDesc = .Cubemap(1, .RGBA16Float, .Sampled | .CopyDst, label: "irradiance cubemap fallback");
			switch (mDevice.CreateTexture(texDesc))
			{
			case .Ok(let tex): FallbackIrradianceCubemap = tex;
			case .Err: return .Err;
			}

			uint16[4] whitePixel = .(0x3C00, 0x3C00, 0x3C00, 0x3C00); // 1.0 in half-float
			TextureDataLayout layout = .() { BytesPerRow = 8, RowsPerImage = 1 };
			Extent3D size = .(1, 1, 1);
			for (uint32 face = 0; face < 6; face++)
				transferBatch.WriteTexture(FallbackIrradianceCubemap, Span<uint8>((uint8*)&whitePixel, 8), layout, size, 0, face);

			TextureViewDesc viewDesc = .()
			{
				Format = .RGBA16Float,
				Dimension = .TextureCube,
				BaseMipLevel = 0,
				MipLevelCount = 1,
				BaseArrayLayer = 0,
				ArrayLayerCount = 6
			};

			switch (mDevice.CreateTextureView(FallbackIrradianceCubemap, viewDesc))
			{
			case .Ok(let view): FallbackIrradianceCubemapView = view;
			case .Err: return .Err;
			}
		}

		// Create 1x1 fallback prefiltered cubemap (white = neutral specular)
		{
			TextureDesc texDesc = .Cubemap(1, .RGBA16Float, .Sampled | .CopyDst, label: "prefiltered cubemap");
			switch (mDevice.CreateTexture(texDesc))
			{
			case .Ok(let tex): FallbackPrefilteredCubemap = tex;
			case .Err: return .Err;
			}

			uint16[4] whitePixel = .(0x3C00, 0x3C00, 0x3C00, 0x3C00);
			TextureDataLayout layout = .() { BytesPerRow = 8, RowsPerImage = 1 };
			Extent3D size = .(1, 1, 1);
			for (uint32 face = 0; face < 6; face++)
				transferBatch.WriteTexture(FallbackPrefilteredCubemap, Span<uint8>((uint8*)&whitePixel, 8), layout, size, 0, face);

			TextureViewDesc viewDesc = .()
			{
				Format = .RGBA16Float,
				Dimension = .TextureCube,
				BaseMipLevel = 0,
				MipLevelCount = 1,
				BaseArrayLayer = 0,
				ArrayLayerCount = 6
			};

			switch (mDevice.CreateTextureView(FallbackPrefilteredCubemap, viewDesc))
			{
			case .Ok(let view): FallbackPrefilteredCubemapView = view;
			case .Err: return .Err;
			}
		}

		// Create 1x1 fallback BRDF LUT (identity: scale=1.0, bias=0.0)
		{
			TextureDesc texDesc = .()
			{
				Label = "Fallback BRDF LUT",
				Width = 1,
				Height = 1,
				Depth = 1,
				Format = .RG16Float,
				MipLevelCount = 1,
				ArrayLayerCount = 1,
				SampleCount = 1,
				Dimension = .Texture2D,
				Usage = .Sampled | .CopyDst
			};

			switch (mDevice.CreateTexture(texDesc))
			{
			case .Ok(let tex): FallbackBRDFLut = tex;
			case .Err: return .Err;
			}

			uint16[2] brdfPixel = .(0x3C00, 0x0000); // (1.0, 0.0) in half-float
			TextureDataLayout layout = .() { BytesPerRow = 4, RowsPerImage = 1 };
			Extent3D size = .(1, 1, 1);
			transferBatch.WriteTexture(FallbackBRDFLut, Span<uint8>((uint8*)&brdfPixel, 4), layout, size);

			TextureViewDesc viewDesc = .()
			{
				Format = .RG16Float,
				Dimension = .Texture2D
			};

			switch (mDevice.CreateTextureView(FallbackBRDFLut, viewDesc))
			{
			case .Ok(let view): FallbackBRDFLutView = view;
			case .Err: return .Err;
			}
		}

		// Create IBL sampler (linear min/mag/mip, clamp to edge)
		{
			SamplerDesc samplerDesc = .();
			samplerDesc.MinFilter = .Linear;
			samplerDesc.MagFilter = .Linear;
			samplerDesc.MipmapFilter = .Linear;
			samplerDesc.AddressU = .ClampToEdge;
			samplerDesc.AddressV = .ClampToEdge;
			samplerDesc.AddressW = .ClampToEdge;

			switch (mDevice.CreateSampler(samplerDesc))
			{
			case .Ok(let sampler): IBLSampler = sampler;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private Result<void> CreateDummyUniformBuffer()
	{
		// Dummy uniform buffer — used as fallback for shadow/probe uniform slots
		// Must be large enough for the largest consumer: ProbeUniforms = 1424 bytes
		if (mDevice.CreateBuffer(BufferDesc()
		{
			Size = 1424,
			Usage = .Uniform,
			Memory = .CpuToGpu,
			Label = "DummyUniformBuffer"
		}) case .Ok(let buf))
			DummyUniformBuffer = buf;
		else
			return .Err;

		return .Ok;
	}

	private Result<void> CreateSamplers()
	{
		// Shadow comparison sampler (for PCF filtering)
		if (mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear, MagFilter = .Linear, MipmapFilter = .Nearest,
			AddressU = .ClampToEdge, AddressV = .ClampToEdge, AddressW = .ClampToEdge,
			Compare = .LessEqual,
			Label = "ShadowSampler"
		}) case .Ok(let shadowSampler))
			ShadowSampler = shadowSampler;
		else
			return .Err;

		return .Ok;
	}
}
