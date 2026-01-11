namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.Renderer;

/// Entity component that adds a camera.
class CameraComponent : IEntityComponent
{
	// Entity and scene references
	private Entity mEntity;
	private RenderSceneComponent mRenderScene;
	private ProxyHandle mProxyHandle = .Invalid;

	// Viewport dimensions
	private uint32 mViewportWidth = 1920;
	private uint32 mViewportHeight = 1080;

	/// Vertical field of view in radians.
	public float FieldOfView = Math.PI_f / 4.0f;

	/// Near clipping plane distance.
	public float NearPlane = 0.1f;

	/// Far clipping plane distance.
	public float FarPlane = 1000.0f;

	/// Whether this is the main camera.
	public bool IsMain = false;

	/// Whether to use reverse-Z depth (recommended for better precision).
	public bool UseReverseZ = true;

	/// Layer mask for what this camera can see.
	public uint32 LayerMask = uint32.MaxValue;

	/// Render target priority (lower = renders first).
	public int32 Priority = 0;

	/// Whether the camera is enabled.
	public bool Enabled = true;

	/// Gets the viewport width.
	public uint32 ViewportWidth => mViewportWidth;

	/// Gets the viewport height.
	public uint32 ViewportHeight => mViewportHeight;

	/// Gets the aspect ratio.
	public float AspectRatio => (float)mViewportWidth / (float)mViewportHeight;

	/// Creates a new CameraComponent.
	public this()
	{
	}

	/// Creates a camera component with specified parameters.
	public this(float fieldOfView, float nearPlane, float farPlane, bool isMain = false)
	{
		FieldOfView = fieldOfView;
		NearPlane = nearPlane;
		FarPlane = farPlane;
		IsMain = isMain;
	}

	/// Sets the viewport dimensions.
	public void SetViewport(uint32 width, uint32 height)
	{
		mViewportWidth = width;
		mViewportHeight = height;

		// Update proxy if attached
		if (mRenderScene != null && mProxyHandle.IsValid)
		{
			if (let proxy = mRenderScene.RenderWorld.GetCameraProxy(mProxyHandle))
			{
				proxy.ViewportWidth = width;
				proxy.ViewportHeight = height;
				proxy.AspectRatio = (float)width / (float)height;
				proxy.UpdateMatrices();
			}
		}
	}

	/// Gets the camera struct for this component.
	public Camera GetCamera()
	{
		var camera = Camera();
		if (mEntity != null)
		{
			camera.Position = mEntity.Transform.WorldPosition;
			camera.Forward = mEntity.Transform.Forward;
			camera.Up = mEntity.Transform.Up;
		}
		camera.FieldOfView = FieldOfView;
		camera.NearPlane = NearPlane;
		camera.FarPlane = FarPlane;
		camera.AspectRatio = AspectRatio;
		camera.UseReverseZ = UseReverseZ;
		return camera;
	}

	/// Gets the camera proxy if attached.
	internal CameraProxy* GetCameraProxy()
	{
		if (mRenderScene != null && mProxyHandle.IsValid)
			return mRenderScene.RenderWorld.GetCameraProxy(mProxyHandle);
		return null;
	}

	/// Creates a ray from the camera through a screen point.
	/// screenX/screenY are in pixel coordinates (0,0 = top-left).
	public Ray ScreenPointToRay(float screenX, float screenY, uint32 viewportWidth, uint32 viewportHeight)
	{
		if (mEntity == null)
			return .(Vector3.Zero, Vector3.Forward);

		// Convert screen to normalized device coordinates (-1 to 1)
		let ndcX = (screenX / (float)viewportWidth) * 2.0f - 1.0f;
		let ndcY = 1.0f - (screenY / (float)viewportHeight) * 2.0f;  // Flip Y

		// Camera properties
		let cameraPos = mEntity.Transform.WorldPosition;
		let forward = mEntity.Transform.Forward;
		let up = mEntity.Transform.Up;
		let right = mEntity.Transform.Right;

		// Calculate the ray direction using perspective projection
		let halfFovTan = Math.Tan(FieldOfView * 0.5f);
		let aspect = (float)viewportWidth / (float)viewportHeight;

		// Direction in view space
		let viewDirX = ndcX * halfFovTan * aspect;
		let viewDirY = ndcY * halfFovTan;

		// Transform to world space
		var rayDir = forward + right * viewDirX + up * viewDirY;
		rayDir = Vector3.Normalize(rayDir);

		return .(cameraPos, rayDir);
	}

	// ==================== IEntityComponent Implementation ====================

	/// Called when the component is attached to an entity.
	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		// Find the RenderSceneComponent
		if (entity.Scene != null)
		{
			mRenderScene = entity.Scene.GetSceneComponent<RenderSceneComponent>();
			if (mRenderScene != null)
			{
				CreateProxy();
			}
		}
	}

	/// Called when the component is detached from an entity.
	public void OnDetach()
	{
		RemoveProxy();
		mEntity = null;
		mRenderScene = null;
	}

	/// Called each frame to update the component.
	public void OnUpdate(float deltaTime)
	{
		// Update proxy properties if they've changed
		if (mRenderScene != null && mProxyHandle.IsValid)
		{
			if (let proxy = mRenderScene.RenderWorld.GetCameraProxy(mProxyHandle))
			{
				proxy.FieldOfView = FieldOfView;
				proxy.NearPlane = NearPlane;
				proxy.FarPlane = FarPlane;
				proxy.UseReverseZ = UseReverseZ;
				proxy.LayerMask = LayerMask;
				proxy.Priority = Priority;
				proxy.Enabled = Enabled;

				// Check if this should become the main camera
				if (IsMain && !proxy.IsMain)
				{
					mRenderScene.MainCamera = mProxyHandle;
				}
			}
		}
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// Field of view
		result = serializer.Float("fieldOfView", ref FieldOfView);
		if (result != .Ok)
			return result;

		// Near and far planes
		result = serializer.Float("nearPlane", ref NearPlane);
		if (result != .Ok)
			return result;
		result = serializer.Float("farPlane", ref FarPlane);
		if (result != .Ok)
			return result;

		// Priority
		result = serializer.Int32("priority", ref Priority);
		if (result != .Ok)
			return result;

		// Layer mask
		int32 layerMask = (int32)LayerMask;
		result = serializer.Int32("layerMask", ref layerMask);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			LayerMask = (uint32)layerMask;

		// Flags
		int32 flags = (IsMain ? 1 : 0) | (UseReverseZ ? 2 : 0) | (Enabled ? 4 : 0);
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
		{
			IsMain = (flags & 1) != 0;
			UseReverseZ = (flags & 2) != 0;
			Enabled = (flags & 4) != 0;
		}

		// Viewport dimensions
		int32 vpWidth = (int32)mViewportWidth;
		int32 vpHeight = (int32)mViewportHeight;
		result = serializer.Int32("viewportWidth", ref vpWidth);
		if (result != .Ok)
			return result;
		result = serializer.Int32("viewportHeight", ref vpHeight);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
		{
			mViewportWidth = (uint32)vpWidth;
			mViewportHeight = (uint32)vpHeight;
		}

		return .Ok;
	}

	// ==================== Internal ====================

	private void CreateProxy()
	{
		if (mRenderScene == null || mEntity == null)
			return;

		let camera = GetCamera();
		mProxyHandle = mRenderScene.CreateCameraProxy(
			mEntity.Id,
			camera,
			mViewportWidth,
			mViewportHeight,
			IsMain
		);

		// Set additional properties on proxy
		if (mProxyHandle.IsValid)
		{
			if (let proxy = mRenderScene.RenderWorld.GetCameraProxy(mProxyHandle))
			{
				proxy.LayerMask = LayerMask;
				proxy.Priority = Priority;
				proxy.Enabled = Enabled;
			}
		}
	}

	private void RemoveProxy()
	{
		if (mRenderScene != null && mEntity != null)
		{
			mRenderScene.DestroyCameraProxy(mEntity.Id);
		}
		mProxyHandle = .Invalid;
	}
}
