namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;

extension RenderWorld
{
	private ProxyPool<CameraProxy> mCameraProxies = new .() ~ delete _;

	private bool mCamerasDirty = false;

	/// Gets the camera proxy pool.
	public ProxyPool<CameraProxy> CameraProxies => mCameraProxies;

	/// Gets the number of active cameras.
	public int32 CameraCount => mCameraProxies.ActiveCount;

	/// Whether any cameras have changed.
	public bool CamerasDirty => mCamerasDirty;

	/// Creates a new camera proxy.
	public CameraProxyHandle CreateCamera()
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
	public CameraProxyHandle CreatePerspectiveCamera(Vector3 position, Vector3 target, Vector3 up, float fov, float aspectRatio, float nearPlane, float farPlane)
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
	public CameraProxyHandle CreateOrthographicCamera(Vector3 position, Vector3 target, Vector3 up, float width, float height, float nearPlane, float farPlane)
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
	public CameraProxy* GetCamera(CameraProxyHandle handle)
	{
		return mCameraProxies.Get(handle.Handle);
	}

	/// Gets a reference to a camera proxy.
	public ref CameraProxy GetCameraRef(CameraProxyHandle handle)
	{
		return ref mCameraProxies.GetRef(handle.Handle);
	}

	/// Destroys a camera proxy.
	public void DestroyCamera(CameraProxyHandle handle)
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
	public void SetMainCamera(CameraProxyHandle handle)
	{
		mMainCamera = handle;
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.IsMainCamera = true;
		}
		mCamerasDirty = true;
	}

	/// Sets camera position and orientation using look-at.
	public void SetCameraLookAt(CameraProxyHandle handle, Vector3 position, Vector3 target, Vector3 up)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.SetLookAt(position, target, up);
			mCamerasDirty = true;
		}
	}

	/// Sets camera position and direction.
	public void SetCameraPositionDirection(CameraProxyHandle handle, Vector3 position, Vector3 forward, Vector3 up)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.SetPositionDirection(position, forward, up);
			mCamerasDirty = true;
		}
	}

	/// Updates camera matrices. Should be called after changing position/orientation.
	public void UpdateCameraMatrices(CameraProxyHandle handle)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.UpdateMatrices();
			mCamerasDirty = true;
		}
	}

	/// Sets camera TAA jitter for the current frame.
	public void SetCameraJitter(CameraProxyHandle handle, Vector2 pixelOffset, uint32 viewportWidth, uint32 viewportHeight)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.SetJitter(pixelOffset, viewportWidth, viewportHeight);
			mCamerasDirty = true;
		}
	}

	/// Iterates over all active cameras.
	public void ForEachCamera(ProxyCallback<CameraProxy> callback)
	{
		mCameraProxies.ForEach(callback);
	}
}
