namespace ModelViewer;

using System;
using System.IO;
using System.Collections;
using Sedulous.AppFramework;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Models.FBX;
using Sedulous.Drawing;
using Sedulous.Drawing.Fonts;
using Sedulous.GUI;
using Sedulous.Render;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Textures;
using Sedulous.Textures.Resources;
using Sedulous.Imaging;
using Tools.Common;

/// Model Viewer Application using Sedulous.Render with multi-tab support
class ModelViewerApp : Application
{
	// Render system (cleaned up in OnCleanup)
	private RenderSystem mRenderSystem;
	private RenderView mView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private GPUSkinningFeature mSkinningFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private OverlayRenderFeature mOverlayFeature;
	private ViewportOutputFeature mOutputFeature;

	// Gizmo
	private TranslateGizmo mGizmo ~ delete _;

	// Tabs
	private List<ModelTab> mTabs ~ DeleteContainerAndItems!(_);
	private int32 mActiveTabIndex = -1;

	// Camera interaction state
	private bool mIsDragging = false;
	private bool mIsFlying = false;
	private bool mIsPanning = false;
	private float mLastMouseX;
	private float mLastMouseY;

	// Gizmo drag state (track start positions since UpdateDrag returns total delta)
	private Vector3 mGizmoDragStartPos;
	private Vector3 mCameraTargetDragStartPos;

	// UI
	private SplitPanel mRootPanel;
	private StackPanel mSidePanel;
	private Grid mViewportPanel;
	private TabControl mTabControl;
	private Grid mViewportContainer; // Container for per-tab content and drop indicator
	private TextBlock mModelInfoLabel;
	private TextBlock mDropIndicator; // Shown when no tabs

	// Icon images for animation controls
	private OwnedImageData mPlayIcon ~ delete _;
	private OwnedImageData mPauseIcon ~ delete _;
	private OwnedImageData mStopIcon ~ delete _;
	private OwnedImageData mResetIcon ~ delete _;
	private OwnedImageData mSkeletonIcon ~ delete _;
	private OwnedImageData mStepBackIcon ~ delete _;
	private OwnedImageData mStepForwardIcon ~ delete _;
	private OwnedImageData mLoopIcon ~ delete _;

	/// Gets the currently active tab, or null if no tabs exist.
	private ModelTab ActiveTab => mActiveTabIndex >= 0 && mActiveTabIndex < (int32)mTabs.Count ? mTabs[mActiveTabIndex] : null;

	public this() : base(.()
		{
			Title = "Model Viewer",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.15f, 0.15f, 0.2f, 1.0f)
		})
	{
		mTabs = new List<ModelTab>();
	}

	protected override bool OnInitialize()
	{
		// Initialize image and model loaders
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();
		Sedulous.Imaging.STB.STBImageLoader.Initialize(); // Required for HDR image loading
		GltfModels.Initialize();
		FbxModels.Initialize();

		// Initialize render system
		let shaderPaths = scope StringView[](scope $"{AssetDirectory}/Render/Shaders");
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(Device, shaderPaths, scope $"{AssetDirectory}/cache/Shaders", .RGBA8Unorm, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return false;
		}

		mView = new RenderView();
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 1000.0f;
		mView.PostProcess.EnableTAA = false;
		mView.PostProcess.EnableBloom = false;
		mView.PostProcess.EnableSSAO = false;

		RegisterFeatures();
		CreateAnimationIcons();

		return true;
	}

	/// Creates the icon images for animation control buttons.
	private void CreateAnimationIcons()
	{
		// Icon size (16x16 pixels, RGBA format)
		const int SIZE = 16;

		// Create play icon (right-pointing triangle)
		{
			uint8[] pixels = new uint8[SIZE * SIZE * 4];
			for (int y = 0; y < SIZE; y++)
			{
				for (int x = 0; x < SIZE; x++)
				{
					int idx = (y * SIZE + x) * 4;
					// Mirror X for correct orientation
					int mx = SIZE - 1 - x;
					float centerY = SIZE / 2.0f;
					float distFromCenter = Math.Abs(y - centerY);
					float triangleX = 2 + distFromCenter * 0.8f;
					bool inside = mx >= triangleX && mx < SIZE - 3;
					uint8 alpha = inside ? 255 : 0;
					pixels[idx + 0] = 220;  // R
					pixels[idx + 1] = 220;  // G
					pixels[idx + 2] = 220;  // B
					pixels[idx + 3] = alpha; // A
				}
			}
			mPlayIcon = new OwnedImageData(SIZE, SIZE, .RGBA8, pixels);
		}

		// Create pause icon (two vertical bars)
		{
			uint8[] pixels = new uint8[SIZE * SIZE * 4];
			for (int y = 0; y < SIZE; y++)
			{
				for (int x = 0; x < SIZE; x++)
				{
					int idx = (y * SIZE + x) * 4;
					// Mirror X for correct orientation
					int mx = SIZE - 1 - x;
					// Two bars
					bool bar1 = mx >= 3 && mx <= 5 && y >= 2 && y <= 13;
					bool bar2 = mx >= 10 && mx <= 12 && y >= 2 && y <= 13;
					uint8 alpha = (bar1 || bar2) ? 255 : 0;
					pixels[idx + 0] = 220;
					pixels[idx + 1] = 220;
					pixels[idx + 2] = 220;
					pixels[idx + 3] = alpha;
				}
			}
			mPauseIcon = new OwnedImageData(SIZE, SIZE, .RGBA8, pixels);
		}

		// Create stop icon (square)
		{
			uint8[] pixels = new uint8[SIZE * SIZE * 4];
			for (int y = 0; y < SIZE; y++)
			{
				for (int x = 0; x < SIZE; x++)
				{
					int idx = (y * SIZE + x) * 4;
					// Square is symmetric, no mirroring needed
					bool inside = x >= 3 && x <= 12 && y >= 3 && y <= 12;
					uint8 alpha = inside ? 255 : 0;
					pixels[idx + 0] = 220;
					pixels[idx + 1] = 220;
					pixels[idx + 2] = 220;
					pixels[idx + 3] = alpha;
				}
			}
			mStopIcon = new OwnedImageData(SIZE, SIZE, .RGBA8, pixels);
		}

		// Create reset icon (left-pointing triangle with bar)
		{
			uint8[] pixels = new uint8[SIZE * SIZE * 4];
			for (int y = 0; y < SIZE; y++)
			{
				for (int x = 0; x < SIZE; x++)
				{
					int idx = (y * SIZE + x) * 4;
					// Mirror X for correct orientation
					int mx = SIZE - 1 - x;
					// Bar on left
					bool bar = mx >= 2 && mx <= 4 && y >= 2 && y <= 13;
					// Triangle pointing left
					float centerY = SIZE / 2.0f;
					float distFromCenter = Math.Abs(y - centerY);
					float triangleX = SIZE - 3 - distFromCenter * 0.8f;
					bool triangle = mx <= triangleX && mx >= 6;
					uint8 alpha = (bar || triangle) ? 255 : 0;
					pixels[idx + 0] = 220;
					pixels[idx + 1] = 220;
					pixels[idx + 2] = 220;
					pixels[idx + 3] = alpha;
				}
			}
			mResetIcon = new OwnedImageData(SIZE, SIZE, .RGBA8, pixels);
		}

		// Create skeleton icon (stick figure bone shape)
		{
			uint8[] pixels = new uint8[SIZE * SIZE * 4];
			for (int y = 0; y < SIZE; y++)
			{
				for (int x = 0; x < SIZE; x++)
				{
					int idx = (y * SIZE + x) * 4;
					// Mirror X for correct orientation (skeleton is mostly symmetric anyway)
					int mx = SIZE - 1 - x;
					// Vertical spine: mx=7-8, y in [1,14]
					bool spine = mx >= 7 && mx <= 8 && y >= 1 && y <= 14;
					// Head (circle at top): distance from (7.5, 2) < 2
					float dx = mx - 7.5f;
					float dy = y - 2.5f;
					bool head = (dx * dx + dy * dy) < 4;
					// Shoulders: y=5, mx in [3,12]
					bool shoulders = y >= 4 && y <= 5 && mx >= 3 && mx <= 12;
					// Hips: y=10, mx in [4,11]
					bool hips = y >= 9 && y <= 10 && mx >= 4 && mx <= 11;
					// Left leg: diagonal from (5,10) to (2,14)
					bool leftLeg = y >= 10 && y <= 14 && Math.Abs(mx - (5 - (y - 10) * 0.75f)) < 1.2f;
					// Right leg: diagonal from (10,10) to (13,14)
					bool rightLeg = y >= 10 && y <= 14 && Math.Abs(mx - (10 + (y - 10) * 0.75f)) < 1.2f;
					// Left arm: diagonal from (5,5) to (2,8)
					bool leftArm = y >= 5 && y <= 8 && Math.Abs(mx - (5 - (y - 5))) < 1.2f;
					// Right arm: diagonal from (10,5) to (13,8)
					bool rightArm = y >= 5 && y <= 8 && Math.Abs(mx - (10 + (y - 5))) < 1.2f;

					bool inside = spine || head || shoulders || hips || leftLeg || rightLeg || leftArm || rightArm;
					uint8 alpha = inside ? 255 : 0;
					pixels[idx + 0] = 220;
					pixels[idx + 1] = 180;  // Slightly yellow tint for bone
					pixels[idx + 2] = 140;
					pixels[idx + 3] = alpha;
				}
			}
			mSkeletonIcon = new OwnedImageData(SIZE, SIZE, .RGBA8, pixels);
		}

		// Create step back icon (bar + left triangle)
		{
			uint8[] pixels = new uint8[SIZE * SIZE * 4];
			for (int y = 0; y < SIZE; y++)
			{
				for (int x = 0; x < SIZE; x++)
				{
					int idx = (y * SIZE + x) * 4;
					// Mirror X for correct orientation
					int mx = SIZE - 1 - x;
					// Bar on left
					bool bar = mx >= 2 && mx <= 4 && y >= 3 && y <= 12;
					// Triangle pointing left
					float centerY = SIZE / 2.0f;
					float distFromCenter = Math.Abs(y - centerY);
					float triangleX = SIZE - 4 - distFromCenter * 0.7f;
					bool triangle = mx <= triangleX && mx >= 6 && y >= 3 && y <= 12;
					uint8 alpha = (bar || triangle) ? 255 : 0;
					pixels[idx + 0] = 220;
					pixels[idx + 1] = 220;
					pixels[idx + 2] = 220;
					pixels[idx + 3] = alpha;
				}
			}
			mStepBackIcon = new OwnedImageData(SIZE, SIZE, .RGBA8, pixels);
		}

		// Create step forward icon (right triangle + bar) - mirror of step back
		// Uses same shape logic as step back but WITHOUT mirroring to get opposite direction
		{
			uint8[] pixels = new uint8[SIZE * SIZE * 4];
			for (int y = 0; y < SIZE; y++)
			{
				for (int x = 0; x < SIZE; x++)
				{
					int idx = (y * SIZE + x) * 4;
					// No mirroring - use x directly (opposite of step back which uses mx)
					// Bar on right: x in [11,13]
					bool bar = x >= 11 && x <= 13 && y >= 3 && y <= 12;
					// Triangle pointing right
					float centerY = SIZE / 2.0f;
					float distFromCenter = Math.Abs(y - centerY);
					float triangleX = SIZE - 4 - distFromCenter * 0.7f;
					bool triangle = x <= triangleX && x >= 6 && y >= 3 && y <= 12;
					uint8 alpha = (bar || triangle) ? 255 : 0;
					pixels[idx + 0] = 220;
					pixels[idx + 1] = 220;
					pixels[idx + 2] = 220;
					pixels[idx + 3] = alpha;
				}
			}
			mStepForwardIcon = new OwnedImageData(SIZE, SIZE, .RGBA8, pixels);
		}

		// Create loop icon (circular arrows)
		{
			uint8[] pixels = new uint8[SIZE * SIZE * 4];
			float centerX = SIZE / 2.0f;
			float centerY = SIZE / 2.0f;
			float outerR = 6.0f;
			float innerR = 3.5f;

			for (int y = 0; y < SIZE; y++)
			{
				for (int x = 0; x < SIZE; x++)
				{
					int idx = (y * SIZE + x) * 4;
					float dx = x - centerX;
					float dy = y - centerY;
					float dist = Math.Sqrt(dx * dx + dy * dy);

					// Ring (circular path)
					bool ring = dist >= innerR && dist <= outerR;

					// Cut gaps for arrow heads (at top-right and bottom-left)
					float angle = Math.Atan2(dy, dx);
					bool topRightGap = angle > -0.8f && angle < 0.3f;
					bool bottomLeftGap = angle > 2.3f || angle < -2.8f;
					ring = ring && !topRightGap && !bottomLeftGap;

					// Arrow head at top-right (pointing clockwise/down-right)
					bool arrow1 = x >= 10 && x <= 14 && y >= 3 && y <= 7 &&
						(Math.Abs((x - 12) + (y - 5)) < 2.0f || Math.Abs((x - 12) - (y - 5)) < 2.0f) &&
						(x + y) >= 15;

					// Arrow head at bottom-left (pointing clockwise/up-left)
					bool arrow2 = x >= 1 && x <= 5 && y >= 8 && y <= 12 &&
						(Math.Abs((x - 3) + (y - 10)) < 2.0f || Math.Abs((x - 3) - (y - 10)) < 2.0f) &&
						(x + y) <= 15;

					bool inside = ring || arrow1 || arrow2;
					uint8 alpha = inside ? 255 : 0;
					pixels[idx + 0] = 220;
					pixels[idx + 1] = 220;
					pixels[idx + 2] = 220;
					pixels[idx + 3] = alpha;
				}
			}
			mLoopIcon = new OwnedImageData(SIZE, SIZE, .RGBA8, pixels);
		}
	}

	private void RegisterFeatures()
	{
		// GPU skinning for skeletal meshes (must run before depth prepass)
		mSkinningFeature = new GPUSkinningFeature();
		mRenderSystem.RegisterFeature(mSkinningFeature);

		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		// Debug rendering for gizmos
		mOverlayFeature = new OverlayRenderFeature();
		mRenderSystem.RegisterFeature(mOverlayFeature);

		// Custom output feature for viewport rendering
		mOutputFeature = new ViewportOutputFeature();
		mRenderSystem.RegisterFeature(mOutputFeature);

		// Initialize gizmo
		mGizmo = new TranslateGizmo();
		mGizmo.Size = 1.0f;
	}

	/// Loads an HDRI environment map into a tab's world for IBL reflections.
	private void LoadHDRIEnvironment(ModelTab tab)
	{
		let hdrPath = scope $"{AssetDirectory}/Render/textures/environment/BlueSky.hdr";
		if (ImageLoaderFactory.LoadImage(hdrPath) case .Ok(var image))
		{
			defer delete image;
			let texData = TextureData.FromImage(image);
			if (mSkyFeature.SetEnvironmentMapEquirect(texData) case .Ok)
				Console.WriteLine("  HDRI environment loaded ({}x{})", image.Width, image.Height);
			else
				Console.WriteLine("  WARNING: Failed to set HDRI environment map");
		}
		else
		{
			Console.WriteLine("  WARNING: Failed to load HDR image: {}", hdrPath);
		}

		// Adjust lighting for HDRI (IBL provides ambient lighting)
		tab.World.AmbientIntensity = 0.5f;
		tab.World.Exposure = 0.5f;
	}

	/// Loads a model and creates a new tab for it.
	public void LoadModel(StringView path)
	{
		// Extract model name from path
		String modelName = new String();
		let lastSlash = Math.Max(path.LastIndexOf('/'), path.LastIndexOf('\\'));
		if (lastSlash >= 0 && lastSlash < path.Length - 1)
			modelName.Set(path.Substring(lastSlash + 1));
		else
			modelName.Set(path);

		// Create new tab
		let tab = new ModelTab(modelName, path);
		delete modelName;

		// Wait for GPU to finish any pending work before creating new resources
		Device.WaitIdle();

		// Create world for this tab and set it active during setup
		tab.CreateWorld(mRenderSystem);
		mRenderSystem.SetActiveWorld(tab.World);

		// Load HDRI environment map for IBL reflections
		LoadHDRIEnvironment(tab);

		// Load model into tab
		let result = ModelLoaderFactory.LoadModel(path, tab.Model);
		if (result != .Ok)
		{
			Console.WriteLine(scope $"Failed to load model: {path}");
			tab.Destroy(mRenderSystem);
			delete tab;
			return;
		}

		Console.WriteLine(scope $"Loaded model: {path}");
		Console.WriteLine(scope $"  Meshes: {tab.Model.Meshes.Count}");
		Console.WriteLine(scope $"  Materials: {tab.Model.Materials.Count}");
		Console.WriteLine(scope $"  Bones: {tab.Model.Bones.Count}");

		// Calculate model bounds for camera fitting
		tab.Model.CalculateBounds();

		// Get base path for texture loading
		let basePath = scope String();
		let lastSep = Math.Max(path.LastIndexOf('/'), path.LastIndexOf('\\'));
		if (lastSep >= 0)
			basePath.Set(path.Substring(0, lastSep));

		// Use ModelImporter for conversion
		let importOptions = new ModelImportOptions();
		importOptions.BasePath.Set(basePath);
		importOptions.RecenterMeshes = false; // Place model at origin

		// Determine if skinned or static
		tab.IsSkinnedMesh = tab.Model.Bones.Count > 0 && tab.Model.Skins.Count > 0;
		importOptions.Flags = tab.IsSkinnedMesh
			? (.SkinnedMeshes | .Skeletons | .Animations | .Textures | .Materials)
			: (.Meshes | .Textures | .Materials);

		let importer = scope ModelImporter(importOptions);
		let importResult = importer.Import(tab.Model);
		defer delete importResult;

		if (!importResult.Success)
		{
			Console.WriteLine("  Import failed:");
			for (let err in importResult.Errors)
				Console.WriteLine(scope $"    {err}");
			tab.Destroy(mRenderSystem);
			delete tab;
			return;
		}

		// Upload and setup based on mesh type
		if (tab.IsSkinnedMesh && importResult.SkinnedMeshes.Count > 0)
		{
			// For skinned meshes, the mesh node's transform (rotation/scale) is NOT baked into
			// vertex data (unlike static meshes) because doing so would break skinning math.
			// However, the bounds are calculated from these untransformed vertices, so they
			// won't match the rendered orientation. Common case: FBX files with Z-up to Y-up
			// rotation on the mesh node. We compute the mesh node's world transform and apply
			// it to the bounds so they align with the rendered model.
			let bindPoseBounds = importResult.SkinnedMeshes[0].Mesh.Bounds;
			tab.MeshNodeTransform = ComputeMeshNodeWorldTransform(tab.Model, 0);
			tab.MeshBounds = TransformBoundingBox(bindPoseBounds, tab.MeshNodeTransform);

			SetupSkinnedMesh(tab, importResult);
		}
		else if (importResult.StaticMeshes.Count > 0)
		{
			tab.MeshBounds = importResult.StaticMeshes[0].Mesh.GetBounds();
			SetupStaticMesh(tab, importResult);
		}

		// Load textures and materials from import result
		LoadTexturesAndMaterials(tab, importResult, basePath);

		// Fit camera to mesh bounds (uses recentered bounds from import)
		tab.Camera.FitToModel(tab.MeshBounds);

		// Add tab to list and UI
		mTabs.Add(tab);
		AddTabToUI(tab);

		// Switch to new tab
		SwitchToTab((int32)mTabs.Count - 1);
	}

	private void SetupStaticMesh(ModelTab tab, ModelImportResult importResult)
	{
		let resource = importResult.TakeStaticMesh(0);
		defer delete resource;

		Console.WriteLine(scope $"  SetupStaticMesh: vertices={resource.Mesh.Vertices.VertexCount}, indices={resource.Mesh.Indices.IndexCount}");
		Console.WriteLine(scope $"  Mesh bounds: {resource.Mesh.GetBounds().Min} to {resource.Mesh.GetBounds().Max}");

		if (mRenderSystem.ResourceManager.UploadMesh(resource.Mesh) case .Ok(let handle))
		{
			tab.MeshHandle = handle;
			Console.WriteLine(scope $"  Mesh uploaded: handle valid={handle.IsValid}");

			tab.StaticMeshProxy = tab.World.CreateMesh();
			Console.WriteLine(scope $"  Proxy created: valid={tab.StaticMeshProxy.IsValid}");

			if (let proxy = tab.World.GetMesh(tab.StaticMeshProxy))
			{
				proxy.MeshHandle = tab.MeshHandle;
				let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
				Console.WriteLine(scope $"  Default material: {defaultMat != null}");
				proxy.Materials[0] = defaultMat;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(resource.Mesh.GetBounds());
				proxy.SetTransformImmediate(.Identity);
				proxy.Flags = .DefaultOpaque;
			}
		}
		else
		{
			Console.WriteLine("  ERROR: Failed to upload mesh!");
		}
	}

	private void SetupSkinnedMesh(ModelTab tab, ModelImportResult importResult)
	{
		// Build skeleton
		if (importResult.Skeletons.Count > 0)
			BuildSkeleton(tab, importResult.Skeletons[0].Skeleton);

		// Extract animations
		ExtractAnimationsFromModel(tab);

		// Upload mesh
		let resource = importResult.TakeSkinnedMesh(0);
		defer delete resource;

		Console.WriteLine(scope $"  SetupSkinnedMesh: vertices={resource.Mesh.VertexCount}, indices={resource.Mesh.IndexCount}");
		Console.WriteLine(scope $"  Mesh bounds: {resource.Mesh.Bounds.Min} to {resource.Mesh.Bounds.Max}");

		if (mRenderSystem.ResourceManager.UploadMesh(resource.Mesh) case .Ok(let handle))
		{
			tab.MeshHandle = handle;
			Console.WriteLine(scope $"  Mesh uploaded: handle valid={handle.IsValid}");

			let boneCount = (uint16)(tab.Skeleton?.BoneCount ?? 0);
			Console.WriteLine(scope $"  Bone count: {boneCount}");
			if (boneCount > 0)
			{
				if (mRenderSystem.ResourceManager.CreateBoneBuffer(boneCount) case .Ok(let boneHandle))
				{
					tab.BoneBufferHandle = boneHandle;
					Console.WriteLine(scope $"  Bone buffer created: valid={boneHandle.IsValid}");
				}
				else
					Console.WriteLine("  ERROR: Failed to create bone buffer!");
			}

			tab.SkinnedMeshProxy = tab.World.CreateSkinnedMesh();
			Console.WriteLine(scope $"  Proxy created: valid={tab.SkinnedMeshProxy.IsValid}");

			if (let proxy = tab.World.GetSkinnedMesh(tab.SkinnedMeshProxy))
			{
				proxy.MeshHandle = tab.MeshHandle;
				proxy.BoneBufferHandle = tab.BoneBufferHandle;
				let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
				Console.WriteLine(scope $"  Default material: {defaultMat != null}");
				proxy.Materials[0] = defaultMat;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(resource.Mesh.Bounds);
				proxy.BoneCount = boneCount;
				proxy.SetTransformImmediate(.Identity);
				proxy.Flags = .DefaultOpaque;
			}
			else
				Console.WriteLine("  ERROR: Could not get proxy!");

			// Play first animation (looping defaults to off)
			if (tab.Clips != null && tab.Clips.Count > 0 && tab.Player != null)
			{
				tab.Clips[0].IsLooping = false;
				tab.Player.Play(tab.Clips[0]);
				Console.WriteLine(scope $"  Playing: {tab.Clips[0].Name}");
			}
		}
	}

	private void BuildSkeleton(ModelTab tab, Skeleton src)
	{
		if (src == null) return;

		let boneCount = src.BoneCount;
		tab.Skeleton = new Skeleton(boneCount);

		for (int32 j = 0; j < boneCount; j++)
		{
			let srcBone = src.Bones[j];
			let dstBone = tab.Skeleton.Bones[j];
			dstBone.Name.Set(srcBone.Name);
			dstBone.Index = srcBone.Index;
			dstBone.ParentIndex = srcBone.ParentIndex;
			dstBone.LocalBindPose = srcBone.LocalBindPose;
			dstBone.InverseBindPose = srcBone.InverseBindPose;
			dstBone.RootCorrection = srcBone.RootCorrection;
		}

		tab.Skeleton.BuildNameMap();
		tab.Skeleton.FindRootBones();
		tab.Skeleton.BuildChildIndices();
		tab.Player = new Sedulous.Animation.AnimationPlayer(tab.Skeleton);
	}

	/// Computes the world transform for the node that references the given mesh index.
	/// This captures rotation/scale that's not baked into skinned mesh vertices.
	private Matrix ComputeMeshNodeWorldTransform(Model model, int32 meshIndex)
	{
		// Find the first node that references this mesh
		int32 nodeIndex = -1;
		for (let bone in model.Bones)
		{
			if (bone.MeshIndex == meshIndex)
			{
				nodeIndex = bone.Index;
				break;
			}
		}

		if (nodeIndex < 0)
			return .Identity;

		// Walk up the parent chain, accumulating transforms
		Matrix worldTransform = .Identity;
		int32 current = nodeIndex;
		while (current >= 0 && current < model.Bones.Count)
		{
			let bone = model.Bones[current];
			bone.UpdateLocalTransform();
			worldTransform = worldTransform * bone.LocalTransform;
			current = bone.ParentIndex;
		}

		return worldTransform;
	}

	/// Transforms an AABB by a matrix, returning a new AABB that contains all transformed corners.
	private BoundingBox TransformBoundingBox(BoundingBox bounds, Matrix transform)
	{
		// Transform all 8 corners of the bounding box
		Vector3[8] corners = .(
			.(bounds.Min.X, bounds.Min.Y, bounds.Min.Z),
			.(bounds.Max.X, bounds.Min.Y, bounds.Min.Z),
			.(bounds.Min.X, bounds.Max.Y, bounds.Min.Z),
			.(bounds.Max.X, bounds.Max.Y, bounds.Min.Z),
			.(bounds.Min.X, bounds.Min.Y, bounds.Max.Z),
			.(bounds.Max.X, bounds.Min.Y, bounds.Max.Z),
			.(bounds.Min.X, bounds.Max.Y, bounds.Max.Z),
			.(bounds.Max.X, bounds.Max.Y, bounds.Max.Z)
		);

		// Transform first corner to initialize min/max
		var newMin = Vector3.Transform(corners[0], transform);
		var newMax = newMin;

		// Transform remaining corners and expand bounds
		for (int i = 1; i < 8; i++)
		{
			let transformed = Vector3.Transform(corners[i], transform);
			newMin = Vector3.Min(newMin, transformed);
			newMax = Vector3.Max(newMax, transformed);
		}

		return .(newMin, newMax);
	}

	private void ExtractAnimationsFromModel(ModelTab tab)
	{
		if (tab.Model == null || tab.Model.Animations.Count == 0 || tab.Model.Skins.Count == 0)
		{
			tab.Clips = new AnimationClip[0];
			return;
		}

		let skin = tab.Model.Skins[0];

		// Use the skeleton converter's mapping which includes non-joint ancestor nodes.
		// This preserves animation channels on ancestor nodes (e.g. root motion on the
		// Armature node) that would otherwise be silently dropped.
		let nodeToBone = Sedulous.Geometry.Tooling.SkeletonConverter.CreateNodeToBoneMapping(tab.Model, skin);
		if (nodeToBone == null)
		{
			tab.Clips = new AnimationClip[0];
			return;
		}
		defer delete nodeToBone;

		for (int i = 0; i < tab.Model.Animations.Count; i++)
		{
			let modelAnim = tab.Model.Animations[i];
			let clip = new AnimationClip(modelAnim.Name, modelAnim.Duration, false);

			for (let channel in modelAnim.Channels)
			{
				let nodeIdx = channel.TargetBone;
				if (nodeIdx < 0 || nodeIdx >= nodeToBone.Count)
					continue;

				let boneIdx = nodeToBone[nodeIdx];
				if (boneIdx < 0)
					continue;

				let interp = ConvertInterpolation(channel.Interpolation);

				switch (channel.Path)
				{
				case .Translation:
					let track = clip.GetOrCreatePositionTrack(boneIdx);
					track.Interpolation = interp;
					for (let kf in channel.Keyframes)
						track.AddKeyframe(kf.Time, Vector3(kf.Value.X, kf.Value.Y, kf.Value.Z));
				case .Rotation:
					let track = clip.GetOrCreateRotationTrack(boneIdx);
					track.Interpolation = interp;
					for (let kf in channel.Keyframes)
						track.AddKeyframe(kf.Time, Quaternion(kf.Value.X, kf.Value.Y, kf.Value.Z, kf.Value.W));
				case .Scale:
					let track = clip.GetOrCreateScaleTrack(boneIdx);
					track.Interpolation = interp;
					for (let kf in channel.Keyframes)
						track.AddKeyframe(kf.Time, Vector3(kf.Value.X, kf.Value.Y, kf.Value.Z));
				case .Weights:
					continue;
				}
			}

			clip.SortAllKeyframes();
			clip.ComputeDuration();

			let animRes = new AnimationClipResource(clip, true);
			tab.AnimResources.Add(animRes);
		}

		tab.Clips = new AnimationClip[tab.AnimResources.Count];
		for (int i = 0; i < tab.AnimResources.Count; i++)
			tab.Clips[i] = tab.AnimResources[i].Clip;
	}

	private static InterpolationMode ConvertInterpolation(AnimationInterpolation interp)
	{
		switch (interp)
		{
		case .Step: return .Step;
		case .Linear: return .Linear;
		case .CubicSpline: return .CubicSpline;
		}
	}

	private static AddressMode SamplerAddressModeToRHI(SamplerAddressMode mode)
	{
		switch (mode)
		{
		case .Repeat:       return .Repeat;
		case .MirrorRepeat: return .MirrorRepeat;
		case .ClampToEdge:  return .ClampToEdge;
		case .ClampToBorder: return .ClampToBorder;
		}
	}

	/// Converts SamplerMinFilter to RHI FilterMode for min and mipmap filters.
	private static (FilterMode minFilter, FilterMode mipmapFilter) MinFilterToRHI(SamplerMinFilter filter)
	{
		switch (filter)
		{
		case .Nearest:              return (.Nearest, .Nearest);
		case .Linear:               return (.Linear, .Nearest);
		case .NearestMipmapNearest: return (.Nearest, .Nearest);
		case .LinearMipmapNearest:  return (.Linear, .Nearest);
		case .NearestMipmapLinear:  return (.Nearest, .Linear);
		case .LinearMipmapLinear:   return (.Linear, .Linear);
		}
	}

	private static FilterMode MagFilterToRHI(SamplerMagFilter filter)
	{
		switch (filter)
		{
		case .Nearest: return .Nearest;
		case .Linear:  return .Linear;
		}
	}

	private void LoadTexturesAndMaterials(ModelTab tab, ModelImportResult importResult, StringView basePath)
	{
		Console.WriteLine($"[ModelViewer] Loading {importResult.Textures.Count} textures, {importResult.Materials.Count} materials");

		// Upload all textures from the import result
		for (int t = 0; t < importResult.Textures.Count; t++)
		{
			let texRes = importResult.Textures[t];
			if (texRes.Image != null)
			{
				let texData = TextureData.FromImage(texRes.Image);
				if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let handle))
				{
					Console.WriteLine($"[ModelViewer]   Texture[{t}] \"{texRes.Name}\": uploaded OK (image {texRes.Image.Width}x{texRes.Image.Height} fmt={texRes.Image.Format})");
					tab.TextureHandles.Add(handle);
				}
				else
				{
					Console.WriteLine($"[ModelViewer]   Texture[{t}] \"{texRes.Name}\": UPLOAD FAILED");
					tab.TextureHandles.Add(.Invalid); // Keep index alignment
				}
			}
			else
			{
				Console.WriteLine($"[ModelViewer]   Texture[{t}] \"{texRes.Name}\": no image data");
				tab.TextureHandles.Add(.Invalid);
			}
		}

		// Create MaterialInstances from all imported materials
		let materialSystem = mRenderSystem.MaterialSystem;
		if (materialSystem == null)
			return;

		// Take ownership of materials from import result (move them to tab)
		for (int m = 0; m < importResult.Materials.Count; m++)
		{
			let matRes = importResult.Materials[m];
			let material = matRes.Material;
			if (material == null)
			{
				Console.WriteLine($"[ModelViewer]   Material[{m}]: null material, skipping");
				tab.MaterialInstances.Add(null);
				continue;
			}

			Console.WriteLine($"[ModelViewer]   Material[{m}] \"{matRes.Name}\": shader=\"{material.ShaderName}\" texRefs={matRes.TextureRefs.Count}");

			// Create instance from the imported material
			let instance = new MaterialInstance(material);

			// Resolve texture references
			for (var kv in matRes.TextureRefs)
			{
				let slot = kv.key;
				let texRef = kv.value;

				if (texRef.Path == null)
				{
					Console.WriteLine($"[ModelViewer]     Slot \"{slot}\": null path, skipping");
					continue;
				}

				// Find the texture by matching path/name in importResult.Textures
				bool found = false;
				for (int i = 0; i < importResult.Textures.Count; i++)
				{
					let texRes = importResult.Textures[i];
					// Match by name or check if path contains the texture name
					bool matches = (texRes.Name == texRef.Path) ||
						(texRes.Name.Length > 0 && texRef.Path.Contains(texRes.Name));
					if (matches)
					{
						if (i < tab.TextureHandles.Count && tab.TextureHandles[i].IsValid)
						{
							if (let texView = mRenderSystem.ResourceManager.GetTextureView(tab.TextureHandles[i]))
							{
								instance.SetTexture(slot, texView);
								Console.WriteLine($"[ModelViewer]     Slot \"{slot}\": matched texture[{i}] \"{texRes.Name}\" -> BOUND");
							}
							else
								Console.WriteLine($"[ModelViewer]     Slot \"{slot}\": matched texture[{i}] \"{texRes.Name}\" -> NO VIEW");
						}
						else
							Console.WriteLine($"[ModelViewer]     Slot \"{slot}\": matched texture[{i}] \"{texRes.Name}\" -> INVALID HANDLE");
						found = true;
						break;
					}
				}

				if (!found)
					Console.WriteLine($"[ModelViewer]     Slot \"{slot}\": NO MATCH for path \"{texRef.Path}\" (searched {importResult.Textures.Count} textures)");
			}

			// Apply sampler settings from material resource
			let addressU = SamplerAddressModeToRHI(matRes.WrapU);
			let addressV = SamplerAddressModeToRHI(matRes.WrapV);
			let (minFilter, mipmapFilter) = MinFilterToRHI(matRes.MinFilter);
			let magFilter = MagFilterToRHI(matRes.MagFilter);
			let sampler = materialSystem.GetOrCreateSampler(addressU, addressV, minFilter, magFilter, mipmapFilter);
			instance.SetSampler("MainSampler", sampler);

			tab.MaterialInstances.Add(instance);
		}

		// Move MaterialResources from import result to tab (tab takes ownership)
		for (let matRes in importResult.Materials)
			tab.MaterialResources.Add(matRes);
		importResult.Materials.Clear(); // Clear without deleting - tab now owns them

		// If no materials were imported, create a default one
		if (tab.MaterialInstances.Count == 0)
		{
			let baseMat = materialSystem.DefaultMaterial;
			if (baseMat != null)
			{
				let instance = new MaterialInstance(baseMat);
				instance.SetColor("BaseColor", .(1, 1, 1, 1));
				instance.SetFloat("Metallic", 0.0f);
				instance.SetFloat("Roughness", 0.5f);
				tab.MaterialInstances.Add(instance);
			}
		}

		// Assign materials to proxies
		AssignMaterialsToProxy(tab);
	}

	private void AssignMaterialsToProxy(ModelTab tab)
	{
		let materialCount = Math.Min(tab.MaterialInstances.Count, RenderConfig.MaxMaterialsPerMesh);

		if (tab.StaticMeshProxy.IsValid)
		{
			if (let proxy = tab.World.GetMesh(tab.StaticMeshProxy))
			{
				for (int32 i = 0; i < materialCount; i++)
					proxy.Materials[i] = tab.MaterialInstances[i];
				proxy.MaterialCount = (int32)materialCount;
			}
		}
		if (tab.SkinnedMeshProxy.IsValid)
		{
			if (let proxy = tab.World.GetSkinnedMesh(tab.SkinnedMeshProxy))
			{
				for (int32 i = 0; i < materialCount; i++)
					proxy.Materials[i] = tab.MaterialInstances[i];
				proxy.MaterialCount = (int32)materialCount;
			}
		}
	}

	private void AddTabToUI(ModelTab tab)
	{
		if (mTabControl == null || mViewportContainer == null)
			return;

		let tabItem = mTabControl.AddTab(tab.Name);
		tabItem.IsCloseable = true;

		// Subscribe to close event
		tabItem.CloseRequested.Subscribe(new [&] (item) =>
			{
				let index = (int32)item.Index;
				if (index >= 0 && index < (int32)mTabs.Count)
					CloseTab(index, false);
			});

		// Create per-tab content panel (Grid with toolbar + viewport + animation toolbar)
		tab.ContentPanel = new Grid();
		tab.ContentPanel.RowDefinitions.Add(new .() { Height = .Auto }); // Row 0: Top Toolbar
		tab.ContentPanel.RowDefinitions.Add(new .() { Height = .Star }); // Row 1: Viewport
		tab.ContentPanel.RowDefinitions.Add(new .() { Height = .Auto }); // Row 2: Animation Toolbar (skinned only)
		tab.ContentPanel.ColumnDefinitions.Add(new .() { Width = .Star });
		tab.ContentPanel.Visibility = .Collapsed; // Hidden until switched to
		mViewportContainer.AddChild(tab.ContentPanel);

		// Create per-tab toolbar (row 0)
		tab.Toolbar = new StackPanel();
		tab.Toolbar.Orientation = .Horizontal;
		tab.Toolbar.Background = Color(45, 45, 55, 255);
		tab.Toolbar.Padding = .(4, 2, 4, 2);
		GridProperties.SetRow(tab.Toolbar, 0);
		tab.ContentPanel.AddChild(tab.Toolbar);

		// Bounding box checkbox
		tab.BoundingBoxCheck = new CheckBox("Bounds");
		tab.BoundingBoxCheck.Margin = .(0, 0, 8, 0);
		tab.BoundingBoxCheck.VerticalAlignment = .Center;
		tab.Toolbar.AddChild(tab.BoundingBoxCheck);

		// Grid checkbox
		tab.GridCheck = new CheckBox("Grid");
		tab.GridCheck.Margin = .(0, 0, 8, 0);
		tab.GridCheck.VerticalAlignment = .Center;
		tab.GridCheck.IsChecked = true; // Default on
		tab.Toolbar.AddChild(tab.GridCheck);

		// Focus camera button
		let focusButton = new Button("Focus");
		focusButton.Padding = .(8, 2, 8, 2);
		focusButton.Margin = .(0, 0, 8, 0);
		focusButton.VerticalAlignment = .Center;
		focusButton.Click.Subscribe(new [&] (btn) =>
			{
				FocusCameraOnModel();
			});
		tab.Toolbar.AddChild(focusButton);

		// Separator before scale
		let scaleSep = new Separator(.Vertical);
		scaleSep.Height = 18;
		scaleSep.Margin = .(4, 0, 4, 0);
		tab.Toolbar.AddChild(scaleSep);

		// Scale label
		let scaleLabel = new Label("Scale:");
		scaleLabel.VerticalAlignment = .Center;
		scaleLabel.Margin = .(0, 0, 4, 0);
		tab.Toolbar.AddChild(scaleLabel);

		// Scale slider
		tab.ScaleSlider = new Slider();
		tab.ScaleSlider.Width = 100;
		tab.ScaleSlider.Minimum = 0.1f;
		tab.ScaleSlider.Maximum = 10.0f;
		tab.ScaleSlider.Value = 1.0f;
		tab.ScaleSlider.VerticalAlignment = .Center;
		tab.ScaleSlider.TooltipText = "Model scale (0.1x - 10x)";
		tab.Toolbar.AddChild(tab.ScaleSlider);

		// Scale value label
		let scaleValueLabel = new Label("1.0x");
		scaleValueLabel.Width = 35;
		scaleValueLabel.VerticalAlignment = .Center;
		scaleValueLabel.Margin = .(4, 0, 0, 0);
		tab.Toolbar.AddChild(scaleValueLabel);

		// Subscribe to scale changes
		tab.ScaleSlider.ValueChanged.Subscribe(new (slider, value) =>
			{
				tab.ModelScale = value;
				scaleValueLabel.ContentText = scope:: $"{value:F1}x";
				UpdateModelTransform(tab);
			});

		// Create per-tab viewport (row 1)
		tab.Viewport = new ViewportControl();
		tab.Viewport.Initialize(Device, mDrawingRenderer);
		tab.Viewport.Background = Color(40, 40, 50, 255);
		tab.Viewport.HorizontalAlignment = .Stretch;
		tab.Viewport.VerticalAlignment = .Stretch;
		GridProperties.SetRow(tab.Viewport, 1);
		tab.ContentPanel.AddChild(tab.Viewport);

		// Create animation toolbar for skinned meshes (row 2)
		if (tab.IsSkinnedMesh && tab.Clips != null && tab.Clips.Count > 0)
		{
			CreateAnimationToolbar(tab);
		}

		// Update visibility
		UpdateEmptyState();
	}

	/// Creates the animation toolbar for skinned meshes.
	private void CreateAnimationToolbar(ModelTab tab)
	{
		tab.AnimationToolbar = new StackPanel();
		tab.AnimationToolbar.Orientation = .Horizontal;
		tab.AnimationToolbar.Background = Color(40, 45, 50, 255);
		tab.AnimationToolbar.Padding = .(4, 2, 4, 2);
		tab.AnimationToolbar.Spacing = 8;
		GridProperties.SetRow(tab.AnimationToolbar, 2);
		tab.ContentPanel.AddChild(tab.AnimationToolbar);

		// Animation label
		let animLabel = new Label("Animation:");
		animLabel.VerticalAlignment = .Center;
		tab.AnimationToolbar.AddChild(animLabel);

		// Animation ComboBox - measure text to determine width
		tab.AnimationComboBox = new ComboBox();
		tab.AnimationComboBox.VerticalAlignment = .Center;

		// Calculate width based on longest animation name
		float maxTextWidth = 100;  // Minimum width
		if (mGUIContext != null)
		{
			if (mGUIContext.GetService<IFontService>() case .Ok(let fontService))
			{
				let cachedFont = fontService.GetFont(12);  // Default font size
				if (cachedFont != null)
				{
					for (let clip in tab.Clips)
					{
						let textWidth = cachedFont.Font.MeasureString(clip.Name);
						maxTextWidth = Math.Max(maxTextWidth, textWidth);
					}
				}
			}
		}
		// Add padding for dropdown arrow and margins
		tab.AnimationComboBox.Width = maxTextWidth + 40;

		for (let clip in tab.Clips)
			tab.AnimationComboBox.AddText(clip.Name);
		tab.AnimationComboBox.SelectedIndex = 0;
		tab.AnimationComboBox.SelectionChanged.Subscribe(new (cb) =>
			{
				OnAnimationSelected(tab, (int32)cb.SelectedIndex);
			});
		tab.AnimationToolbar.AddChild(tab.AnimationComboBox);

		// Play/Pause button
		tab.PlayPauseButton = CreateImageButton(mPlayIcon, "Play/Pause animation");
		tab.PlayPauseButton.Click.Subscribe(new (btn) => OnPlayPause(tab));
		tab.AnimationToolbar.AddChild(tab.PlayPauseButton);

		// Stop button
		tab.StopButton = CreateImageButton(mStopIcon, "Stop animation");
		tab.StopButton.Click.Subscribe(new (btn) => OnStop(tab));
		tab.AnimationToolbar.AddChild(tab.StopButton);

		// Reset button
		tab.ResetButton = CreateImageButton(mResetIcon, "Reset to beginning");
		tab.ResetButton.Click.Subscribe(new (btn) => OnReset(tab));
		tab.AnimationToolbar.AddChild(tab.ResetButton);

		// Step back button
		let stepBackBtn = CreateImageButton(mStepBackIcon, "Step back one frame");
		stepBackBtn.Click.Subscribe(new (btn) => OnStepBack(tab));
		tab.AnimationToolbar.AddChild(stepBackBtn);

		// Step forward button
		let stepForwardBtn = CreateImageButton(mStepForwardIcon, "Step forward one frame");
		stepForwardBtn.Click.Subscribe(new (btn) => OnStepForward(tab));
		tab.AnimationToolbar.AddChild(stepForwardBtn);

		// Loop toggle checkbox
		tab.LoopCheck = new CheckBox();
		let loopImg = new Sedulous.GUI.Image(mLoopIcon);
		loopImg.Stretch = .None;
		tab.LoopCheck.Content = loopImg;
		tab.LoopCheck.VerticalAlignment = .Center;
		tab.LoopCheck.IsChecked = false; // Default off
		tab.LoopCheck.TooltipText = "Loop animation";
		tab.LoopCheck.Checked.Subscribe(new (cb, isChecked) => OnLoopToggled(tab, isChecked));
		tab.AnimationToolbar.AddChild(tab.LoopCheck);

		// Separator
		let sep = new Separator(.Vertical);
		sep.Height = 18;
		sep.Margin = .(4, 0, 4, 0);
		tab.AnimationToolbar.AddChild(sep);

		// Skeleton visualization checkbox
		tab.SkeletonCheck = new CheckBox();
		let skelImg = new Sedulous.GUI.Image(mSkeletonIcon);
		skelImg.Stretch = .None;
		tab.SkeletonCheck.Content = skelImg;
		tab.SkeletonCheck.VerticalAlignment = .Center;
		tab.SkeletonCheck.TooltipText = "Show skeleton";
		tab.AnimationToolbar.AddChild(tab.SkeletonCheck);

		// Update button state
		UpdatePlayPauseButton(tab);
	}

	/// Creates a button with an image icon.
	private Button CreateImageButton(IImageData icon, StringView tooltip)
	{
		let btn = new Button();
		let img = new Sedulous.GUI.Image(icon);
		img.Stretch = .None;
		img.HorizontalAlignment = .Center;
		img.VerticalAlignment = .Center;
		btn.Content = img;
		btn.Width = 28;
		btn.Height = 24;
		btn.Padding = .(4, 2, 4, 2);
		btn.VerticalAlignment = .Center;
		btn.TooltipText = tooltip;
		return btn;
	}

	/// Called when animation is selected from ComboBox.
	private void OnAnimationSelected(ModelTab tab, int32 index)
	{
		if (tab.Player == null || tab.Clips == null || index < 0 || index >= (int32)tab.Clips.Count)
			return;
		tab.CurrentClip = index;
		let isLooping = tab.LoopCheck?.IsChecked ?? false;
		tab.Clips[index].IsLooping = isLooping;
		tab.Player.Play(tab.Clips[index]);
		UpdatePlayPauseButton(tab);
	}

	/// Toggles play/pause on current animation.
	private void OnPlayPause(ModelTab tab)
	{
		if (tab.Player == null) return;

		if (tab.Player.State == .Playing)
			tab.Player.Pause();
		else if (tab.Player.State == .Paused)
			tab.Player.Resume();
		else if (tab.Clips != null && tab.Clips.Count > 0)
		{
			let isLooping = tab.LoopCheck?.IsChecked ?? false;
			tab.Clips[tab.CurrentClip].IsLooping = isLooping;
			tab.Player.Play(tab.Clips[tab.CurrentClip]);
		}
		UpdatePlayPauseButton(tab);
	}

	/// Stops the current animation.
	private void OnStop(ModelTab tab)
	{
		if (tab.Player != null)
			tab.Player.Stop();
		UpdatePlayPauseButton(tab);
	}

	/// Resets (restarts) the current animation.
	private void OnReset(ModelTab tab)
	{
		if (tab.Player != null && tab.Clips != null && tab.CurrentClip < (int32)tab.Clips.Count)
		{
			let isLooping = tab.LoopCheck?.IsChecked ?? false;
			tab.Clips[tab.CurrentClip].IsLooping = isLooping;
			tab.Player.Play(tab.Clips[tab.CurrentClip]);
		}
		UpdatePlayPauseButton(tab);
	}

	/// Called when loop toggle is changed.
	private void OnLoopToggled(ModelTab tab, bool isLooping)
	{
		if (tab.Clips == null || tab.CurrentClip >= (int32)tab.Clips.Count)
			return;

		// Update the current clip's looping state
		tab.Clips[tab.CurrentClip].IsLooping = isLooping;
	}

	/// Steps the animation back by one frame (1/30 second).
	private void OnStepBack(ModelTab tab)
	{
		if (tab.Player == null || tab.Clips == null || tab.CurrentClip >= (int32)tab.Clips.Count)
			return;

		let clip = tab.Clips[tab.CurrentClip];

		// If stopped, start the clip paused at current position
		if (tab.Player.State == .Stopped)
		{
			let isLooping = tab.LoopCheck?.IsChecked ?? false;
			clip.IsLooping = isLooping;
			tab.Player.Play(clip, false);
			tab.Player.Pause();
		}
		else if (tab.Player.State == .Playing)
		{
			tab.Player.Pause();
		}

		// Step back by 1/30 second (typical frame time)
		let frameTime = 1.0f / 30.0f;
		tab.Player.CurrentTime = Math.Max(0, tab.Player.CurrentTime - frameTime);
		tab.Player.Evaluate();
		UpdatePlayPauseButton(tab);
	}

	/// Steps the animation forward by one frame (1/30 second).
	private void OnStepForward(ModelTab tab)
	{
		if (tab.Player == null || tab.Clips == null || tab.CurrentClip >= (int32)tab.Clips.Count)
			return;

		let clip = tab.Clips[tab.CurrentClip];

		// If stopped, start the clip paused at current position
		if (tab.Player.State == .Stopped)
		{
			let isLooping = tab.LoopCheck?.IsChecked ?? false;
			clip.IsLooping = isLooping;
			tab.Player.Play(clip, false);
			tab.Player.Pause();
		}
		else if (tab.Player.State == .Playing)
		{
			tab.Player.Pause();
		}

		// Step forward by 1/30 second (typical frame time)
		let frameTime = 1.0f / 30.0f;
		tab.Player.CurrentTime = Math.Min(clip.Duration, tab.Player.CurrentTime + frameTime);
		tab.Player.Evaluate();
		UpdatePlayPauseButton(tab);
	}

	/// Updates the play/pause button icon based on player state.
	private void UpdatePlayPauseButton(ModelTab tab)
	{
		if (tab.PlayPauseButton == null || tab.Player == null) return;

		if (let img = tab.PlayPauseButton.Content as Sedulous.GUI.Image)
		{
			if (tab.Player.State == .Playing)
				img.Source = mPauseIcon;
			else
				img.Source = mPlayIcon;
		}
	}

	/// Updates the model transform with scale and offset.
	private void UpdateModelTransform(ModelTab tab)
	{
		let transform = Matrix.CreateScale(tab.ModelScale) * Matrix.CreateTranslation(tab.ModelOffset);
		if (tab.StaticMeshProxy.IsValid)
		{
			if (let proxy = tab.World.GetMesh(tab.StaticMeshProxy))
				proxy.SetTransformImmediate(transform);
		}
		if (tab.SkinnedMeshProxy.IsValid)
		{
			if (let proxy = tab.World.GetSkinnedMesh(tab.SkinnedMeshProxy))
				proxy.SetTransformImmediate(transform);
		}
	}

	/// Draws the skeleton for a skinned mesh using overlay lines.
	private void DrawSkeleton(ModelTab tab, OverlayRenderFeature overlay)
	{
		if (tab.Skeleton == null || tab.Player == null)
			return;

		let skeleton = tab.Skeleton;
		let boneCount = skeleton.BoneCount;
		if (boneCount == 0)
			return;

		// Get current bone poses from animation player
		let localPoses = tab.Player.GetLocalPoses();

		// Compute world poses
		Span<Matrix> worldPoses = scope Matrix[boneCount];
		skeleton.ComputeWorldPoses(localPoses, worldPoses);

		// Apply model transform (scale + offset)
		let modelTransform = Matrix.CreateScale(tab.ModelScale) * Matrix.CreateTranslation(tab.ModelOffset);

		// Draw bones
		let boneColor = Color(255, 200, 100, 255);
		let jointColor = Color(255, 100, 100, 255);

		for (int32 i = 0; i < boneCount; i++)
		{
			let bone = skeleton.GetBone(i);
			if (bone == null)
				continue;

			// Get bone world position (translation component of world pose, transformed by model)
			let boneWorldPose = worldPoses[i] * modelTransform;
			let bonePos = Vector3(boneWorldPose.M41, boneWorldPose.M42, boneWorldPose.M43);

			// Draw joint sphere
			overlay.AddSphere(bonePos, 0.02f * tab.ModelScale, jointColor, 8, .Overlay);

			// Draw line to parent
			if (bone.ParentIndex >= 0 && bone.ParentIndex < boneCount)
			{
				let parentWorldPose = worldPoses[bone.ParentIndex] * modelTransform;
				let parentPos = Vector3(parentWorldPose.M41, parentWorldPose.M42, parentWorldPose.M43);
				overlay.AddLine(parentPos, bonePos, boneColor, .Overlay);
			}
		}
	}

	private void SwitchToTab(int32 index)
	{
		if (index < 0 || index >= (int32)mTabs.Count)
			return;

		// Wait for GPU to finish before switching worlds (prevents descriptor set errors)
		Device.WaitIdle();

		// Hide current tab's content panel
		let oldTab = ActiveTab;
		if (oldTab != null && oldTab.ContentPanel != null)
			oldTab.ContentPanel.Visibility = .Collapsed;

		mActiveTabIndex = index;
		let tab = mTabs[index];

		// Switch render world
		mRenderSystem.SetActiveWorld(tab.World);

		// Show new tab's content panel
		if (tab.ContentPanel != null)
			tab.ContentPanel.Visibility = .Visible;

		// Update TabControl selection
		if (mTabControl != null)
			mTabControl.SelectedIndex = index;

		// Update info label
		UpdateModelInfoLabel();
	}

	/// Focuses the camera on the current model's bounding box.
	private void FocusCameraOnModel()
	{
		let tab = ActiveTab;
		if (tab == null || tab.Model == null)
			return;

		// Focus on scaled bounds at model's current position
		let scaledBounds = BoundingBox(
			tab.MeshBounds.Min * tab.ModelScale + tab.ModelOffset,
			tab.MeshBounds.Max * tab.ModelScale + tab.ModelOffset);
		tab.Camera.FitToModel(scaledBounds);
	}

	private void CloseTab(int32 index, bool removeFromTabControl = true)
	{
		if (index < 0 || index >= (int32)mTabs.Count)
			return;

		// Wait for GPU
		Device.WaitIdle();

		// Get the tab being closed
		let tab = mTabs[index];

		// Remove per-tab UI elements from container (don't delete - Destroy() handles that)
		if (tab.ContentPanel != null && mViewportContainer != null)
			mViewportContainer.RemoveChild(tab.ContentPanel, false);

		// Clean up and remove tab
		tab.Destroy(mRenderSystem);
		delete tab;
		mTabs.RemoveAt(index);

		// Remove from TabControl UI (skip if triggered by close button, as TabControl handles it)
		if (removeFromTabControl)
			mTabControl.RemoveTabAt(index);

		// Adjust active index and switch to appropriate tab
		if (mTabs.Count == 0)
		{
			mActiveTabIndex = -1;
			mRenderSystem.SetActiveWorld(null);
		}
		else if (mActiveTabIndex >= (int32)mTabs.Count)
		{
			mActiveTabIndex = (int32)mTabs.Count - 1;
			SwitchToTab(mActiveTabIndex);
		}
		else if (mActiveTabIndex == index)
		{
			// Same index, need to show the tab that slid into this position
			SwitchToTab(mActiveTabIndex);
		}

		UpdateEmptyState();
		UpdateModelInfoLabel();
	}

	private void UpdateEmptyState()
	{
		let hasModels = mTabs.Count > 0;

		// Show/hide drop indicator
		if (mDropIndicator != null)
			mDropIndicator.Visibility = hasModels ? .Collapsed : .Visible;

		// Show/hide tab control
		if (mTabControl != null)
			mTabControl.Visibility = hasModels ? .Visible : .Collapsed;
	}

	private void UpdateModelInfoLabel()
	{
		if (mModelInfoLabel == null)
			return;

		let tab = ActiveTab;
		let info = scope String();

		if (tab == null)
		{
			info.Append("Drag and drop a model\nonto the viewport\nto view it.");
		}
		else
		{
			info.AppendF("{}\n", tab.Name);
			if (tab.Model != null && tab.Model.Meshes.Count > 0)
			{
				int32 totalVerts = 0;
				int32 totalTris = 0;
				for (let mesh in tab.Model.Meshes)
				{
					totalVerts += mesh.VertexCount;
					totalTris += mesh.IndexCount / 3;
				}
				info.AppendF("Meshes: {}\n", tab.Model.Meshes.Count);
				info.AppendF("Vertices: {}\n", totalVerts);
				info.AppendF("Triangles: {}\n", totalTris);
				info.AppendF("Materials: {}\n", tab.Model.Materials.Count);
				if (tab.Model.Bones.Count > 0)
					info.AppendF("Bones: {}\n", tab.Model.Bones.Count);
				if (tab.Clips != null && tab.Clips.Count > 0)
					info.AppendF("Animations: {}", tab.Clips.Count);
			}
		}
		mModelInfoLabel.Text = info;
	}

	protected override void OnUpdate(float deltaTime)
	{
		let tab = ActiveTab;
		if (tab == null || tab.Viewport == null)
			return;

		// Handle viewport camera controls
		{
			let mouse = Shell.InputManager.Mouse;
			let keyboard = Shell.InputManager.Keyboard;
			let viewport = tab.Viewport;

			// Account for UI scaling - convert screen coordinates to logical coordinates
			let uiScale = mGUIContext?.ScaleFactor ?? 1.0f;
			float scaledMouseX = mouse.X / uiScale;
			float scaledMouseY = mouse.Y / uiScale;

			// Check if mouse is inside viewport bounds (in logical coordinates)
			let viewportBounds = viewport.ArrangedBounds;
			bool mouseInViewport = scaledMouseX >= viewportBounds.X && scaledMouseX < viewportBounds.Right &&
				scaledMouseY >= viewportBounds.Y && scaledMouseY < viewportBounds.Bottom;

			// Check if mouse is over a UI element (popup, dropdown, etc.) - block input if so
			// Note: HitTest expects screen coordinates, not scaled
			let hitElement = mGUIContext?.HitTest(mouse.X, mouse.Y);
			bool uiCaptured = hitElement != null && hitElement != viewport && hitElement != mRootPanel;

			// Track button state - only start drag/fly/pan if mouse is in viewport and UI hasn't captured input
			// Ctrl+LMB = orbit rotate, LMB alone = gizmo interaction
			bool ctrlHeld = keyboard.IsKeyDown(.LeftCtrl) || keyboard.IsKeyDown(.RightCtrl);
			if (mouse.IsButtonPressed(.Left) && mouseInViewport && !uiCaptured && ctrlHeld)
			{
				mIsDragging = true;
				mLastMouseX = mouse.X;
				mLastMouseY = mouse.Y;
			}
			if (mouse.IsButtonReleased(.Left))
				mIsDragging = false;

			if (mouse.IsButtonPressed(.Right) && mouseInViewport && !uiCaptured)
			{
				mIsFlying = true;
				mLastMouseX = mouse.X;
				mLastMouseY = mouse.Y;
			}
			if (mouse.IsButtonReleased(.Right))
				mIsFlying = false;

			if (mouse.IsButtonPressed(.Middle) && mouseInViewport && !uiCaptured)
			{
				mIsPanning = true;
				mLastMouseX = mouse.X;
				mLastMouseY = mouse.Y;
			}
			if (mouse.IsButtonReleased(.Middle))
				mIsPanning = false;

			// LMB: Orbit rotate (horizontal only - no pitch to avoid accidental vertical rotation)
			if (mIsDragging && !mIsFlying)
			{
				float deltaX = mouse.X - mLastMouseX;
				tab.Camera.Rotate(-deltaX * 0.01f, 0);
				mLastMouseX = mouse.X;
				mLastMouseY = mouse.Y;
			}

			// RMB: Fly mode - mouse look + WASD movement
			if (mIsFlying)
			{
				// Mouse look
				float deltaX = mouse.X - mLastMouseX;
				float deltaY = mouse.Y - mLastMouseY;
				tab.Camera.Rotate(-deltaX * 0.01f, -deltaY * 0.01f);
				mLastMouseX = mouse.X;
				mLastMouseY = mouse.Y;

				// WASD movement (only if viewport has focus to avoid conflict with text input)
				if (viewport.IsFocused || mouseInViewport)
				{
					float moveSpeed = tab.Camera.Distance * 2.0f * deltaTime;
					if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
						moveSpeed *= 3.0f; // Sprint

					float forward = 0, right = 0, up = 0;
					if (keyboard.IsKeyDown(.W)) forward += 1;
					if (keyboard.IsKeyDown(.S)) forward -= 1;
					if (keyboard.IsKeyDown(.D)) right += 1;
					if (keyboard.IsKeyDown(.A)) right -= 1;
					if (keyboard.IsKeyDown(.E) || keyboard.IsKeyDown(.Space)) up += 1;
					if (keyboard.IsKeyDown(.Q) || keyboard.IsKeyDown(.LeftCtrl)) up -= 1;

					if (forward != 0 || right != 0 || up != 0)
						tab.Camera.Move(forward, right, up, moveSpeed);
				}
			}

			// MMB: Pan
			if (mIsPanning)
			{
				float deltaX = mouse.X - mLastMouseX;
				float deltaY = mouse.Y - mLastMouseY;
				tab.Camera.Pan(-deltaX, deltaY);
				mLastMouseX = mouse.X;
				mLastMouseY = mouse.Y;
			}

			// Scroll: Zoom (only when mouse is in viewport and not over UI elements)
			if (mouse.ScrollY != 0 && mouseInViewport && !uiCaptured)
				tab.Camera.Zoom(mouse.ScrollY * tab.Camera.Distance * 0.1f);

			// Gizmo interaction (when not flying or panning and not over UI)
			if (mGizmo != null && !mIsFlying && !mIsPanning && !uiCaptured && tab.Model != null)
			{
				// Position gizmo at model's current position (only when not dragging)
				if (!mGizmo.IsDragging)
				{
					// Model center in local space, scaled, plus model offset = world position
					let meshCenter = (tab.MeshBounds.Min + tab.MeshBounds.Max) * 0.5f * tab.ModelScale;
					mGizmo.Position = meshCenter + tab.ModelOffset;
				}

				// Scale gizmo based on distance from camera
				mGizmo.Size = tab.Camera.Distance * 0.15f;

				// Get viewport bounds and render dimensions
				// Both ArrangedBounds and RenderWidth/Height are in logical coordinates
				let vpX = viewportBounds.X;
				let vpY = viewportBounds.Y;
				let vpW = viewport.RenderWidth;
				let vpH = viewport.RenderHeight;

				// Convert scaled mouse position to viewport-local coordinates (all in logical space)
				float localMouseX = scaledMouseX - vpX;
				float localMouseY = scaledMouseY - vpY;

				// Only interact if mouse is inside viewport and dimensions are valid
				if (localMouseX >= 0 && localMouseX < vpW && localMouseY >= 0 && localMouseY < vpH && vpW > 0 && vpH > 0)
				{
					// Compute projection matrix for picking (no Vulkan Y-flip - that's for rendering only)
					// CreatePickRay handles the screen-to-NDC Y conversion internally
					float aspectRatio = (float)vpW / (float)vpH;
					let projMatrix = Matrix.CreatePerspectiveFieldOfView(
						mView.FieldOfView, aspectRatio, mView.NearPlane, mView.FarPlane);

					// Create pick ray
					let pickRay = TranslateGizmo.CreatePickRay(
						localMouseX, localMouseY, vpW, vpH,
						tab.Camera.ViewMatrix, projMatrix);

					// Update hover
					mGizmo.UpdateHover(pickRay, mGizmo.Size * 0.15f);

					// Handle drag start (LMB without Ctrl = gizmo, Ctrl+LMB = camera rotate)
					// Note: ctrlHeld already defined in outer scope
					if (mouse.IsButtonPressed(.Left) && mGizmo.HoveredAxis != .None && !ctrlHeld)
					{
						Console.WriteLine(scope $"BeginDrag: axis={mGizmo.HoveredAxis}, pos={mGizmo.Position}");
						mGizmo.BeginDrag(pickRay);
						mIsDragging = false; // Prevent camera rotation while dragging gizmo
						// Store start model offset (not gizmo position, which includes mesh center)
						mGizmoDragStartPos = tab.ModelOffset;
					}

					if (mGizmo.IsDragging)
					{
						let delta = mGizmo.UpdateDrag(pickRay);
						// Calculate new model offset from original offset + drag delta
						let newOffset = mGizmoDragStartPos + delta;

						// Store the offset and update transform (includes scale)
						tab.ModelOffset = newOffset;
						UpdateModelTransform(tab);

						// Update gizmo to follow the model (gizmo is at scaled mesh center + offset)
						let meshCenter = (tab.MeshBounds.Min + tab.MeshBounds.Max) * 0.5f * tab.ModelScale;
						mGizmo.Position = meshCenter + newOffset;
					}
				}

				if (mouse.IsButtonReleased(.Left) && mGizmo.IsDragging)
				{
					Console.WriteLine(scope $"EndDrag: finalPos={mGizmo.Position}, startPos={mGizmoDragStartPos}, delta={mGizmo.Position - mGizmoDragStartPos}");
					mGizmo.EndDrag();
				}
			}

			// Cycle animations (require focus for keyboard input)
			if (viewport.IsFocused && tab.Clips != null && tab.Clips.Count > 0 && tab.Player != null)
			{
				bool changed = false;
				if (keyboard.IsKeyPressed(.Right) || keyboard.IsKeyPressed(.Period))
				{
					tab.CurrentClip = (tab.CurrentClip + 1) % (int32)tab.Clips.Count;
					changed = true;
				}
				if (keyboard.IsKeyPressed(.Left) || keyboard.IsKeyPressed(.Comma))
				{
					tab.CurrentClip = (tab.CurrentClip - 1 + (int32)tab.Clips.Count) % (int32)tab.Clips.Count;
					changed = true;
				}
				if (changed)
				{
					let isLooping = tab.LoopCheck?.IsChecked ?? false;
					tab.Clips[tab.CurrentClip].IsLooping = isLooping;
					tab.Player.Play(tab.Clips[tab.CurrentClip]);
					Console.WriteLine(scope $"Playing: {tab.Clips[tab.CurrentClip].Name}");

					// Sync ComboBox selection
					if (tab.AnimationComboBox != null)
						tab.AnimationComboBox.SelectedIndex = tab.CurrentClip;
					UpdatePlayPauseButton(tab);
				}
			}
		}

		// Update animation
		if (tab.Player != null)
		{
			tab.Player.Update(deltaTime);
			tab.Player.Evaluate();

			// Upload bone matrices
			if (tab.BoneBufferHandle.IsValid && tab.Skeleton != null)
			{
				let currentMatrices = tab.Player.GetSkinningMatrices();
				let prevMatrices = tab.Player.GetPrevSkinningMatrices();
				if (currentMatrices.Ptr != null && currentMatrices.Length > 0)
				{
					mRenderSystem.ResourceManager.UpdateBoneBuffer(
						tab.BoneBufferHandle,
						currentMatrices.Ptr,
						prevMatrices.Ptr,
						(uint16)tab.Skeleton.BoneCount
						);
				}
			}
		}
		else if (tab.BoneBufferHandle.IsValid && tab.Skeleton != null)
		{
			// No animation player but have skeleton - upload identity matrices
			// This shouldn't happen normally, but let's handle it
			Console.WriteLine("WARNING: Skinned mesh has no animation player!");
		}
	}

	protected override bool OnRender(ICommandEncoder encoder, int32 frameIndex)
	{
		let tab = ActiveTab;
		let viewport = tab?.Viewport;

		// Render the 3D viewport content
		if (viewport != null && viewport.IsReady)
		{
			let width = viewport.RenderWidth;
			let height = viewport.RenderHeight;

			if (tab != null)
			{
				// Update view
				mView.Width = width;
				mView.Height = height;
				mView.CameraPosition = tab.Camera.Position;
				mView.CameraForward = tab.Camera.Forward;
				mView.CameraUp = .(0, 1, 0);
				mView.UpdateMatrices(Device.FlipProjectionRequired);

				// Set output target for our custom feature
				mOutputFeature.SetOutputTarget(viewport.ColorTexture, viewport.ColorTargetView,
					viewport.DepthTexture, viewport.DepthTargetView, width, height);

				// Render via RenderSystem
				mRenderSystem.BeginFrame(TotalTime, DeltaTime);
				mRenderSystem.SetCamera(tab.Camera.Position, tab.Camera.Forward, .(0, 1, 0),
					mView.FieldOfView, mView.AspectRatio, mView.NearPlane, mView.FarPlane, width, height);

				// Draw gizmo (before BuildRenderGraph so overlay feature can pick it up)
				if (mGizmo != null && mOverlayFeature != null && tab.Model != null)
				{
					mGizmo.Draw(mOverlayFeature);
				}

				// Draw bounding box if enabled (offset by model position)
				if (tab.BoundingBoxCheck != null && tab.BoundingBoxCheck.IsChecked && mOverlayFeature != null && tab.Model != null)
				{
					// Apply scale (around origin) then offset to match the model transform
					let scaledBounds = BoundingBox(
						tab.MeshBounds.Min * tab.ModelScale + tab.ModelOffset,
						tab.MeshBounds.Max * tab.ModelScale + tab.ModelOffset);
					mOverlayFeature.AddBox(scaledBounds, Color(255, 200, 50, 255), .Overlay);
				}

				// Draw floor grid if enabled
				if (tab.GridCheck != null && tab.GridCheck.IsChecked && mOverlayFeature != null)
				{
					// Grid at Y=0, sized based on model bounds
					let gridSize = Math.Max(
						Math.Max(Math.Abs(tab.MeshBounds.Max.X), Math.Abs(tab.MeshBounds.Min.X)),
						Math.Max(Math.Abs(tab.MeshBounds.Max.Z), Math.Abs(tab.MeshBounds.Min.Z))
					) * tab.ModelScale * 4.0f;
					let gridCenter = Vector3(tab.ModelOffset.X, 0, tab.ModelOffset.Z);
					mOverlayFeature.AddGrid(gridCenter, Math.Max(gridSize, 10.0f), 20, Color(80, 80, 100, 255), .DepthTest);
				}

				// Draw skeleton if enabled (skinned meshes only)
				if (tab.SkeletonCheck != null && tab.SkeletonCheck.IsChecked && mOverlayFeature != null &&
					tab.Skeleton != null && tab.Player != null)
				{
					DrawSkeleton(tab, mOverlayFeature);
				}

				if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
					mRenderSystem.Execute(encoder);

				mRenderSystem.EndFrame();
			}
			else
			{
				// No active tab - just clear the viewport to a dark color
				RenderPassColorAttachment[1] clearAttachments = .(.(viewport.ColorTargetView)
					{
						LoadOp = .Clear,
						StoreOp = .Store,
						ClearValue = .(0.1f, 0.1f, 0.12f, 1.0f)
					});
				RenderPassDescriptor clearPassDesc = .(clearAttachments);
				clearPassDesc.DepthStencilAttachment = .(viewport.DepthTargetView)
					{
						DepthLoadOp = .Clear,
						DepthStoreOp = .Store,
						DepthClearValue = 1.0f
					};

				let clearPass = encoder.BeginRenderPass(&clearPassDesc);
				if (clearPass != null)
				{
					clearPass.End();
					delete clearPass;
				}
			}

			// Transition the viewport texture for UI sampling
			encoder.TextureBarrier(viewport.ColorTexture, .ColorAttachment, .ShaderReadOnly);
		}

		// Then render UI (default behavior renders to swap chain)
		let swapTextureView = SwapChain.CurrentTextureView;
		RenderPassColorAttachment[1] uiAttachments = .(.(swapTextureView)
			{
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = mConfig.ClearColor
			});
		RenderPassDescriptor uiPassDesc = .(uiAttachments);

		let uiPass = encoder.BeginRenderPass(&uiPassDesc);
		if (uiPass != null)
		{
			mDrawingRenderer.Render(uiPass, SwapChain.Width, SwapChain.Height, frameIndex);
			uiPass.End();
			delete uiPass;
		}

		return true;
	}

	protected override void OnUISetup(GUIContext context)
	{
		// Root: SplitPanel with sidebar on left, viewport on right
		mRootPanel = new SplitPanel();
		mRootPanel.Orientation = .Horizontal;
		mRootPanel.SplitRatio = 0.2f;
		mRootPanel.MinFirstSize = 150;
		mRootPanel.MinSecondSize = 200;
		mRootPanel.SplitterSize = 6;

		// Side panel (first child = left)
		mSidePanel = new StackPanel();
		mSidePanel.Orientation = .Vertical;
		mSidePanel.Spacing = 5;
		mSidePanel.Background = Color(30, 30, 35, 240);
		mSidePanel.Padding = .(10, 10, 10, 10);
		mRootPanel.AddChild(mSidePanel);

		// Title
		let titleLabel = new Label("Model Viewer");
		titleLabel.FontSize = 18;
		mSidePanel.AddChild(titleLabel);

		// Supported formats
		let formatsLabel = new Label("Formats: GLTF, GLB, FBX");
		formatsLabel.FontSize = 11;
		formatsLabel.Foreground = Color(180, 180, 180, 255);
		mSidePanel.AddChild(formatsLabel);

		let sep = new Separator();
		sep.Margin = .(0, 5, 0, 5);
		mSidePanel.AddChild(sep);

		// Model info
		mModelInfoLabel = new TextBlock("No model loaded");
		mModelInfoLabel.FontSize = 12;
		mModelInfoLabel.TextWrapping = .Wrap;
		mSidePanel.AddChild(mModelInfoLabel);

		let sep2 = new Separator();
		sep2.Margin = .(0, 5, 0, 5);
		mSidePanel.AddChild(sep2);

		// Help
		let helpLabel = new Label("Controls:");
		helpLabel.FontSize = 12;
		mSidePanel.AddChild(helpLabel);

		let help1 = new Label("  LMB: Rotate");
		help1.FontSize = 11;
		help1.Foreground = Color(180, 180, 180, 255);
		mSidePanel.AddChild(help1);

		let help2 = new Label("  RMB: Pan");
		help2.FontSize = 11;
		help2.Foreground = Color(180, 180, 180, 255);
		mSidePanel.AddChild(help2);

		let help3 = new Label("  Scroll: Zoom");
		help3.FontSize = 11;
		help3.Foreground = Color(180, 180, 180, 255);
		mSidePanel.AddChild(help3);

		let help4 = new Label("  R: Reset camera");
		help4.FontSize = 11;
		help4.Foreground = Color(180, 180, 180, 255);
		mSidePanel.AddChild(help4);

		let help5 = new Label("  Left/Right: Cycle anims");
		help5.FontSize = 11;
		help5.Foreground = Color(180, 180, 180, 255);
		mSidePanel.AddChild(help5);

		let help6 = new Label("  Drop files to load");
		help6.FontSize = 11;
		help6.Foreground = Color(180, 180, 180, 255);
		mSidePanel.AddChild(help6);

		// Right side: Grid with tabs (row 0), viewport container (row 1)
		mViewportPanel = new Grid();
		mViewportPanel.RowDefinitions.Add(new .() { Height = .Auto }); // Row 0: Tab control (auto height)
		mViewportPanel.RowDefinitions.Add(new .() { Height = .Star }); // Row 1: Per-tab content (fills remaining)
		mViewportPanel.ColumnDefinitions.Add(new .() { Width = .Star });
		mRootPanel.AddChild(mViewportPanel);

		// Tab control (row 0, hidden when no tabs)
		mTabControl = new TabControl();
		mTabControl.TabStripPlacement = .Top;
		mTabControl.Height = 30;
		mTabControl.Visibility = .Collapsed;
		GridProperties.SetRow(mTabControl, 0);
		mTabControl.SelectionChanged.Subscribe(new (tc) =>
			{
				if (tc.SelectedIndex >= 0 && tc.SelectedIndex != mActiveTabIndex)
					SwitchToTab((int32)tc.SelectedIndex);
			});
		mViewportPanel.AddChild(mTabControl);

		// Container for per-tab content panels and drop indicator (row 1)
		mViewportContainer = new Grid();
		mViewportContainer.RowDefinitions.Add(new .() { Height = .Star });
		mViewportContainer.ColumnDefinitions.Add(new .() { Width = .Star });
		GridProperties.SetRow(mViewportContainer, 1);
		mViewportPanel.AddChild(mViewportContainer);

		// Drop indicator (shown when no tabs)
		mDropIndicator = new TextBlock("Drop a model here\n\nGLTF, GLB, FBX");
		mDropIndicator.FontSize = 20;
		mDropIndicator.Foreground = Color(150, 150, 160, 255);
		mDropIndicator.TextWrapping = .Wrap;
		mDropIndicator.TextAlignment = .Center;
		mDropIndicator.HorizontalAlignment = .Center;
		mDropIndicator.VerticalAlignment = .Center;
		mViewportContainer.AddChild(mDropIndicator);

		context.RootElement = mRootPanel;

		UpdateModelInfoLabel();
		UpdateEmptyState();
	}

	protected override void OnKeyDown(Sedulous.Shell.Input.KeyCode key)
	{
		// Reset/focus camera on model
		if (key == .R)
			FocusCameraOnModel();
	}

	protected override void OnFileDrop(StringView path)
	{
		// Check if any registered loader supports this file type
		let ext = Path.GetExtension(path, .. scope .());
		if (ModelLoaderFactory.GetLoaderForExtension(ext) != null)
		{
			LoadModel(path);
		}
	}

	protected override void OnCleanup()
	{
		// Wait for GPU to finish all work
		Device?.WaitIdle();

		// Close all tabs properly (destroys render resources, deletes tab objects)
		while (mTabs.Count > 0)
			CloseTab(0, false);

		// Shutdown render system (this cleans up features, pipelines, etc.)
		mRenderSystem?.Shutdown();

		// Delete view and render system (after shutdown)
		if (mView != null) { delete mView; mView = null; }
		if (mRenderSystem != null) { delete mRenderSystem; mRenderSystem = null; }

		// Clean up UI last — GUIContext only references it, doesn't own it
		delete mRootPanel;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope ModelViewerApp();
		return app.Run();
	}
}
