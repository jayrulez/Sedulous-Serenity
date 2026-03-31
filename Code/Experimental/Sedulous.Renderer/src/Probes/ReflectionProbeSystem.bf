namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// GPU probe data layout (matches forward_pbr.hlsl ProbeData struct).
[CRepr]
struct GPUProbeData
{
	public Vector3 Position;
	public float _pad1;
	public Vector3 BoxMin;
	public float _pad2;
	public Vector3 BoxMax;
	public uint32 LayerIndex;
}

/// GPU probe uniforms header (uploaded each frame).
[CRepr]
struct GPUProbeUniforms
{
	public uint32 ProbeCount;
	public float[3] _pad;
	public GPUProbeData[ReflectionProbeSystem.MaxProbes] Probes;
}

/// Manages reflection probe cubemap array, layer allocation, uniform upload, and baking.
class ReflectionProbeSystem
{
	public const int MaxProbes = 16;
	public const uint32 CubemapSize = 128;
	public const uint32 CubemapMips = 1;  // TODO: add compute prefilter for roughness mips

	private IDevice mDevice;

	// Shared cubemap array: 6 * MaxProbes layers
	private ITexture mCubemapArray;
	private ITextureView mCubemapArrayView;  // TextureCubeArray view for shader sampling

	// Per-face render target views for baking (6 * MaxProbes)
	private ITextureView[6 * MaxProbes] mFaceViews;

	// Layer allocation
	private bool[MaxProbes] mLayerAllocated;

	// Probe uniform buffer (CpuToGpu mapped)
	private IBuffer[RenderConfig.FrameBufferCount] mUniformBuffers;
	private void*[RenderConfig.FrameBufferCount] mMappedPtrs;

	// Fallback (1x1 black cubemap array for when no probes are active)
	private ITexture mFallbackTexture;
	private ITextureView mFallbackView;

	private uint32 mActiveProbeCount;

	public ITextureView CubemapArrayView => (mCubemapArrayView != null) ? mCubemapArrayView : mFallbackView;
	public uint32 ActiveProbeCount => mActiveProbeCount;

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create cubemap array texture: 6 * MaxProbes layers, with mip levels
		let texResult = device.CreateTexture(TextureDesc.Tex2DArray(
			.RGBA16Float, CubemapSize, CubemapSize,
			(uint32)(6 * MaxProbes),
			.Sampled | .RenderTarget | .CopyDst,
			mipLevels: CubemapMips,
			label: "ReflectionProbe_CubemapArray"
		));
		if (texResult case .Err) { Console.WriteLine("ERROR: Failed to create probe cubemap array"); return .Err; }
		mCubemapArray = texResult.Value;

		// TextureCubeArray view for shader sampling (all probes)
		let arrayViewResult = device.CreateTextureView(mCubemapArray, TextureViewDesc()
		{
			Dimension = .TextureCubeArray,
			BaseArrayLayer = 0,
			ArrayLayerCount = (uint32)(6 * MaxProbes),
			MipLevelCount = CubemapMips,
			Label = "ReflectionProbe_CubeArrayView"
		});
		if (arrayViewResult case .Err) { Console.WriteLine("ERROR: Failed to create probe cubemap array view"); return .Err; }
		mCubemapArrayView = arrayViewResult.Value;

		// Create per-face render target views for baking
		for (int probe = 0; probe < MaxProbes; probe++)
		{
			for (int face = 0; face < 6; face++)
			{
				let idx = probe * 6 + face;
				let faceViewResult = device.CreateTextureView(mCubemapArray, TextureViewDesc()
				{
					Dimension = .Texture2D,
					BaseArrayLayer = (uint32)idx,
					ArrayLayerCount = 1,
					BaseMipLevel = 0,
					MipLevelCount = 1,
					Label = "ReflectionProbe_FaceView"
				});
				if (faceViewResult case .Err) { Console.WriteLine(scope $"ERROR: Failed to create probe face view {idx}"); return .Err; }
				mFaceViews[idx] = faceViewResult.Value;
			}
		}

		// Uniform buffers (double-buffered)
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			let bufResult = device.CreateBuffer(BufferDesc()
			{
				Size = (uint64)sizeof(GPUProbeUniforms),
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "ReflectionProbe_Uniforms"
			});
			if (bufResult case .Err) { Console.WriteLine("ERROR: Failed to create probe uniform buffer"); return .Err; }
			mUniformBuffers[i] = bufResult.Value;
			mMappedPtrs[i] = mUniformBuffers[i].Map();
		}

		// Fallback: 1x1 black cubemap array (6 layers)
		let fallbackResult = device.CreateTexture(TextureDesc.Tex2DArray(
			.RGBA16Float, 1, 1, 6,
			.Sampled | .CopyDst,
			label: "ReflectionProbe_Fallback"
		));
		if (fallbackResult case .Err) { Console.WriteLine("ERROR: Failed to create probe fallback texture"); return .Err; }
		mFallbackTexture = fallbackResult.Value;

		let fallbackViewResult = device.CreateTextureView(mFallbackTexture, TextureViewDesc()
		{
			Dimension = .TextureCubeArray,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6,
			Label = "ReflectionProbe_FallbackView"
		});
		if (fallbackViewResult case .Err) { Console.WriteLine("ERROR: Failed to create probe fallback view"); return .Err; }
		mFallbackView = fallbackViewResult.Value;

		return .Ok;
	}

	/// Allocates a cubemap layer for a probe. Returns the layer index (0-based).
	public int32 AllocateLayer()
	{
		for (int i = 0; i < MaxProbes; i++)
		{
			if (!mLayerAllocated[i])
			{
				mLayerAllocated[i] = true;
				return (int32)i;
			}
		}
		return -1;
	}

	/// Frees a cubemap layer.
	public void FreeLayer(int32 layer)
	{
		if (layer >= 0 && layer < MaxProbes)
			mLayerAllocated[layer] = false;
	}

	/// Syncs proxy data and uploads uniform buffer for the current frame.
	public void Update(RenderWorld world, int frameIndex)
	{
		var uniforms = GPUProbeUniforms();
		uint32 count = 0;

		world.ReflectionProbes.ForEach(scope [&](handle, proxy) =>
		{
			if (!proxy.Enabled || count >= MaxProbes) return;

			// Auto-allocate layer if needed
			if (proxy.CubemapLayer < 0)
			{
				proxy.CubemapLayer = AllocateLayer();
				if (proxy.CubemapLayer < 0) return;  // No free layers
				proxy.IsDirty = true;
			}

			uniforms.Probes[(int)count] = .()
			{
				Position = proxy.Position,
				BoxMin = proxy.BoxMin,
				BoxMax = proxy.BoxMax,
				LayerIndex = (uint32)proxy.CubemapLayer
			};
			count++;
		});

		uniforms.ProbeCount = count;
		mActiveProbeCount = count;

		// Upload
		let ptr = mMappedPtrs[frameIndex];
		if (ptr != null)
			Internal.MemCpy(ptr, &uniforms, sizeof(GPUProbeUniforms));
	}

	/// Gets the uniform buffer for the current frame.
	public IBuffer GetUniformBuffer(int frameIndex) => mUniformBuffers[frameIndex];

	/// Gets the render target view for a specific probe face.
	public ITextureView GetFaceView(int32 probeLayer, int face) => mFaceViews[probeLayer * 6 + face];

	/// Gets the cubemap array texture (for mip generation after baking).
	public ITexture CubemapArrayTexture => mCubemapArray;

	/// Gets the cubemap face directions for rendering.
	public static void GetFaceCamera(int face, out Vector3 forward, out Vector3 up)
	{
		switch (face)
		{
		case 0: forward = .(1, 0, 0);  up = .(0, -1, 0);  // +X
		case 1: forward = .(-1, 0, 0); up = .(0, -1, 0);  // -X
		case 2: forward = .(0, 1, 0);  up = .(0, 0, 1);   // +Y
		case 3: forward = .(0, -1, 0); up = .(0, 0, -1);  // -Y
		case 4: forward = .(0, 0, 1);  up = .(0, -1, 0);  // +Z
		case 5: forward = .(0, 0, -1); up = .(0, -1, 0);  // -Z
		default: forward = .(0, 0, 1); up = .(0, -1, 0);
		}
	}

	public void Shutdown(IDevice device)
	{
		for (int i = 0; i < 6 * MaxProbes; i++)
			if (mFaceViews[i] != null) device.DestroyTextureView(ref mFaceViews[i]);
		if (mCubemapArrayView != null) device.DestroyTextureView(ref mCubemapArrayView);
		if (mCubemapArray != null) device.DestroyTexture(ref mCubemapArray);
		if (mFallbackView != null) device.DestroyTextureView(ref mFallbackView);
		if (mFallbackTexture != null) device.DestroyTexture(ref mFallbackTexture);
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			if (mUniformBuffers[i] != null) { mUniformBuffers[i].Unmap(); device.DestroyBuffer(ref mUniformBuffers[i]); }
	}
}
