using System;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

namespace Sedulous.Renderer;

/// Per-frame rendering context.
/// Manages multi-buffered scene uniform buffers with persistent mapping.
/// Frame-level data (timing, frame number, light counts) is constant across all views.
/// View-level data (camera, matrices) varies per view — uploaded via UploadUniforms(ViewContext).
public class RenderFrameContext
{
	private IDevice mDevice;
	private IBuffer[RenderConfig.TotalBufferSlots] mSceneUniformBuffers;
	private void*[RenderConfig.TotalBufferSlots] mMappedPtrs;
	private int32 mCurrentSlot;

	/// Frame-level data (constant across views within a frame)
	public float TotalTime;
	public float DeltaTime;
	public uint32 FrameNumber;
	public uint32 LightCount;
	public uint32 ShadowCascadeCount;
	public uint32 ProbeCount;

	/// Size of the scene uniform buffer in bytes
	public static uint64 SceneUniformSize => SceneUniforms.Size;

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Initialize per-frame buffers (persistently mapped)
	public Result<void> Initialize()
	{
		for (int i = 0; i < RenderConfig.TotalBufferSlots; i++)
		{
			if (mDevice.CreateBuffer(BufferDesc()
			{
				Size = SceneUniforms.Size,
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "SceneUniforms"
			}) case .Ok(let buf))
			{
				mSceneUniformBuffers[i] = buf;
				mMappedPtrs[i] = buf.Map();
			}
			else
				return .Err;
		}

		return .Ok;
	}

	/// Set the active buffer slot for this frame + view combination
	public void SetSlot(int32 frameIndex, int32 viewIndex)
	{
		mCurrentSlot = RenderConfig.BufferSlot(frameIndex, viewIndex);
	}

	/// Get the current scene uniform buffer
	public IBuffer CurrentSceneBuffer => mSceneUniformBuffers[mCurrentSlot];

	/// Builds SceneUniforms from view context and world data, uploads to the current slot's GPU buffer.
	/// Returns the uploaded uniforms snapshot.
	public SceneUniforms UploadUniforms(ViewContext viewCtx, RenderWorld world = null)
	{
		SceneUniforms uniforms = .();
		uniforms.ViewMatrix = viewCtx.ViewMatrix;
		uniforms.ProjectionMatrix = viewCtx.ProjectionMatrix;
		uniforms.ViewProjectionMatrix = viewCtx.ViewProjectionMatrix;

		Matrix.TryInvert(viewCtx.ViewMatrix, out uniforms.InverseViewMatrix);
		Matrix.TryInvert(viewCtx.ProjectionMatrix, out uniforms.InverseProjectionMatrix);

		uniforms.PrevViewProjectionMatrix = viewCtx.PrevViewProjectionMatrix;
		uniforms.CameraPosition = viewCtx.CameraPosition;
		uniforms.CameraForward = viewCtx.CameraForward;
		uniforms.Time = TotalTime;
		uniforms.DeltaTime = DeltaTime;
		uniforms.ScreenSize = Vector2((float)viewCtx.RenderWidth, (float)viewCtx.RenderHeight);
		uniforms.NearPlane = viewCtx.NearPlane;
		uniforms.FarPlane = viewCtx.FarPlane;

		// Upload to persistently mapped buffer
		if (mMappedPtrs[mCurrentSlot] != null)
			Internal.MemCpy(mMappedPtrs[mCurrentSlot], &uniforms, SceneUniforms.Size);

		// Store uniform buffer reference in view context for pass binding
		viewCtx.SceneUniformBuffer = mSceneUniformBuffers[mCurrentSlot];
		viewCtx.Uniforms = uniforms;

		return uniforms;
	}

	public void Shutdown()
	{
		for (int i = 0; i < RenderConfig.TotalBufferSlots; i++)
		{
			if (mSceneUniformBuffers[i] != null)
			{
				if (mMappedPtrs[i] != null)
				{
					mSceneUniformBuffers[i].Unmap();
					mMappedPtrs[i] = null;
				}
				var buf = mSceneUniformBuffers[i];
				mDevice.DestroyBuffer(ref buf);
				mSceneUniformBuffers[i] = null;
			}
		}
	}

	public ~this()
	{
		Shutdown();
	}
}
