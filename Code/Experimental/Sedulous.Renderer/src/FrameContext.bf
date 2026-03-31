namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;

/// GPU-uploadable per-frame scene uniforms.
/// Matches the shader cbuffer layout exactly (448 bytes).
[CRepr]
struct SceneUniforms
{
	public Matrix ViewMatrix;                  // 64 bytes
	public Matrix ProjectionMatrix;            // 64 bytes
	public Matrix ViewProjectionMatrix;        // 64 bytes
	public Matrix InverseViewMatrix;           // 64 bytes
	public Matrix InverseProjectionMatrix;     // 64 bytes
	public Matrix PrevViewProjectionMatrix;    // 64 bytes
	public Vector3 CameraPosition;             // 12 bytes
	public float Time;                         // 4 bytes
	public Vector3 CameraForward;              // 12 bytes
	public float DeltaTime;                    // 4 bytes
	public Vector2 ScreenSize;                 // 8 bytes
	public float NearPlane;                    // 4 bytes
	public float FarPlane;                     // 4 bytes
	public uint32 FrameNumber;                 // 4 bytes
	public uint32 LightCount;                  // 4 bytes
	public uint32 ShadowCascadeCount;          // 4 bytes
	public float Exposure;                     // 4 bytes — scene exposure multiplier (pre-tonemap)
	public float AmbientIntensity;             // 4 bytes — IBL ambient multiplier
	public float SkyExposure;                  // 4 bytes — HDRI sky brightness multiplier
	public uint32 ProbeCount;                  // 4 bytes — active reflection probe count
	public float _pad3;                        // 4 bytes
	// Total: 464 bytes
}

/// Per-frame context — data constant across all views within a single frame.
/// Manages multi-buffered scene uniform upload.
/// Buffers are sized [FrameBufferCount * MaxViews] so that multiple views
/// can be batched into a single command buffer submission without overwriting
/// each other's mapped data.
class FrameContext
{
	private IDevice mDevice;
	private IBuffer[RenderConfig.TotalBufferSlots] mUniformBuffers;
	private void*[RenderConfig.TotalBufferSlots] mMappedPtrs;
	private int mCurrentSlot;

	public float TotalTime;
	public float DeltaTime;
	public uint32 FrameNumber;
	public uint32 LightCount;
	public uint32 ShadowCascadeCount;
	public uint32 ProbeCount;

	/// The current buffer slot's uniform buffer.
	public IBuffer CurrentUniformBuffer => mUniformBuffers[mCurrentSlot];

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		for (int i = 0; i < RenderConfig.TotalBufferSlots; i++)
		{
			let result = device.CreateBuffer(BufferDesc()
			{
				Size = (uint64)sizeof(SceneUniforms),
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "SceneUniforms"
			});

			if (result case .Err)
				return .Err;

			mUniformBuffers[i] = result.Value;
			mMappedPtrs[i] = mUniformBuffers[i].Map();
		}

		return .Ok;
	}

	/// Selects the current buffer slot for this frame + view combination.
	public void SetSlot(int frameIndex, int viewIndex)
	{
		mCurrentSlot = RenderConfig.BufferSlot(frameIndex, viewIndex);
	}

	/// Builds scene uniforms from the view context and world, uploads to GPU.
	public SceneUniforms UploadUniforms(ViewContext viewCtx, RenderWorld world)
	{
		SceneUniforms uniforms = .();
		uniforms.ViewMatrix = viewCtx.ViewMatrix;
		uniforms.ProjectionMatrix = viewCtx.ProjectionMatrix;
		uniforms.ViewProjectionMatrix = viewCtx.ViewProjectionMatrix;

		// Compute inverses
		Matrix.Invert(viewCtx.ViewMatrix, out uniforms.InverseViewMatrix);
		Matrix.Invert(viewCtx.ProjectionMatrix, out uniforms.InverseProjectionMatrix);

		uniforms.PrevViewProjectionMatrix = viewCtx.PrevViewProjectionMatrix;
		uniforms.CameraPosition = viewCtx.CameraPosition;
		uniforms.CameraForward = viewCtx.CameraForward;
		uniforms.Time = TotalTime;
		uniforms.DeltaTime = DeltaTime;
		uniforms.ScreenSize = Vector2((float)viewCtx.RenderWidth, (float)viewCtx.RenderHeight);
		uniforms.NearPlane = viewCtx.NearPlane;
		uniforms.FarPlane = viewCtx.FarPlane;
		uniforms.FrameNumber = FrameNumber;
		uniforms.LightCount = LightCount;
		uniforms.ShadowCascadeCount = ShadowCascadeCount;
		uniforms.ProbeCount = ProbeCount;
		uniforms.Exposure = viewCtx.Exposure;
		uniforms.AmbientIntensity = (world?.Environment != null) ? world.Environment.AmbientIntensity : 1.0f;
		uniforms.SkyExposure = (world?.Environment != null) ? world.Environment.SkyExposure : 1.0f;

		// Upload to mapped buffer
		if (mMappedPtrs[mCurrentSlot] != null)
			Internal.MemCpy(mMappedPtrs[mCurrentSlot], &uniforms, sizeof(SceneUniforms));

		return uniforms;
	}

	public void Shutdown()
	{
		if (mDevice == null)
			return;

		for (int i = 0; i < RenderConfig.TotalBufferSlots; i++)
		{
			if (mUniformBuffers[i] != null)
			{
				mUniformBuffers[i].Unmap();
				mMappedPtrs[i] = null;
				mDevice.DestroyBuffer(ref mUniformBuffers[i]);
			}
		}
	}
}
