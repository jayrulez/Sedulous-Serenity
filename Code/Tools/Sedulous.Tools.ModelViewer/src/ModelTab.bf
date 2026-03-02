namespace Sedulous.Tools.ModelViewer;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Models;
using Sedulous.Render;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.GUI;
using Sedulous.Tools.AppFramework;
using Sedulous.Tools.Core;

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

	/// The actual GPU mesh bounds (may differ from Model.Bounds due to recentering)
	public BoundingBox MeshBounds = .(.Zero, .Zero);

	/// For skinned meshes: the mesh node's world transform (rotation/scale not baked into vertices)
	/// This transform converts bounds from bind-pose space to world-oriented space.
	public Matrix MeshNodeTransform = .Identity;

	/// Current model position offset (for gizmo manipulation)
	public Vector3 ModelOffset = .Zero;

	/// Per-tab UI elements
	public Grid ContentPanel;           // Container for toolbar + viewport
	public StackPanel Toolbar;
	public ViewportControl Viewport;
	public CheckBox BoundingBoxCheck;

	// Animation toolbar (only for skinned meshes)
	public StackPanel AnimationToolbar;
	public ComboBox AnimationComboBox;
	public Button PlayPauseButton;
	public Button StopButton;
	public Button ResetButton;
	public CheckBox LoopCheck;

	// Scale control
	public Slider ScaleSlider;
	public float ModelScale = 1.0f;

	// Visualization toggles
	public CheckBox GridCheck;
	public CheckBox SkeletonCheck;

	// GPU resources
	public GPUMeshHandle MeshHandle = .Invalid;
	public GPUBoneBufferHandle BoneBufferHandle = .Invalid;
	public List<GPUTextureHandle> TextureHandles = new .() ~ delete _;
	public MeshProxyHandle StaticMeshProxy = .Invalid;
	public SkinnedMeshProxyHandle SkinnedMeshProxy = .Invalid;
	// MaterialResources own the Material objects; MaterialInstances reference them
	public List<Sedulous.Materials.Resources.MaterialResource> MaterialResources = new .() ~ DeleteContainerAndItems!(_);
	public List<MaterialInstance> MaterialInstances = new .() ~ { for (let m in _) m?.ReleaseRef(); delete _; };

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
			.(1.0f, 1.0f, 0.95f), 1.5f);

		FillLight = World.CreatePointLight(.(0, 30, 30), .(0.6f, 0.7f, 1.0f), 1.5f, 60.0f);

		// Set environment
		World.AmbientColor = .(0.1f, 0.1f, 0.15f);
		World.AmbientIntensity = 0.6f;
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
		for (let texHandle in TextureHandles)
		{
			if (texHandle.IsValid)
				renderSystem.ResourceManager.ReleaseTexture(texHandle, renderSystem.FrameNumber);
		}
		TextureHandles.Clear();

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

		// Clear materials (instances first, then resources that own the Material objects)
		for (let mat in MaterialInstances)
			mat?.ReleaseRef();
		MaterialInstances.Clear();
		DeleteContainerAndItems!(MaterialResources);
		MaterialResources = new .();
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

		// Clean up UI elements (ContentPanel owns all child UI as children)
		// Note: ContentPanel must be removed from its parent before calling Destroy
		if (ContentPanel != null)
		{
			// Use deferred deletion if attached to a context, otherwise delete directly
			if (ContentPanel.Context != null)
				ContentPanel.Context.MutationQueue.QueueDelete(ContentPanel);
			else
				delete ContentPanel;
			ContentPanel = null;
			Toolbar = null;
			Viewport = null;
			BoundingBoxCheck = null;
			AnimationToolbar = null;
			AnimationComboBox = null;
			PlayPauseButton = null;
			StopButton = null;
			ResetButton = null;
			ScaleSlider = null;
		}
	}
}
