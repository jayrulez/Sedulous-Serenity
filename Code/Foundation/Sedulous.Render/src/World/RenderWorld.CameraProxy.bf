using Sedulous.Core.Mathematics;
namespace Sedulous.Render;

extension RenderWorld
{
	private RenderPool<CameraProxy> mCameraProxies = new .() ~ delete _;

	// ========================================================================
	// Camera API
	// ========================================================================

	/// Creates a new camera proxy.
	public CameraRenderHandle CreateCamera()
	{
		let handle = mCameraProxies.Allocate();
		var proxy = mCameraProxies.Get(handle);
		proxy.Reset();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mCamerasDirty = true;
		return .() { Handle = handle };
	}

	/// Creates a perspective camera.
	public CameraRenderHandle CreatePerspectiveCamera(Vector3 position, Vector3 target, Vector3 up, float fov, float aspectRatio, float nearPlane, float farPlane)
	{
		let handle = CreateCamera();
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			*proxy = CameraProxy.CreatePerspective(position, target, up, fov, aspectRatio, nearPlane, farPlane);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Creates an orthographic camera.
	public CameraRenderHandle CreateOrthographicCamera(Vector3 position, Vector3 target, Vector3 up, float width, float height, float nearPlane, float farPlane)
	{
		let handle = CreateCamera();
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			*proxy = CameraProxy.CreateOrthographic(position, target, up, width, height, nearPlane, farPlane);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Gets a camera proxy by handle.
	public CameraProxy* GetCamera(CameraRenderHandle handle)
	{
		return mCameraProxies.Get(handle.Handle);
	}

	/// Gets a reference to a camera proxy.
	public ref CameraProxy GetCameraRef(CameraRenderHandle handle)
	{
		return ref mCameraProxies.GetRef(handle.Handle);
	}

	/// Destroys a camera proxy.
	public void DestroyCamera(CameraRenderHandle handle)
	{
		// If this was the main camera, clear it
		if (mMainCamera == handle)
			mMainCamera = .Invalid;

		if (mCameraProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mCameraProxies.Free(handle.Handle);
		mCamerasDirty = true;
	}

	/// Sets the main camera.
	public void SetMainCamera(CameraRenderHandle handle)
	{
		mMainCamera = handle;
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.IsMainCamera = true;
		}
		mCamerasDirty = true;
	}

	/// Sets camera position and orientation using look-at.
	public void SetCameraLookAt(CameraRenderHandle handle, Vector3 position, Vector3 target, Vector3 up)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.SetLookAt(position, target, up);
			mCamerasDirty = true;
		}
	}

	/// Sets camera position and direction.
	public void SetCameraPositionDirection(CameraRenderHandle handle, Vector3 position, Vector3 forward, Vector3 up)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.SetPositionDirection(position, forward, up);
			mCamerasDirty = true;
		}
	}

	/// Updates camera matrices. Should be called after changing position/orientation.
	public void UpdateCameraMatrices(CameraRenderHandle handle, bool flipY = false)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.UpdateMatrices(flipY);
			mCamerasDirty = true;
		}
	}

	/// Sets camera TAA jitter for the current frame.
	public void SetCameraJitter(CameraRenderHandle handle, Vector2 pixelOffset, uint32 viewportWidth, uint32 viewportHeight)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.SetJitter(pixelOffset, viewportWidth, viewportHeight);
			mCamerasDirty = true;
		}
	}

	/// Iterates over all active cameras.
	public void ForEachCamera(RenderPoolCallback<CameraProxy> callback)
	{
		mCameraProxies.ForEach(callback);
	}
}
