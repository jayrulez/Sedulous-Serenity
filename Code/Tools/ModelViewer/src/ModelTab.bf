namespace ModelViewer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Models;
using Sedulous.Render;
using Sedulous.Materials;
using Sedulous.Animation;
using Sedulous.Animation.Resources;

/// Represents a single model tab with its own world, resources, and camera state.
class ModelTab
{
	// Identity
	public String Name ~ delete _;
	public String FilePath ~ delete _;

	// Render world (isolated per tab)
	public RenderWorld World;
	public LightProxyHandle SunLight = .Invalid;
	public LightProxyHandle FillLight = .Invalid;

	// Model data
	public Model Model ~ delete _;
	public Skeleton Skeleton ~ delete _;
	public AnimationPlayer Player ~ delete _;
	public List<AnimationClipResource> AnimResources ~ DeleteContainerAndItems!(_);
	public AnimationClip[] Clips ~ delete _;
	public int32 CurrentClip;
	public bool IsSkinnedMesh;

	// GPU resources
	public GPUMeshHandle MeshHandle = .Invalid;
	public GPUBoneBufferHandle BoneBufferHandle = .Invalid;
	public GPUTextureHandle TextureHandle = .Invalid;
	public MeshProxyHandle StaticMeshProxy = .Invalid;
	public SkinnedMeshProxyHandle SkinnedMeshProxy = .Invalid;
	public MaterialInstance Material ~ _?.ReleaseRef();

	// Per-tab camera state
	public OrbitCamera Camera ~ delete _;

	public this(StringView name, StringView filePath)
	{
		Name = new String(name);
		FilePath = new String(filePath);
		Model = new Model();
		Camera = new OrbitCamera();
		AnimResources = new List<AnimationClipResource>();
	}

	/// Creates the render world and default lights for this tab.
	public void CreateWorld(RenderSystem renderSystem)
	{
		World = renderSystem.CreateWorld();

		// Set up default lighting
		SunLight = World.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -1.0f, 0.3f)),
			.(1.0f, 1.0f, 0.95f), 2.5f);

		FillLight = World.CreatePointLight(.(0, 30, 30), .(0.6f, 0.7f, 1.0f), 3.0f, 60.0f);

		// Set environment
		World.AmbientColor = .(0.1f, 0.1f, 0.15f);
		World.AmbientIntensity = 0.5f;
		World.Exposure = 1.0f;
	}

	/// Clears all model resources from this tab.
	public void ClearModel(RenderSystem renderSystem)
	{
		if (renderSystem == null)
			return;

		// Release GPU resources
		if (MeshHandle.IsValid)
		{
			renderSystem.ResourceManager.ReleaseMesh(MeshHandle, renderSystem.FrameNumber);
			MeshHandle = .Invalid;
		}
		if (BoneBufferHandle.IsValid)
		{
			renderSystem.ResourceManager.ReleaseBoneBuffer(BoneBufferHandle, renderSystem.FrameNumber);
			BoneBufferHandle = .Invalid;
		}
		if (TextureHandle.IsValid)
		{
			renderSystem.ResourceManager.ReleaseTexture(TextureHandle, renderSystem.FrameNumber);
			TextureHandle = .Invalid;
		}

		// Remove proxies from world
		if (World != null)
		{
			if (StaticMeshProxy.IsValid)
			{
				World.DestroyMesh(StaticMeshProxy);
				StaticMeshProxy = .Invalid;
			}
			if (SkinnedMeshProxy.IsValid)
			{
				World.DestroySkinnedMesh(SkinnedMeshProxy);
				SkinnedMeshProxy = .Invalid;
			}
		}

		// Clear animation data
		if (Player != null) { delete Player; Player = null; }
		if (Skeleton != null) { delete Skeleton; Skeleton = null; }
		if (AnimResources != null) { DeleteContainerAndItems!(AnimResources); AnimResources = new .(); }
		if (Clips != null) { delete Clips; Clips = null; }
		CurrentClip = 0;

		// Clear material
		if (Material != null) { Material.ReleaseRef(); Material = null; }
	}

	/// Destroys the entire tab including world and all resources.
	public void Destroy(RenderSystem renderSystem)
	{
		// Clear model resources first
		ClearModel(renderSystem);

		// Destroy lights
		if (World != null)
		{
			if (SunLight.IsValid)
				World.DestroyLight(SunLight);
			if (FillLight.IsValid)
				World.DestroyLight(FillLight);
		}

		// Delete the world
		if (World != null)
		{
			delete World;
			World = null;
		}
	}
}
