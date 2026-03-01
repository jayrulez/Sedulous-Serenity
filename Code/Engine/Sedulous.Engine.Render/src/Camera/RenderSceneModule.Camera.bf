namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Render;

/// Camera instance storage and API.
extension RenderSceneModule
{
	// ==================== Camera Instance Storage ====================

	public struct CameraInstanceData
	{
		public EntityId Entity;
		public CameraProxyHandle ProxyHandle = .Invalid;
		public bool Active;
	}

	private List<CameraInstanceData> mCameraInstances = new .() ~ delete _;
	private List<int32> mFreeCameraSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToCameraInstance = new .() ~ delete _;

	public List<CameraInstanceData> CameraInstances => mCameraInstances;

	// ==================== Camera API ====================

	/// Helper: allocates a camera instance slot and sets up the thin component handle.
	private int32 AllocateCameraSlot(EntityId entity, CameraProxyHandle proxyHandle)
	{
		int32 slotIdx;
		if (mFreeCameraSlots.Count > 0)
			slotIdx = mFreeCameraSlots.PopBack();
		else
		{
			slotIdx = (int32)mCameraInstances.Count;
			mCameraInstances.Add(.());
		}

		var instance = ref mCameraInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.ProxyHandle = proxyHandle;
		instance.Active = true;
		mEntityToCameraInstance[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<CameraComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<CameraComponent>(entity, .());
			comp = mScene.GetComponent<CameraComponent>(entity);
		}
		comp.InternalHandle = slotIdx;

		return slotIdx;
	}

	/// Creates a perspective camera for an entity.
	public CameraProxyHandle CreatePerspectiveCamera(EntityId entity, float fov, float aspectRatio, float nearPlane, float farPlane)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let position = worldMatrix.Translation;
		let forward = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
		let up = Vector3.Normalize(.(worldMatrix.M21, worldMatrix.M22, worldMatrix.M23));
		let target = position + forward;

		let handle = mWorld.CreatePerspectiveCamera(position, target, up, fov, aspectRatio, nearPlane, farPlane);
		AllocateCameraSlot(entity, handle);

		return handle;
	}

	/// Creates an orthographic camera for an entity.
	public CameraProxyHandle CreateOrthographicCamera(EntityId entity, float width, float height, float nearPlane, float farPlane)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let position = worldMatrix.Translation;
		let forward = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
		let up = Vector3.Normalize(.(worldMatrix.M21, worldMatrix.M22, worldMatrix.M23));
		let target = position + forward;

		let handle = mWorld.CreateOrthographicCamera(position, target, up, width, height, nearPlane, farPlane);
		AllocateCameraSlot(entity, handle);

		return handle;
	}

	/// Sets this camera as the main camera.
	public void SetMainCamera(EntityId entity)
	{
		if (mEntityToCameraInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mCameraInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld?.SetMainCamera(instance.ProxyHandle);
		}
	}

	/// Updates camera matrices. Call after changing projection parameters.
	public void UpdateCameraMatrices(EntityId entity, bool flipY = false)
	{
		if (mEntityToCameraInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mCameraInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld?.UpdateCameraMatrices(instance.ProxyHandle, flipY);
		}
	}

	/// Gets the camera proxy for direct access.
	public CameraProxy* GetCameraProxy(EntityId entity)
	{
		if (mEntityToCameraInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mCameraInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				return mWorld?.GetCamera(instance.ProxyHandle);
		}
		return null;
	}

	/// Returns whether the entity has a camera component managed by this module.
	public bool HasCamera(EntityId entity)
	{
		return mEntityToCameraInstance.ContainsKey(entity);
	}

	/// Destroys all camera instances (bulk teardown for scene destroy).
	private void DestroyAllCameras()
	{
		for (var instance in ref mCameraInstances)
		{
			if (!instance.Active) continue;
			if (mWorld != null && instance.ProxyHandle.IsValid)
				mWorld.DestroyCamera(instance.ProxyHandle);
			instance.Active = false;
		}
		mCameraInstances.Clear();
		mFreeCameraSlots.Clear();
		mEntityToCameraInstance.Clear();
	}

	/// Syncs camera proxy transform from world matrix.
	private void SyncCameraTransform(EntityId entity, in Matrix worldMatrix)
	{
		if (mEntityToCameraInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mCameraInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
			{
				if (let proxy = mWorld?.GetCamera(instance.ProxyHandle))
				{
					let position = worldMatrix.Translation;
					let forward = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
					let up = Vector3.Normalize(.(worldMatrix.M21, worldMatrix.M22, worldMatrix.M23));
					proxy.SetPositionDirection(position, forward, up);
				}
			}
		}
	}

	/// Destroys the camera for an entity.
	public void DestroyCamera(EntityId entity)
	{
		if (!mEntityToCameraInstance.TryGetValue(entity, var idx))
			return;

		var instance = ref mCameraInstances[idx];
		if (instance.Active)
		{
			if (instance.ProxyHandle.IsValid && mWorld != null)
				mWorld.DestroyCamera(instance.ProxyHandle);
			instance.Active = false;
			mFreeCameraSlots.Add(idx);
		}
		mEntityToCameraInstance.Remove(entity);

		if (var comp = mScene?.GetComponent<CameraComponent>(entity))
			comp.InternalHandle = -1;
	}

	/// Duplicates the camera from src entity to dst entity.
	public void DuplicateCamera(EntityId src, EntityId dst)
	{
		let proxy = GetCameraProxy(src);
		if (proxy == null)
			return;

		switch (proxy.Projection)
		{
		case .Perspective:
			CreatePerspectiveCamera(dst, proxy.FieldOfView, proxy.AspectRatio, proxy.NearPlane, proxy.FarPlane);
		case .Orthographic:
			CreateOrthographicCamera(dst, proxy.OrthoWidth, proxy.OrthoHeight, proxy.NearPlane, proxy.FarPlane);
		}
	}
}
