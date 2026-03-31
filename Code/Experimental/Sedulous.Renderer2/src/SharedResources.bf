using System;
using Sedulous.RHI;
using Sedulous.Profiler;

namespace Sedulous.Renderer;

/// Shared default textures and samplers used by all render features.
/// Created once during RenderSystem init, uploaded in a single batched transfer.
public class SharedResources
{
	// --- Default textures ---
	public ITexture White1x1 ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView White1x1View ~ { var v = _; mDevice?.DestroyTextureView(ref v); };

	public ITexture Black1x1 ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView Black1x1View ~ { var v = _; mDevice?.DestroyTextureView(ref v); };

	public ITexture Normal1x1 ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView Normal1x1View ~ { var v = _; mDevice?.DestroyTextureView(ref v); };

	public ITexture DummyShadowMap ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView DummyShadowMapView ~ { var v = _; mDevice?.DestroyTextureView(ref v); };

	public ITexture FallbackCubemap ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView FallbackCubemapView ~ { var v = _; mDevice?.DestroyTextureView(ref v); };

	public ITexture FallbackCubemapArray ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView FallbackCubemapArrayView ~ { var v = _; mDevice?.DestroyTextureView(ref v); };

	public ITexture BRDFLUT ~ { var t = _; mDevice?.DestroyTexture(ref t); };
	public ITextureView BRDFLUTView ~ { var v = _; mDevice?.DestroyTextureView(ref v); };

	// --- Fallback buffers ---
	/// Small zeroed uniform buffer used as fallback for shadow/probe uniform slots when those systems aren't active
	public IBuffer DummyUniformBuffer ~ { var b = _; mDevice?.DestroyBuffer(ref b); };

	// --- Shared samplers ---
	public ISampler LinearClamp ~ { var s = _; mDevice?.DestroySampler(ref s); };
	public ISampler LinearWrap ~ { var s = _; mDevice?.DestroySampler(ref s); };
	public ISampler PointClamp ~ { var s = _; mDevice?.DestroySampler(ref s); };
	public ISampler ShadowSampler ~ { var s = _; mDevice?.DestroySampler(ref s); };

	private IDevice mDevice;

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Initialize all shared resources. GPU uploads go through the provided transfer batch.
	public Result<void> Initialize(ITransferBatch transferBatch)
	{
		using (SProfiler.Begin("Renderer.SharedResources"))
		{
			Try!(CreateDefaultTextures(transferBatch));
			Try!(CreateSamplers());
		}
		return .Ok;
	}

	private Result<void> CreateDefaultTextures(ITransferBatch transferBatch)
	{
		// 1x1 white
		{
			uint8[4] data = .(255, 255, 255, 255);
			Try!(CreateSmallTexture("White1x1", .RGBA8Unorm, &data, 4, transferBatch,
				out White1x1, out White1x1View));
		}

		// 1x1 black
		{
			uint8[4] data = .(0, 0, 0, 255);
			Try!(CreateSmallTexture("Black1x1", .RGBA8Unorm, &data, 4, transferBatch,
				out Black1x1, out Black1x1View));
		}

		// 1x1 flat normal — (128, 128, 255, 255) = (0, 0, 1) in tangent space
		{
			uint8[4] data = .(128, 128, 255, 255);
			Try!(CreateSmallTexture("Normal1x1", .RGBA8Unorm, &data, 4, transferBatch,
				out Normal1x1, out Normal1x1View));
		}

		// Dummy shadow map (4x4 depth array, 4 layers — matches Texture2DArray in shader)
		{
			if (mDevice.CreateTexture(TextureDesc()
			{
				Format = .Depth32Float,
				Width = 4, Height = 4,
				ArrayLayerCount = 4,
				Usage = .DepthStencil | .Sampled,
				Label = "DummyShadowMap"
			}) case .Ok(let tex))
			{
				DummyShadowMap = tex;
				if (mDevice.CreateTextureView(tex, TextureViewDesc()
				{
					Format = .Depth32Float,
					Dimension = .Texture2DArray,
					ArrayLayerCount = 4,
					Aspect = .DepthOnly,
					Label = "DummyShadowMapView"
				}) case .Ok(let view))
					DummyShadowMapView = view;
				else
					return .Err;

				// Clear to depth 1.0 (fully lit, no shadow) via render passes
				ClearDummyShadowMap(tex);
			}
			else
				return .Err;
		}

		// Fallback cubemap (1x1 per face, neutral gray)
		{
			if (mDevice.CreateTexture(TextureDesc()
			{
				Format = .RGBA16Float,
				Width = 1, Height = 1,
				ArrayLayerCount = 6,
				Usage = .Sampled | .CopyDst,
				Label = "FallbackCubemap"
			}) case .Ok(let tex))
			{
				FallbackCubemap = tex;
				if (mDevice.CreateTextureView(tex, TextureViewDesc()
				{
					Dimension = .TextureCube,
					ArrayLayerCount = 6
				}) case .Ok(let view))
					FallbackCubemapView = view;
				else
					return .Err;

				// Upload neutral gray to all 6 faces (RGBA16Float: 8 bytes per pixel)
				uint16[4] grayPixel = .(15360, 15360, 15360, 15360); // float16(0.5)
				for (uint32 face = 0; face < 6; face++)
				{
					transferBatch.WriteTexture(tex, Span<uint8>((uint8*)&grayPixel, 8),
						TextureDataLayout() { BytesPerRow = 8, RowsPerImage = 1 },
						Extent3D(1, 1, 1), 0, face);
				}
			}
			else
				return .Err;
		}

		// Fallback cubemap array (1x1 per face, 1 cube = 6 layers, for ProbeCubemaps binding)
		{
			if (mDevice.CreateTexture(TextureDesc()
			{
				Format = .RGBA16Float,
				Width = 1, Height = 1,
				ArrayLayerCount = 6,
				Usage = .Sampled | .CopyDst,
				Label = "FallbackCubemapArray"
			}) case .Ok(let tex))
			{
				FallbackCubemapArray = tex;
				if (mDevice.CreateTextureView(tex, TextureViewDesc()
				{
					Dimension = .TextureCubeArray,
					ArrayLayerCount = 6
				}) case .Ok(let view))
					FallbackCubemapArrayView = view;
				else
					return .Err;

				uint16[4] grayPixel = .(15360, 15360, 15360, 15360);
				for (uint32 face = 0; face < 6; face++)
				{
					transferBatch.WriteTexture(tex, Span<uint8>((uint8*)&grayPixel, 8),
						TextureDataLayout() { BytesPerRow = 8, RowsPerImage = 1 },
						Extent3D(1, 1, 1), 0, face);
				}
			}
			else
				return .Err;
		}

		// BRDF LUT placeholder (1x1 RG16Float — real one loaded in Phase 5)
		{
			uint16[2] data = .(15360, 0); // (0.5, 0.0)
			if (mDevice.CreateTexture(TextureDesc()
			{
				Format = .RG16Float,
				Width = 1, Height = 1,
				Usage = .Sampled | .CopyDst,
				Label = "BRDFLUT_Placeholder"
			}) case .Ok(let tex))
			{
				BRDFLUT = tex;
				if (mDevice.CreateTextureView(tex, TextureViewDesc()) case .Ok(let view))
					BRDFLUTView = view;
				else
					return .Err;

				transferBatch.WriteTexture(tex, Span<uint8>((uint8*)&data, 4),
					TextureDataLayout() { BytesPerRow = 4, RowsPerImage = 1 },
					Extent3D(1, 1, 1));
			}
			else
				return .Err;
		}

		// Dummy uniform buffer — used as fallback for shadow/probe uniform slots
		// Must be large enough for the largest consumer: ProbeUniforms = 1424 bytes
		{
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
		}

		return .Ok;
	}

	private Result<void> CreateSmallTexture(StringView name, TextureFormat format, void* data, int dataSize,
		ITransferBatch transferBatch, out ITexture outTexture, out ITextureView outView)
	{
		outTexture = null;
		outView = null;

		if (mDevice.CreateTexture(TextureDesc()
		{
			Format = format,
			Width = 1, Height = 1,
			Usage = .Sampled | .CopyDst,
			Label = name
		}) case .Ok(let tex))
		{
			outTexture = tex;
			if (mDevice.CreateTextureView(tex, TextureViewDesc()) case .Ok(let view))
				outView = view;
			else
				return .Err;

			transferBatch.WriteTexture(tex, Span<uint8>((uint8*)data, dataSize),
				TextureDataLayout() { BytesPerRow = (uint32)dataSize, RowsPerImage = 1 },
				Extent3D(1, 1, 1));
			return .Ok;
		}

		return .Err;
	}

	private void ClearDummyShadowMap(ITexture shadowTex)
	{
		var cmdPool = mDevice.CreateCommandPool(.Graphics).Value;
		if (cmdPool == null)
			return;
		var encoder = cmdPool.CreateEncoder().Value;
		if (encoder == null)
		{
			mDevice.DestroyCommandPool(ref cmdPool);
			return;
		}

		// Create temporary per-layer views for clearing
		ITextureView[4] layerViews = default;
		for (uint32 layer = 0; layer < 4; layer++)
		{
			if (mDevice.CreateTextureView(shadowTex, TextureViewDesc()
			{
				Format = .Depth32Float,
				Dimension = .Texture2D,
				BaseArrayLayer = layer,
				ArrayLayerCount = 1,
				Aspect = .DepthOnly,
				Label = "Dummy Shadow Clear View"
			}) case .Ok(let view))
				layerViews[layer] = view;
		}

		// Clear each layer to depth 1.0 (fully lit)
		for (uint32 layer = 0; layer < 4; layer++)
		{
			if (layerViews[layer] == null)
				continue;

			RenderPassDesc rpDesc = .()
			{
				Label = "Clear Dummy Shadow",
				DepthStencilAttachment = .()
				{
					View = layerViews[layer],
					DepthLoadOp = .Clear,
					DepthStoreOp = .Store,
					DepthClearValue = 1.0f
				}
			};

			let pass = encoder.BeginRenderPass(rpDesc);
			if (pass != null)
				pass.End();
		}

		// Transition to shader-readable after all clears
		encoder.TransitionTexture(shadowTex, .DepthStencilWrite, .ShaderRead);

		let cmdBuf = encoder.Finish();
		if (cmdBuf != null)
		{
			mDevice.GetQueue(.Graphics).Submit(cmdBuf);
			mDevice.WaitIdle();
		}

		// Cleanup
		for (uint32 layer = 0; layer < 4; layer++)
			if (layerViews[layer] != null)
				mDevice.DestroyTextureView(ref layerViews[layer]);

		cmdPool.DestroyEncoder(ref encoder);
		cmdPool.Reset();
		mDevice.DestroyCommandPool(ref cmdPool);
	}

	private Result<void> CreateSamplers()
	{
		if (mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear, MagFilter = .Linear, MipmapFilter = .Linear,
			AddressU = .ClampToEdge, AddressV = .ClampToEdge, AddressW = .ClampToEdge,
			Label = "LinearClamp"
		}) case .Ok(let linearClamp))
			LinearClamp = linearClamp;
		else
			return .Err;

		if (mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear, MagFilter = .Linear, MipmapFilter = .Linear,
			Label = "LinearWrap"
		}) case .Ok(let linearWrap))
			LinearWrap = linearWrap;
		else
			return .Err;

		if (mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Nearest, MagFilter = .Nearest, MipmapFilter = .Nearest,
			AddressU = .ClampToEdge, AddressV = .ClampToEdge, AddressW = .ClampToEdge,
			Label = "PointClamp"
		}) case .Ok(let pointClamp))
			PointClamp = pointClamp;
		else
			return .Err;

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
