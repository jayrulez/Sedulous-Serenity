namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Foundation.Mathematics;

/// Per-frame uniform data matching common.hlsli SceneUniforms (b0, space0).
[CRepr]
public struct SceneUniforms
{
	public Matrix ViewMatrix;
	public Matrix ProjectionMatrix;
	public Matrix ViewProjectionMatrix;
	public Matrix InverseViewMatrix;
	public Matrix InverseProjectionMatrix;
	public Matrix PrevViewProjectionMatrix;

	public Vector3 CameraPosition;
	public float Time;

	public Vector3 CameraForward;
	public float DeltaTime;

	public Vector2 ScreenSize;
	public float NearPlane;
	public float FarPlane;

	public const uint32 Size = 464; // 7 matrices (448) + 4 floats (16) = 464

	public static Self Identity => .()
	{
		ViewMatrix = .Identity,
		ProjectionMatrix = .Identity,
		ViewProjectionMatrix = .Identity,
		InverseViewMatrix = .Identity,
		InverseProjectionMatrix = .Identity,
		PrevViewProjectionMatrix = .Identity,
		CameraPosition = .Zero,
		CameraForward = .(0, 0, -1),
		Time = 0,
		DeltaTime = 0.016f,
		ScreenSize = .(1920, 1080),
		NearPlane = 0.1f,
		FarPlane = 1000.0f
	};
}

/// Per-frame GPU state with multi-buffered resources.
/// Each frame in flight gets its own set of resources to avoid GPU/CPU synchronization.
class RenderFrameContext : IDisposable
{
	private IDevice mDevice;

	/// Frame index for multi-buffering (0 to FrameBufferCount-1).
	private int32 mFrameIndex;

	/// Absolute frame number (monotonically increasing).
	private uint64 mFrameNumber;

	/// Time since application start.
	private float mTotalTime;

	/// Time since last frame.
	private float mDeltaTime;

	/// Per-frame, per-view scene uniform buffers.
	/// Indexed as [frameIndex * MaxViews + viewIndex].
	private IBuffer[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneUniformBuffers ~ { for (let b in _) delete b; };

	/// Current scene uniform data.
	private SceneUniforms mSceneUniforms;

	/// Previous frame's view-projection matrices (per-view, for motion vectors).
	private Matrix[RenderConfig.MaxViews] mPrevViewProjections;

	/// Whether scene uniforms are dirty and need upload.
	private bool mSceneUniformsDirty = true;

	/// Currently active view index (0 to MaxViews-1).
	private int32 mActiveViewIndex = 0;

	/// Number of active views this frame.
	private int32 mViewCount = 1;

	/// Current frame index (for multi-buffering).
	public int32 FrameIndex => mFrameIndex;

	/// Absolute frame number.
	public uint64 FrameNumber => mFrameNumber;

	/// Total time since start.
	public float TotalTime => mTotalTime;

	/// Delta time since last frame.
	public float DeltaTime => mDeltaTime;

	/// Current scene uniforms.
	public ref SceneUniforms SceneUniforms => ref mSceneUniforms;

	/// Currently active view index.
	public int32 ActiveViewIndex => mActiveViewIndex;

	/// Number of active views this frame.
	public int32 ViewCount => mViewCount;

	/// Scene uniform buffer for current frame and active view.
	public IBuffer SceneUniformBuffer => mSceneUniformBuffers[mFrameIndex * RenderConfig.MaxViews + mActiveViewIndex];

	/// Scene uniform buffer for a specific frame index and active view.
	public IBuffer GetSceneUniformBuffer(int32 frameIdx) => mSceneUniformBuffers[frameIdx * RenderConfig.MaxViews + mActiveViewIndex];

	/// Sets the active view index for per-view buffer selection.
	public void SetActiveView(int32 viewIndex)
	{
		mActiveViewIndex = Math.Clamp(viewIndex, 0, RenderConfig.MaxViews - 1);
		mSceneUniformsDirty = true;
	}

	/// Sets the number of active views this frame.
	public void SetViewCount(int32 count)
	{
		mViewCount = Math.Clamp(count, 1, RenderConfig.MaxViews);
	}

	/// Initializes the frame context.
	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;
		mSceneUniforms = .Identity;

		// Create per-frame, per-view scene uniform buffers
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			var desc = BufferDescriptor()
			{
				Size = 464, // SceneUniforms size: 7 matrices (448) + 4 floats (16) = 464
				Usage = .Uniform,
				MemoryAccess = .Upload // CPU-mappable
			};

			if (device.CreateBuffer(&desc) case .Ok(let buffer))
				mSceneUniformBuffers[i] = buffer;
			else
				return .Err;
		}

		// Initialize per-view prev VP matrices
		for (int32 i = 0; i < RenderConfig.MaxViews; i++)
			mPrevViewProjections[i] = .Identity;

		return .Ok;
	}

	/// Begins a new frame.
	public void BeginFrame(uint64 frameNumber, float totalTime, float deltaTime)
	{
		mFrameNumber = frameNumber;
		mFrameIndex = (int32)(frameNumber % RenderConfig.FrameBufferCount);
		mTotalTime = totalTime;
		mDeltaTime = deltaTime;

		// Reset view state to single-view defaults each frame.
		// RenderViews() will override these for multi-view rendering.
		mActiveViewIndex = 0;
		mViewCount = 1;

		// Update time in scene uniforms
		mSceneUniforms.Time = totalTime;
		mSceneUniforms.DeltaTime = deltaTime;
		mSceneUniformsDirty = true;
	}

	/// Updates scene uniforms from camera parameters.
	public void SetCamera(
		Vector3 position,
		Vector3 forward,
		Vector3 up,
		float fov,
		float aspectRatio,
		float nearPlane,
		float farPlane,
		uint32 screenWidth,
		uint32 screenHeight,
		bool flipProjection = false)
	{
		// Build view matrix
		let target = position + forward;
		mSceneUniforms.ViewMatrix = Matrix.CreateLookAt(position, target, up);

		// Build projection matrix
		mSceneUniforms.ProjectionMatrix = Matrix.CreatePerspectiveFieldOfView(
			fov, aspectRatio, nearPlane, farPlane);

		// Flip Y for Vulkan if required
		if (flipProjection)
			mSceneUniforms.ProjectionMatrix.M22 = -mSceneUniforms.ProjectionMatrix.M22;

		// Combined VP
		mSceneUniforms.ViewProjectionMatrix = mSceneUniforms.ViewMatrix * mSceneUniforms.ProjectionMatrix;

		// Inverse matrices
		Matrix.Invert(mSceneUniforms.ViewMatrix, out mSceneUniforms.InverseViewMatrix);
		Matrix.Invert(mSceneUniforms.ProjectionMatrix, out mSceneUniforms.InverseProjectionMatrix);

		// Previous frame VP (per-view)
		mSceneUniforms.PrevViewProjectionMatrix = mPrevViewProjections[mActiveViewIndex];

		// Camera parameters
		mSceneUniforms.CameraPosition = position;
		mSceneUniforms.CameraForward = forward;
		mSceneUniforms.NearPlane = nearPlane;
		mSceneUniforms.FarPlane = farPlane;
		mSceneUniforms.ScreenSize = .((float)screenWidth, (float)screenHeight);

		mSceneUniformsDirty = true;
	}

	/// Sets camera from pre-computed matrices.
	public void SetCameraMatrices(
		Matrix viewMatrix,
		Matrix projectionMatrix,
		Vector3 cameraPosition,
		Vector3 cameraForward,
		float nearPlane,
		float farPlane,
		uint32 screenWidth,
		uint32 screenHeight)
	{
		mSceneUniforms.ViewMatrix = viewMatrix;
		mSceneUniforms.ProjectionMatrix = projectionMatrix;
		mSceneUniforms.ViewProjectionMatrix = viewMatrix * projectionMatrix;

		Matrix.Invert(viewMatrix, out mSceneUniforms.InverseViewMatrix);
		Matrix.Invert(projectionMatrix, out mSceneUniforms.InverseProjectionMatrix);

		mSceneUniforms.PrevViewProjectionMatrix = mPrevViewProjections[mActiveViewIndex];
		mSceneUniforms.CameraPosition = cameraPosition;
		mSceneUniforms.CameraForward = cameraForward;
		mSceneUniforms.NearPlane = nearPlane;
		mSceneUniforms.FarPlane = farPlane;
		mSceneUniforms.ScreenSize = .((float)screenWidth, (float)screenHeight);

		mSceneUniformsDirty = true;
	}

	/// Uploads scene uniforms to GPU if dirty.
	public void UploadSceneUniforms()
	{
		if (!mSceneUniformsDirty)
			return;

		let buffer = mSceneUniformBuffers[mFrameIndex * RenderConfig.MaxViews + mActiveViewIndex];
		// Use Map/Unmap to avoid command buffer creation
		if (let ptr = buffer.Map())
		{
			// Bounds check: ensure we don't write past buffer size
			let copySize = Sedulous.Render.SceneUniforms.Size;
			Runtime.Assert(copySize <= (.)buffer.Size, scope $"SceneUniforms copy size ({copySize}) exceeds buffer size ({buffer.Size})");
			Internal.MemCpy(ptr, &mSceneUniforms, copySize);
			buffer.Unmap();
		}
		mSceneUniformsDirty = false;
	}

	/// Saves the current view-projection for next frame's motion vectors.
	/// Call this after uploading scene uniforms for each view.
	public void SaveViewProjection()
	{
		mPrevViewProjections[mActiveViewIndex] = mSceneUniforms.ViewProjectionMatrix;
	}

	/// Ends the current frame.
	public void EndFrame()
	{
	}

	public void Dispose()
	{
		// Buffers cleaned up by destructor
	}
}
