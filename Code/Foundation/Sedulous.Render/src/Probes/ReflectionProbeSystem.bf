namespace Sedulous.Render;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;

/// GPU-side probe uniform data, matching probe_uniforms.hlsli.
[CRepr]
struct ProbeData
{
	public Vector3 Position;
	public float Radius;
	public uint32 LayerIndex;
	public Vector3 _Pad;
	public Vector4[9] IrradianceSH; // SH9 irradiance (xyz = RGB, w = unused)

	public const uint64 Size = 176; // 32 + 9*16 = 176 bytes
}

/// Complete probe uniform buffer matching probe_uniforms.hlsli cbuffer.
[CRepr]
struct ProbeUniforms
{
	public ProbeData[ReflectionProbeSystem.MaxProbes] Probes;
	public uint32 ProbeCount;
	public uint32[3] _Pad;

	public const uint64 Size = (uint64)(ReflectionProbeSystem.MaxProbes * sizeof(ProbeData) + 16);
}

/// Manages reflection probe cubemap array, uniform buffer, and CPU-based baking.
public class ReflectionProbeSystem
{
	public const int32 MaxProbes = 8;
	public const int32 CubemapSize = 128;
	public const uint32 MipLevels = 5;
	public const int32 NumSamples = 128;

	// Cubemap array for all probes
	private ITexture mCubemapArray;
	private ITextureView mCubemapArrayView;

	// Fallback: 1-layer white cubemap array (for when no probes active)
	private ITexture mFallbackCubemapArray;
	private ITextureView mFallbackCubemapArrayView;

	// Probe uniform buffers (per-frame for double-buffering)
	private IBuffer[RenderConfig.FrameBufferCount] mProbeUniformBuffers;

	// Layer allocation pool
	private bool[MaxProbes] mLayerAllocated;

	// Probe generation counter (for bind group invalidation)
	private uint32 mGeneration = 0;

	private IDevice mDevice;

	/// Current generation counter. Incremented when probe data changes.
	public uint32 Generation => mGeneration;

	/// Initializes the probe system: creates textures, buffers, and fallback resources.
	public Result<void> Initialize(IDevice device, ITransferBatch batch = null)
	{
		mDevice = device;

		// Create cubemap array texture (6 faces * MaxProbes layers)
		var texDesc = TextureDesc();
		texDesc.Label = "Probe Cubemap Array";
		texDesc.Dimension = .Texture2D;
		texDesc.Format = .RGBA16Float;
		texDesc.Width = (uint32)CubemapSize;
		texDesc.Height = (uint32)CubemapSize;
		texDesc.Depth = 1;
		texDesc.ArrayLayerCount = (uint32)(6 * MaxProbes);
		texDesc.MipLevelCount = MipLevels;
		texDesc.SampleCount = 1;
		texDesc.Usage = .Sampled | .CopyDst;

		switch (device.CreateTexture(texDesc))
		{
		case .Ok(let tex): mCubemapArray = tex;
		case .Err: return .Err;
		}

		// Create TextureCubeArray view over the full array
		var viewDesc = TextureViewDesc();
		viewDesc.Label = "Probe Cubemap Array View";
		viewDesc.Format = .RGBA16Float;
		viewDesc.Dimension = .TextureCubeArray;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = MipLevels;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = (uint32)(6 * MaxProbes);

		switch (device.CreateTextureView(mCubemapArray, viewDesc))
		{
		case .Ok(let view): mCubemapArrayView = view;
		case .Err: return .Err;
		}

		// Initialize all subresources to black so Vulkan transitions them out of UNDEFINED layout.
		// Without this, unwritten layers cause validation errors when the full array view is bound.
		InitializeAllSubresources(device, batch);

		// Create fallback: 1-cube white cubemap array
		if (CreateFallbackCubemapArray(device, batch) case .Err)
			return .Err;

		// Create per-frame probe uniform buffers
		var emptyUniforms = ProbeUniforms();
		emptyUniforms.ProbeCount = 0;

		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			var bufDesc = BufferDesc();
			bufDesc.Label = "Probe Uniforms";
			bufDesc.Size = ProbeUniforms.Size;
			bufDesc.Usage = .Uniform;
			bufDesc.Memory = .CpuToGpu;

			switch (device.CreateBuffer(bufDesc))
			{
			case .Ok(let buf): mProbeUniformBuffers[i] = buf;
			case .Err: return .Err;
			}

			// Initialize with zero probe count
			if (let ptr = mProbeUniformBuffers[i].Map())
			{
				Internal.MemCpy(ptr, &emptyUniforms, (int)ProbeUniforms.Size);
				mProbeUniformBuffers[i].Unmap();
			}
		}

		return .Ok;
	}

	/// Creates a 1-cube fallback white cubemap array for when no probes are active.
	private Result<void> CreateFallbackCubemapArray(IDevice device, ITransferBatch batch = null)
	{
		var texDesc = TextureDesc();
		texDesc.Label = "Fallback Probe CubeArray";
		texDesc.Dimension = .Texture2D;
		texDesc.Format = .RGBA16Float;
		texDesc.Width = 1;
		texDesc.Height = 1;
		texDesc.Depth = 1;
		texDesc.ArrayLayerCount = 6; // 1 cube
		texDesc.MipLevelCount = 1;
		texDesc.SampleCount = 1;
		texDesc.Usage = .Sampled | .CopyDst;

		switch (device.CreateTexture(texDesc))
		{
		case .Ok(let tex): mFallbackCubemapArray = tex;
		case .Err: return .Err;
		}

		// Upload white pixels to all 6 faces
		uint16[4] whitePixel = .(FloatToHalf(1.0f), FloatToHalf(1.0f), FloatToHalf(1.0f), FloatToHalf(1.0f));
		var layout = TextureDataLayout() { BytesPerRow = 8, RowsPerImage = 1 };
		var writeSize = Extent3D(1, 1, 1);

		for (uint32 face = 0; face < 6; face++)
		{
			if (batch != null)
				batch.WriteTexture(mFallbackCubemapArray, Span<uint8>((uint8*)&whitePixel, 8), layout, writeSize, 0, face);
			else
				TransferHelper.WriteTextureSync(device.GetQueue(.Graphics), device,mFallbackCubemapArray, Span<uint8>((uint8*)&whitePixel, 8), layout, writeSize, 0, face);
		}

		var viewDesc = TextureViewDesc();
		viewDesc.Label = "Fallback Probe CubeArray View";
		viewDesc.Format = .RGBA16Float;
		viewDesc.Dimension = .TextureCubeArray;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = 1;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = 6;

		switch (device.CreateTextureView(mFallbackCubemapArray, viewDesc))
		{
		case .Ok(let view): mFallbackCubemapArrayView = view;
		case .Err: return .Err;
		}

		return .Ok;
	}

	/// Writes black pixels to every subresource (all layers, all mips) of the cubemap array.
	/// This transitions all subresources out of VK_IMAGE_LAYOUT_UNDEFINED.
	private void InitializeAllSubresources(IDevice device, ITransferBatch batch = null)
	{
		if (mCubemapArray == null) return;

		int32 totalLayers = 6 * MaxProbes;

		for (uint32 mip = 0; mip < MipLevels; mip++)
		{
			int32 mipSize = CubemapSize >> (int32)mip;
			int32 dataSize = mipSize * mipSize * 8; // RGBA16Float = 8 bytes/pixel

			// Allocate zeroed buffer for one face at this mip
			uint8[] zeroData = new uint8[dataSize];
			defer delete zeroData;

			var layout = TextureDataLayout() { BytesPerRow = (uint32)(mipSize * 8), RowsPerImage = (uint32)mipSize };
			var writeSize = Extent3D((uint32)mipSize, (uint32)mipSize, 1);

			for (int32 layer = 0; layer < totalLayers; layer++)
			{
				if (batch != null)
					batch.WriteTexture(mCubemapArray, Span<uint8>(zeroData.Ptr, dataSize), layout, writeSize, mip, (uint32)layer);
				else
					TransferHelper.WriteTextureSync(device.GetQueue(.Graphics), device,mCubemapArray, Span<uint8>(zeroData.Ptr, dataSize), layout, writeSize, mip, (uint32)layer);
			}
		}
	}

	/// Allocates the next free layer in the cubemap array.
	/// Returns -1 if all layers are allocated.
	public int32 AllocateLayer()
	{
		for (int32 i = 0; i < MaxProbes; i++)
		{
			if (!mLayerAllocated[i])
			{
				mLayerAllocated[i] = true;
				return i;
			}
		}
		return -1;
	}

	/// Frees a previously allocated layer.
	public void FreeLayer(int32 layer)
	{
		if (layer >= 0 && layer < MaxProbes)
			mLayerAllocated[layer] = false;
	}

	/// Bakes a prefiltered cubemap for a probe at the given array layer.
	/// Also computes SH9 irradiance coefficients and stores them in outSH.
	/// Uses CPU gradient sky generation (same algorithm as SkyFeature).
	public void BakeProbe(int32 layer, Color zenith, Color horizon, Color ground, Vector4* outSH)
	{
		if (layer < 0 || layer >= MaxProbes || mCubemapArray == null || mDevice == null)
			return;

		// Color.R/G/B return uint8 (0-255), need to normalize to 0-1 float
		let topColor = Vector3((float)zenith.R / 255.0f, (float)zenith.G / 255.0f, (float)zenith.B / 255.0f);
		let horizonColor = Vector3((float)horizon.R / 255.0f, (float)horizon.G / 255.0f, (float)horizon.B / 255.0f);
		let groundColor = Vector3((float)ground.R / 255.0f, (float)ground.G / 255.0f, (float)ground.B / 255.0f);

		// Project SH9 irradiance from the same gradient sky
		if (outSH != null)
			ProjectSH9(topColor, horizonColor, groundColor, outSH);

		// Allocate buffer for largest face (mip 0)
		int32 maxPixels = CubemapSize * CubemapSize;
		uint16[] faceData = new uint16[maxPixels * 4];
		defer delete faceData;

		for (uint32 mip = 0; mip < MipLevels; mip++)
		{
			int32 mipSize = CubemapSize >> (int32)mip;
			float roughness = (float)mip / (float)(MipLevels - 1);

			for (int32 face = 0; face < 6; face++)
			{
				for (int32 y = 0; y < mipSize; y++)
				{
					for (int32 x = 0; x < mipSize; x++)
					{
						Vector3 N = CubemapTexelDirection(face, x, y, mipSize);
						Vector3 R = N;
						Vector3 V = R;

						Vector3 T, B;
						BuildTangentBasis(N, out T, out B);

						Vector3 prefilteredColor = .Zero;
						float totalWeight = 0.0f;

						for (int32 i = 0; i < NumSamples; i++)
						{
							float xi1 = (float)i / (float)NumSamples;
							float xi2 = RadicalInverseVdC((uint32)i);

							Vector3 H = TangentToWorld(ImportanceSampleGGX(xi1, xi2, roughness), T, B, N);
							Vector3 L = H * (2.0f * Vector3.Dot(V, H)) - V;

							float NdotL = Math.Max(Vector3.Dot(N, L), 0.0f);
							if (NdotL > 0.0f)
							{
								Vector3 skyColor = SampleGradientSky(L, topColor, horizonColor, groundColor);
								prefilteredColor += skyColor * NdotL;
								totalWeight += NdotL;
							}
						}

						if (totalWeight > 0.0f)
							prefilteredColor = prefilteredColor * (1.0f / totalWeight);

						int32 idx = (y * mipSize + x) * 4;
						faceData[idx + 0] = FloatToHalf(prefilteredColor.X);
						faceData[idx + 1] = FloatToHalf(prefilteredColor.Y);
						faceData[idx + 2] = FloatToHalf(prefilteredColor.Z);
						faceData[idx + 3] = FloatToHalf(1.0f);
					}
				}

				// Upload to cubemap array: array layer = layer * 6 + face
				uint32 arrayLayer = (uint32)(layer * 6 + face);
				var layout = TextureDataLayout() { BytesPerRow = (uint32)(mipSize * 8), RowsPerImage = (uint32)mipSize };
				var writeSize = Extent3D((uint32)mipSize, (uint32)mipSize, 1);
				TransferHelper.WriteTextureSync(mDevice.GetQueue(.Graphics), mDevice, mCubemapArray, Span<uint8>((uint8*)faceData.Ptr, mipSize * mipSize * 8), layout, writeSize, mip, arrayLayer);
			}
		}

		mGeneration++;
	}

	/// Updates the probe uniform buffer from the active probes in the render world.
	/// Also bakes any dirty probes.
	public void UpdateProbeUniforms(RenderWorld world, int32 frameIndex)
	{
		if (world == null || frameIndex < 0 || frameIndex >= RenderConfig.FrameBufferCount)
			return;

		let buffer = mProbeUniformBuffers[frameIndex];
		if (buffer == null)
			return;

		var uniforms = ProbeUniforms();
		uint32 probeCount = 0;

		world.ForEachReflectionProbe(scope [&] (handle, proxy) =>
		{
			if (!proxy.IsEnabled || !proxy.IsActive || probeCount >= (uint32)MaxProbes)
				return;

			// Allocate layer if needed
			if (proxy.ArrayLayer < 0)
			{
				proxy.ArrayLayer = AllocateLayer();
				if (proxy.ArrayLayer < 0)
					return; // No free layers
				proxy.IsDirty = true;
			}

			// Bake if dirty
			if (proxy.IsDirty)
			{
				BakeProbe(proxy.ArrayLayer, proxy.ZenithColor, proxy.HorizonColor, proxy.GroundColor, &proxy.IrradianceSH);
				proxy.IsDirty = false;
			}

			// Fill uniform data
			uniforms.Probes[probeCount].Position = proxy.Position;
			uniforms.Probes[probeCount].Radius = proxy.Radius;
			uniforms.Probes[probeCount].LayerIndex = (uint32)proxy.ArrayLayer;
			uniforms.Probes[probeCount].IrradianceSH = proxy.IrradianceSH;
			probeCount++;
		});

		uniforms.ProbeCount = probeCount;

		// Upload to this frame's buffer
		if (let ptr = buffer.Map())
		{
			Internal.MemCpy(ptr, &uniforms, (int)ProbeUniforms.Size);
			buffer.Unmap();
		}
	}

	/// Gets the cubemap array view for the bind group.
	/// Returns the probe array if any probes are allocated, otherwise the fallback.
	public ITextureView GetCubemapArrayView()
	{
		// Check if any layers are allocated
		for (int32 i = 0; i < MaxProbes; i++)
		{
			if (mLayerAllocated[i])
			{
				if (mCubemapArrayView != null)
					return mCubemapArrayView;
			}
		}
		return mFallbackCubemapArrayView;
	}

	/// Gets the probe uniform buffer for the given frame.
	public IBuffer GetProbeUniformBuffer(int32 frameIndex)
	{
		if (frameIndex >= 0 && frameIndex < RenderConfig.FrameBufferCount)
			return mProbeUniformBuffers[frameIndex];
		return null;
	}

	/// Disposes GPU resources.
	public void Dispose()
	{
		if (mDevice == null)
			return;

		mDevice.DestroyTextureView(ref mCubemapArrayView);
		mDevice.DestroyTexture(ref mCubemapArray);
		mDevice.DestroyTextureView(ref mFallbackCubemapArrayView);
		mDevice.DestroyTexture(ref mFallbackCubemapArray);
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
			mDevice.DestroyBuffer(ref mProbeUniformBuffers[i]);
	}

	/// Projects gradient sky into SH9 irradiance coefficients (pre-convolved with cosine lobe).
	/// Uses stratified lat/lon sampling over the sphere (~4096 samples).
	private static void ProjectSH9(Vector3 topColor, Vector3 horizonColor, Vector3 groundColor, Vector4* outSH)
	{
		// Zero output
		for (int32 i = 0; i < 9; i++)
			outSH[i] = .Zero;

		// Stratified sampling: 64 phi x 64 theta = 4096 directions
		const int32 NumPhi = 64;
		const int32 NumTheta = 64;
		const float dPhi = 2.0f * Math.PI_f / (float)NumPhi;
		const float dTheta = Math.PI_f / (float)NumTheta;

		for (int32 ti = 0; ti < NumTheta; ti++)
		{
			float theta = ((float)ti + 0.5f) * dTheta;
			float sinTheta = Math.Sin(theta);
			float cosTheta = Math.Cos(theta);

			for (int32 pi = 0; pi < NumPhi; pi++)
			{
				float phi = ((float)pi + 0.5f) * dPhi;
				float sinPhi = Math.Sin(phi);
				float cosPhi = Math.Cos(phi);

				// Direction on sphere (Y-up)
				Vector3 dir = .(sinTheta * cosPhi, cosTheta, sinTheta * sinPhi);
				Vector3 skyColor = SampleGradientSky(dir, topColor, horizonColor, groundColor);

				// Solid angle weight for lat/lon grid
				float weight = sinTheta * dTheta * dPhi;

				// SH basis functions (real, orthonormal)
				float[9] Y = .();
				Y[0] = 0.282095f;                                           // Y00
				Y[1] = 0.488603f * dir.Y;                                   // Y1,-1
				Y[2] = 0.488603f * dir.Z;                                   // Y1,0
				Y[3] = 0.488603f * dir.X;                                   // Y1,1
				Y[4] = 1.092548f * dir.X * dir.Y;                           // Y2,-2
				Y[5] = 1.092548f * dir.Y * dir.Z;                           // Y2,-1
				Y[6] = 0.315392f * (3.0f * dir.Z * dir.Z - 1.0f);          // Y2,0
				Y[7] = 1.092548f * dir.X * dir.Z;                           // Y2,1
				Y[8] = 0.546274f * (dir.X * dir.X - dir.Y * dir.Y);        // Y2,2

				for (int32 i = 0; i < 9; i++)
				{
					float basis = Y[i] * weight;
					outSH[i].X += skyColor.X * basis;
					outSH[i].Y += skyColor.Y * basis;
					outSH[i].Z += skyColor.Z * basis;
				}
			}
		}

		// Pre-multiply by cosine convolution coefficients (Al) so shader just evaluates
		// Band 0 (index 0): * PI
		outSH[0] = outSH[0] * Math.PI_f;
		// Band 1 (indices 1-3): * 2*PI/3
		float a1 = 2.0f * Math.PI_f / 3.0f;
		for (int32 i = 1; i <= 3; i++)
			outSH[i] = outSH[i] * a1;
		// Band 2 (indices 4-8): * PI/4
		float a2 = Math.PI_f / 4.0f;
		for (int32 i = 4; i <= 8; i++)
			outSH[i] = outSH[i] * a2;
	}

	// ==================== IBL Helper Methods (same as SkyFeature) ====================

	private static uint16 FloatToHalf(float value)
	{
		if (value == 0.0f) return 0;
		if (value != value) return 0x7E00;

		var val = value;
		uint32 bits = *(uint32*)&val;
		uint32 sign = (bits >> 16) & 0x8000;
		int32 exp = (int32)((bits >> 23) & 0xFF) - 127 + 15;
		uint32 mantissa = bits & 0x007FFFFF;

		if (exp <= 0)
			return (uint16)sign;
		else if (exp >= 31)
			return (uint16)(sign | 0x7C00);

		return (uint16)(sign | ((uint32)exp << 10) | (mantissa >> 13));
	}

	private static Vector3 CubemapTexelDirection(int32 face, int32 x, int32 y, int32 resolution)
	{
		float u = ((float)x + 0.5f) / (float)resolution * 2.0f - 1.0f;
		float v = ((float)y + 0.5f) / (float)resolution * 2.0f - 1.0f;

		Vector3 dir;
		switch (face)
		{
		case 0: dir = .(1.0f, -v, -u);
		case 1: dir = .(-1.0f, -v, u);
		case 2: dir = .(u, 1.0f, v);
		case 3: dir = .(u, -1.0f, -v);
		case 4: dir = .(u, -v, 1.0f);
		default: dir = .(-u, -v, -1.0f);
		}
		return Vector3.Normalize(dir);
	}

	private static Vector3 SampleGradientSky(Vector3 dir, Vector3 topColor, Vector3 horizonColor, Vector3 groundColor)
	{
		float elevation = dir.Y;
		if (elevation > 0.0f)
			return Vector3.Lerp(horizonColor, topColor, elevation);
		else
			return Vector3.Lerp(horizonColor, groundColor, -elevation);
	}

	private static Vector3 ImportanceSampleGGX(float xi1, float xi2, float roughness)
	{
		float a = roughness * roughness;
		float phi = 2.0f * Math.PI_f * xi1;
		float cosTheta = Math.Sqrt((1.0f - xi2) / (1.0f + (a * a - 1.0f) * xi2));
		float sinTheta = Math.Sqrt(1.0f - cosTheta * cosTheta);

		return .(Math.Cos(phi) * sinTheta, Math.Sin(phi) * sinTheta, cosTheta);
	}

	private static void BuildTangentBasis(Vector3 N, out Vector3 T, out Vector3 B)
	{
		Vector3 up = (Math.Abs(N.Y) < 0.999f) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
		T = Vector3.Normalize(Vector3.Cross(up, N));
		B = Vector3.Cross(N, T);
	}

	private static Vector3 TangentToWorld(Vector3 v, Vector3 T, Vector3 B, Vector3 N)
	{
		return T * v.X + B * v.Y + N * v.Z;
	}

	private static float RadicalInverseVdC(uint32 bits)
	{
		var bits;
		bits = (bits << 16) | (bits >> 16);
		bits = ((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1);
		bits = ((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2);
		bits = ((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4);
		bits = ((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8);
		return (float)bits * 2.3283064365386963e-10f;
	}
}
