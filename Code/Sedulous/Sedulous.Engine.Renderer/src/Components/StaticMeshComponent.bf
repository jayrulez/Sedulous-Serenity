namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.Engine.Core;
using Sedulous.Geometry;
using Sedulous.Mathematics;
using Sedulous.Serialization;

/// Entity component that renders a static mesh.
class StaticMeshComponent : IEntityComponent
{
	// GPU mesh handle
	private GPUMeshHandle mGPUMesh = .Invalid;
	private BoundingBox mLocalBounds = .(.Zero, .Zero);

	// Entity and scene references
	private Entity mEntity;
	private RenderSceneComponent mRenderScene;
	private ProxyHandle mProxyHandle = .Invalid;

	/// Material instance handles for each sub-mesh (up to 8).
	public MaterialInstanceHandle[8] MaterialInstances = .(.Invalid, .Invalid, .Invalid, .Invalid, .Invalid, .Invalid, .Invalid, .Invalid);

	/// Legacy material IDs for each sub-mesh (up to 8).
	/// Used when MaterialInstances[i].IsValid == false.
	public uint32[8] MaterialIds;

	/// Number of materials used.
	public uint8 MaterialCount;

	/// Whether this mesh casts shadows.
	public bool CastShadows = true;

	/// Whether this mesh receives shadows.
	public bool ReceiveShadows = true;

	/// Whether the mesh is visible.
	public bool Visible = true;

	/// Gets the local bounding box.
	public BoundingBox LocalBounds => mLocalBounds;

	/// Gets the GPU mesh handle (framework use).
	public GPUMeshHandle GPUMeshHandle => mGPUMesh;

	/// Checks if this component uses material instances (vs legacy material IDs).
	public bool UsesMaterialInstances => MaterialInstances[0].IsValid;

	/// Creates a new MeshRendererComponent.
	public this()
	{
	}

	/// Sets a material instance for a sub-mesh.
	public void SetMaterialInstance(int32 slot, MaterialInstanceHandle instance)
	{
		if (slot >= 0 && slot < 8)
		{
			MaterialInstances[slot] = instance;
			if (slot >= MaterialCount)
				MaterialCount = (uint8)(slot + 1);

			// Sync to proxy
			if (mProxyHandle.IsValid && mRenderScene != null)
			{
				if (let proxy = mRenderScene.RenderWorld.GetMeshProxy(mProxyHandle))
					proxy.SetMaterialInstance(slot, instance);
			}
		}
	}

	/// Gets the material instance for a sub-mesh.
	public MaterialInstanceHandle GetMaterialInstance(int32 slot)
	{
		if (slot >= 0 && slot < 8)
			return MaterialInstances[slot];
		return .Invalid;
	}

	/// Sets the GPU mesh to render (low-level API).
	internal void SetMesh(GPUMeshHandle mesh, BoundingBox bounds)
	{
		mGPUMesh = mesh;
		mLocalBounds = bounds;

		// Update proxy if attached
		if (mEntity != null && mRenderScene != null && mesh.IsValid)
		{
			CreateOrUpdateProxy();
		}
	}

	/// Sets the mesh to render.
	/// Automatically uploads geometry to GPU.
	public void SetMesh(StaticMesh mesh)
	{
		if (mesh == null)
		{
			mGPUMesh = .Invalid;
			mLocalBounds = .(.Zero, .Zero);
			RemoveProxy();
			return;
		}

		// Get RendererService from RenderSceneComponent
		if (mRenderScene?.RendererService?.ResourceManager == null)
		{
			// Not attached yet or no renderer - store bounds only
			mLocalBounds = mesh.GetBounds();
			return;
		}

		// Upload to GPU
		mGPUMesh = mRenderScene.RendererService.ResourceManager.CreateMesh(mesh);
		mLocalBounds = mesh.GetBounds();

		// Update proxy if attached
		if (mEntity != null && mGPUMesh.IsValid)
		{
			CreateOrUpdateProxy();
		}
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
			if (mRenderScene != null && mGPUMesh.IsValid)
			{
				CreateOrUpdateProxy();
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
		// Transform sync is handled by RenderSceneComponent.SyncProxies()
		// Update visibility flag on proxy if changed
		if (mRenderScene != null && mProxyHandle.IsValid)
		{
			if (let proxy = mRenderScene.RenderWorld.GetMeshProxy(mProxyHandle))
			{
				if (Visible)
					proxy.Flags |= .Visible;
				else
					proxy.Flags &= ~.Visible;
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

		// Serialize rendering flags
		int32 flags = (CastShadows ? 1 : 0) | (ReceiveShadows ? 2 : 0) | (Visible ? 4 : 0);
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok)
			return result;

		if (serializer.IsReading)
		{
			CastShadows = (flags & 1) != 0;
			ReceiveShadows = (flags & 2) != 0;
			Visible = (flags & 4) != 0;
		}

		// Serialize material count and IDs
		int32 matCount = (int32)MaterialCount;
		result = serializer.Int32("materialCount", ref matCount);
		if (result != .Ok)
			return result;
		MaterialCount = (uint8)Math.Min(matCount, 8);

		for (int32 i = 0; i < MaterialCount; i++)
		{
			int32 matId = (int32)MaterialIds[i];
			result = serializer.Int32(null, ref matId);
			if (result != .Ok)
				return result;
			if (serializer.IsReading)
				MaterialIds[i] = (uint32)matId;
		}

		// Note: GPU mesh is not serialized - it needs to be set up by the loading code
		// using resource references (e.g., mesh path)

		return .Ok;
	}

	// ==================== Internal ====================

	private void CreateOrUpdateProxy()
	{
		if (mRenderScene == null || mEntity == null)
			return;

		mProxyHandle = mRenderScene.CreateMeshProxy(
			mEntity.Id,
			mGPUMesh,
			mEntity.Transform.WorldMatrix,
			mLocalBounds
		);

		// Copy material data to the proxy
		if (mProxyHandle.IsValid)
		{
			if (let proxy = mRenderScene.RenderWorld.GetMeshProxy(mProxyHandle))
			{
				proxy.MaterialCount = MaterialCount;
				for (int i = 0; i < 8; i++)
				{
					proxy.MaterialInstances[i] = MaterialInstances[i];
					proxy.MaterialIds[i] = MaterialIds[i];
				}
			}
		}
	}

	private void RemoveProxy()
	{
		if (mRenderScene != null && mEntity != null)
		{
			mRenderScene.DestroyMeshProxy(mEntity.Id);
		}
		mProxyHandle = .Invalid;
	}
}
