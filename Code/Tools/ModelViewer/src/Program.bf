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
using Sedulous.GUI;
using Sedulous.Render;
using Sedulous.Materials;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Textures;
using Sedulous.Textures.Resources;
using Sedulous.Imaging;

/// Simple orbit camera
class OrbitCamera
{
	public Vector3 Target = .Zero;
	public float Distance = 5.0f;
	public float Yaw = 0.0f;
	public float Pitch = 0.3f;
	public float MinDistance = 0.5f;
	public float MaxDistance = 100.0f;
	public float MinPitch = -Math.PI_f / 2.0f + 0.1f;
	public float MaxPitch = Math.PI_f / 2.0f - 0.1f;

	public Vector3 Position
	{
		get
		{
			float x = Distance * Math.Cos(Pitch) * Math.Sin(Yaw);
			float y = Distance * Math.Sin(Pitch);
			float z = Distance * Math.Cos(Pitch) * Math.Cos(Yaw);
			return Target + Vector3(x, y, z);
		}
	}

	public Vector3 Forward => Vector3.Normalize(Target - Position);

	public Matrix ViewMatrix => Matrix.CreateLookAt(Position, Target, Vector3.Up);

	public void Rotate(float deltaYaw, float deltaPitch)
	{
		Yaw += deltaYaw;
		Pitch = Math.Clamp(Pitch + deltaPitch, MinPitch, MaxPitch);
	}

	public void Zoom(float delta)
	{
		Distance = Math.Clamp(Distance - delta, MinDistance, MaxDistance);
	}

	public void Pan(float deltaX, float deltaY)
	{
		let forward = Vector3.Normalize(Target - Position);
		let right = Vector3.Normalize(Vector3.Cross(forward, Vector3.Up));
		let up = Vector3.Cross(right, forward);

		Target += right * deltaX * Distance * 0.01f;
		Target += up * deltaY * Distance * 0.01f;
	}

	public void FitToModel(BoundingBox bounds)
	{
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let extents = (bounds.Max - bounds.Min) * 0.5f;
		Target = center;
		Distance = Math.Max(extents.Length() * 2.5f, 1.0f);
		Yaw = 0;
		Pitch = 0.3f;
	}

	/// Gets the right vector (perpendicular to forward and up).
	public Vector3 Right
	{
		get
		{
			let forward = Forward;
			return Vector3.Normalize(Vector3.Cross(forward, Vector3.Up));
		}
	}

	/// Gets the camera's local up vector.
	public Vector3 Up
	{
		get
		{
			let forward = Forward;
			let right = Vector3.Normalize(Vector3.Cross(forward, Vector3.Up));
			return Vector3.Cross(right, forward);
		}
	}

	/// Moves the camera in fly mode (WASD style).
	/// forward: +1 = forward (W), -1 = backward (S)
	/// right: +1 = right (D), -1 = left (A)
	/// up: +1 = up (E/Space), -1 = down (Q/Ctrl)
	public void Move(float forward, float right, float up, float speed)
	{
		let forwardDir = Forward;
		let rightDir = Right;

		// Move both camera and target together to preserve orbit distance
		let movement = forwardDir * forward * speed + rightDir * right * speed + Vector3.Up * up * speed;
		Target += movement;
	}
}

/// Model Viewer Application using Sedulous.Render with multi-tab support
class ModelViewerApp : Application
{
	// Render system (cleaned up in OnCleanup)
	private RenderSystem mRenderSystem;
	private RenderView mView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private DebugRenderFeature mDebugFeature;
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

	// UI
	private SplitPanel mRootPanel;
	private StackPanel mSidePanel;
	private Grid mViewportPanel;
	private TabControl mTabControl;
	private Grid mViewportContainer;
	private ViewportControl mViewport;
	private Label mModelInfoLabel;
	private Label mDropIndicator;

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
		GltfModels.Initialize();
		FbxModels.Initialize();

		// Initialize render system
		let shaderPaths = scope StringView[](scope $"{AssetDirectory}/Render/Shaders");
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(Device, shaderPaths, .RGBA8Unorm, .Depth24PlusStencil8) case .Err)
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

		return true;
	}

	private void RegisterFeatures()
	{
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		// Debug rendering for gizmos
		mDebugFeature = new DebugRenderFeature();
		mRenderSystem.RegisterFeature(mDebugFeature);

		// Custom output feature for viewport rendering
		mOutputFeature = new ViewportOutputFeature();
		mRenderSystem.RegisterFeature(mOutputFeature);

		// Initialize gizmo
		mGizmo = new TranslateGizmo();
		mGizmo.Size = 1.0f;
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

		// Create world for this tab
		tab.CreateWorld(mRenderSystem);

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

		// Get base path for texture loading
		let basePath = scope String();
		let lastSep = Math.Max(path.LastIndexOf('/'), path.LastIndexOf('\\'));
		if (lastSep >= 0)
			basePath.Set(path.Substring(0, lastSep));

		// Use ModelImporter for conversion
		let importOptions = new ModelImportOptions();
		importOptions.BasePath.Set(basePath);

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
			SetupSkinnedMesh(tab, importResult);
		}
		else if (importResult.StaticMeshes.Count > 0)
		{
			SetupStaticMesh(tab, importResult);
		}

		// Load texture
		LoadTexture(tab, importResult, basePath);

		// Fit camera to model
		tab.Camera.FitToModel(tab.Model.Bounds);

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

		if (mRenderSystem.ResourceManager.UploadMesh(resource.Mesh) case .Ok(let handle))
		{
			tab.MeshHandle = handle;

			tab.StaticMeshProxy = tab.World.CreateMesh();
			if (let proxy = tab.World.GetMesh(tab.StaticMeshProxy))
			{
				proxy.MeshHandle = tab.MeshHandle;
				proxy.Materials[0] = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(resource.Mesh.GetBounds());
				proxy.SetTransformImmediate(.Identity);
				proxy.Flags = .DefaultOpaque;
			}
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

		if (mRenderSystem.ResourceManager.UploadMesh(resource.Mesh) case .Ok(let handle))
		{
			tab.MeshHandle = handle;

			let boneCount = (uint16)(tab.Skeleton?.BoneCount ?? 0);
			if (boneCount > 0)
			{
				if (mRenderSystem.ResourceManager.CreateBoneBuffer(boneCount) case .Ok(let boneHandle))
					tab.BoneBufferHandle = boneHandle;
			}

			tab.SkinnedMeshProxy = tab.World.CreateSkinnedMesh();
			if (let proxy = tab.World.GetSkinnedMesh(tab.SkinnedMeshProxy))
			{
				proxy.MeshHandle = tab.MeshHandle;
				proxy.BoneBufferHandle = tab.BoneBufferHandle;
				proxy.Materials[0] = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(resource.Mesh.Bounds);
				proxy.BoneCount = boneCount;
				proxy.SetTransformImmediate(.Identity);
				proxy.Flags = .DefaultOpaque;
			}

			// Play first animation
			if (tab.Clips != null && tab.Clips.Count > 0 && tab.Player != null)
			{
				tab.Clips[0].IsLooping = true;
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

	private void ExtractAnimationsFromModel(ModelTab tab)
	{
		if (tab.Model == null || tab.Model.Animations.Count == 0 || tab.Model.Skins.Count == 0)
		{
			tab.Clips = new AnimationClip[0];
			return;
		}

		let skin = tab.Model.Skins[0];
		Dictionary<int32, int32> boneToJoint = scope .();
		for (int32 j = 0; j < (int32)skin.Joints.Count; j++)
			boneToJoint[skin.Joints[j]] = j;

		for (int i = 0; i < tab.Model.Animations.Count; i++)
		{
			let modelAnim = tab.Model.Animations[i];
			let clip = new AnimationClip(modelAnim.Name, modelAnim.Duration, false);

			for (let channel in modelAnim.Channels)
			{
				int32 jointIndex;
				if (!boneToJoint.TryGetValue(channel.TargetBone, out jointIndex))
					continue;

				let interp = ConvertInterpolation(channel.Interpolation);

				switch (channel.Path)
				{
				case .Translation:
					let track = clip.GetOrCreatePositionTrack(jointIndex);
					track.Interpolation = interp;
					for (let kf in channel.Keyframes)
						track.AddKeyframe(kf.Time, Vector3(kf.Value.X, kf.Value.Y, kf.Value.Z));
				case .Rotation:
					let track = clip.GetOrCreateRotationTrack(jointIndex);
					track.Interpolation = interp;
					for (let kf in channel.Keyframes)
						track.AddKeyframe(kf.Time, Quaternion(kf.Value.X, kf.Value.Y, kf.Value.Z, kf.Value.W));
				case .Scale:
					let track = clip.GetOrCreateScaleTrack(jointIndex);
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

	private void LoadTexture(ModelTab tab, ModelImportResult importResult, StringView basePath)
	{
		// Try to load texture from import result
		if (importResult.Textures.Count > 0)
		{
			let texRes = importResult.Textures[0];
			if (texRes.Image != null)
			{
				let texData = TextureData.FromImage(texRes.Image);
				if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let handle))
				{
					tab.TextureHandle = handle;
					CreateMaterial(tab);
					return;
				}
			}
		}

		// Try loading textures from model materials
		if (tab.Model.Materials.Count > 0)
		{
			let mat = tab.Model.Materials[0];
			if (mat.BaseColorTextureIndex >= 0 && mat.BaseColorTextureIndex < (int32)tab.Model.Textures.Count)
			{
				let modelTex = tab.Model.Textures[mat.BaseColorTextureIndex];
				let texUri = modelTex.Uri;

				if (texUri.Length > 0)
				{
					let texPath = scope String();
					if (basePath.Length > 0)
						texPath.AppendF("{}/{}", basePath, texUri);
					else
						texPath.Set(texUri);

					if (ImageLoaderFactory.LoadImage(texPath) case .Ok(var image))
					{
						defer delete image;
						let texData = TextureData.FromImage(image);
						if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let handle))
						{
							tab.TextureHandle = handle;
							CreateMaterial(tab);
							return;
						}
					}
				}
			}
		}
	}

	private void CreateMaterial(ModelTab tab)
	{
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMat != null)
		{
			tab.Material = new MaterialInstance(baseMat);
			tab.Material.SetColor("BaseColor", .(1, 1, 1, 1));
			tab.Material.SetFloat("Metallic", 0.0f);
			tab.Material.SetFloat("Roughness", 0.5f);

			if (let texView = mRenderSystem.ResourceManager.GetTextureView(tab.TextureHandle))
				tab.Material.SetTexture("AlbedoMap", texView);

			// Update proxy material
			if (tab.StaticMeshProxy.IsValid)
			{
				if (let proxy = tab.World.GetMesh(tab.StaticMeshProxy))
					proxy.Materials[0] = tab.Material;
			}
			if (tab.SkinnedMeshProxy.IsValid)
			{
				if (let proxy = tab.World.GetSkinnedMesh(tab.SkinnedMeshProxy))
					proxy.Materials[0] = tab.Material;
			}
		}
	}

	private void AddTabToUI(ModelTab tab)
	{
		if (mTabControl == null)
			return;

		let tabItem = mTabControl.AddTab(tab.Name);
		tabItem.IsCloseable = true;

		// Subscribe to close event - use the tab's stored index
		tabItem.CloseRequested.Subscribe(new [&](item) => {
			// Get the index before TabControl removes the tab
			let index = (int32)item.Index;
			if (index >= 0 && index < (int32)mTabs.Count)
				CloseTab(index, false);  // Don't remove from TabControl - it handles that
		});

		// Update visibility
		UpdateEmptyState();
	}

	private void SwitchToTab(int32 index)
	{
		if (index < 0 || index >= (int32)mTabs.Count)
			return;

		mActiveTabIndex = index;
		let tab = mTabs[index];

		// Switch render world
		mRenderSystem.SetActiveWorld(tab.World);

		// Update TabControl selection
		if (mTabControl != null)
			mTabControl.SelectedIndex = index;

		// Update info label
		UpdateModelInfoLabel();
	}

	private void CloseTab(int32 index, bool removeFromTabControl = true)
	{
		if (index < 0 || index >= (int32)mTabs.Count)
			return;

		// Wait for GPU
		Device.WaitIdle();

		// Clean up and remove tab
		let tab = mTabs[index];
		tab.Destroy(mRenderSystem);
		delete tab;
		mTabs.RemoveAt(index);

		// Remove from TabControl UI (skip if triggered by close button, as TabControl handles it)
		if (removeFromTabControl)
			mTabControl.RemoveTabAt(index);

		// Adjust active index
		if (mTabs.Count == 0)
		{
			mActiveTabIndex = -1;
			mRenderSystem.SetActiveWorld(null);
		}
		else if (mActiveTabIndex >= (int32)mTabs.Count)
		{
			mActiveTabIndex = (int32)mTabs.Count - 1;
			mRenderSystem.SetActiveWorld(mTabs[mActiveTabIndex].World);
		}
		else if (mActiveTabIndex == index)
		{
			// Switched away, reactivate
			mRenderSystem.SetActiveWorld(mTabs[mActiveTabIndex].World);
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
		mModelInfoLabel.ContentText = info;
	}

	protected override void OnUpdate(float deltaTime)
	{
		let tab = ActiveTab;
		if (tab == null)
			return;

		// Handle viewport camera controls
		if (mViewport != null)
		{
			let mouse = Shell.InputManager.Mouse;
			let keyboard = Shell.InputManager.Keyboard;

			// Check if mouse is inside viewport bounds
			let viewportBounds = mViewport.ArrangedBounds;
			bool mouseInViewport = mouse.X >= viewportBounds.X && mouse.X < viewportBounds.Right &&
								   mouse.Y >= viewportBounds.Y && mouse.Y < viewportBounds.Bottom;

			// Track button state - only start drag/fly/pan if mouse is in viewport
			if (mouse.IsButtonPressed(.Left) && mouseInViewport)
			{
				mIsDragging = true;
				mLastMouseX = mouse.X;
				mLastMouseY = mouse.Y;
			}
			if (mouse.IsButtonReleased(.Left))
				mIsDragging = false;

			if (mouse.IsButtonPressed(.Right) && mouseInViewport)
			{
				mIsFlying = true;
				mLastMouseX = mouse.X;
				mLastMouseY = mouse.Y;
			}
			if (mouse.IsButtonReleased(.Right))
				mIsFlying = false;

			if (mouse.IsButtonPressed(.Middle) && mouseInViewport)
			{
				mIsPanning = true;
				mLastMouseX = mouse.X;
				mLastMouseY = mouse.Y;
			}
			if (mouse.IsButtonReleased(.Middle))
				mIsPanning = false;

			// LMB: Orbit rotate
			if (mIsDragging && !mIsFlying)
			{
				float deltaX = mouse.X - mLastMouseX;
				float deltaY = mouse.Y - mLastMouseY;
				tab.Camera.Rotate(-deltaX * 0.01f, -deltaY * 0.01f);
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
				if (mViewport.IsFocused || mouseInViewport)
				{
					float moveSpeed = tab.Camera.Distance * 2.0f * deltaTime;
					if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
						moveSpeed *= 3.0f;  // Sprint

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

			// Scroll: Zoom
			if (mouse.ScrollY != 0)
				tab.Camera.Zoom(mouse.ScrollY * tab.Camera.Distance * 0.1f);

			// Gizmo interaction (when not flying or panning)
			if (mGizmo != null && !mIsFlying && !mIsPanning && tab.Model != null)
			{
				// Position gizmo at model center
				let modelCenter = (tab.Model.Bounds.Min + tab.Model.Bounds.Max) * 0.5f;
				mGizmo.Position = modelCenter;

				// Scale gizmo based on distance from camera
				mGizmo.Size = tab.Camera.Distance * 0.15f;

				// Get viewport bounds in screen space (reuse viewportBounds from above)
				let vpX = viewportBounds.X;
				let vpY = viewportBounds.Y;
				let vpW = mViewport.RenderWidth;
				let vpH = mViewport.RenderHeight;

				// Convert window mouse position to viewport-local coordinates
				float localMouseX = mouse.X - vpX;
				float localMouseY = mouse.Y - vpY;

				// Only interact if mouse is inside viewport
				if (localMouseX >= 0 && localMouseX < vpW && localMouseY >= 0 && localMouseY < vpH)
				{
					// Create pick ray
					let pickRay = TranslateGizmo.CreatePickRay(
						localMouseX, localMouseY, vpW, vpH,
						tab.Camera.ViewMatrix, mView.ProjectionMatrix);

					// Update hover
					mGizmo.UpdateHover(pickRay, mGizmo.Size * 0.15f);

					// Handle drag
					if (mouse.IsButtonPressed(.Left) && mGizmo.HoveredAxis != .None)
					{
						mGizmo.BeginDrag(pickRay);
						mIsDragging = false;  // Prevent camera rotation while dragging gizmo
					}

					if (mGizmo.IsDragging)
					{
						let delta = mGizmo.UpdateDrag(pickRay);
						// Move both model bounds and camera target together
						// (For now we just move the camera target - model transform would need world matrix support)
						tab.Camera.Target += delta;
						mGizmo.Position += delta;
					}
				}

				if (mouse.IsButtonReleased(.Left) && mGizmo.IsDragging)
					mGizmo.EndDrag();
			}

			// Cycle animations (require focus for keyboard input)
			if (mViewport.IsFocused && tab.Clips != null && tab.Clips.Count > 0 && tab.Player != null)
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
					tab.Clips[tab.CurrentClip].IsLooping = true;
					tab.Player.Play(tab.Clips[tab.CurrentClip]);
					Console.WriteLine(scope $"Playing: {tab.Clips[tab.CurrentClip].Name}");
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
				mRenderSystem.ResourceManager.UpdateBoneBuffer(
					tab.BoneBufferHandle,
					currentMatrices.Ptr,
					prevMatrices.Ptr,
					(uint16)tab.Skeleton.BoneCount
				);
			}
		}
	}

	protected override bool OnRender(ICommandEncoder encoder, int32 frameIndex)
	{
		let tab = ActiveTab;

		// Render the 3D viewport content
		if (mViewport != null && mViewport.IsReady)
		{
			let width = mViewport.RenderWidth;
			let height = mViewport.RenderHeight;

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
				mOutputFeature.SetOutputTarget(mViewport.ColorTexture, mViewport.ColorTargetView,
					mViewport.DepthTexture, mViewport.DepthTargetView, width, height);

				// Render via RenderSystem
				mRenderSystem.BeginFrame(TotalTime, DeltaTime);
				mRenderSystem.SetCamera(tab.Camera.Position, tab.Camera.Forward, .(0, 1, 0),
					mView.FieldOfView, mView.AspectRatio, mView.NearPlane, mView.FarPlane, width, height);

				// Draw gizmo (before BuildRenderGraph so debug feature can pick it up)
				if (mGizmo != null && mDebugFeature != null && tab.Model != null)
				{
					mGizmo.Draw(mDebugFeature);
				}

				if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
					mRenderSystem.Execute(encoder);

				mRenderSystem.EndFrame();
			}
			else
			{
				// No active tab - just clear the viewport to a dark color
				RenderPassColorAttachment[1] clearAttachments = .(.(mViewport.ColorTargetView)
					{
						LoadOp = .Clear,
						StoreOp = .Store,
						ClearValue = .(0.1f, 0.1f, 0.12f, 1.0f)
					});
				RenderPassDescriptor clearPassDesc = .(clearAttachments);
				clearPassDesc.DepthStencilAttachment = .(mViewport.DepthTargetView)
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
			encoder.TextureBarrier(mViewport.ColorTexture, .ColorAttachment, .ShaderReadOnly);
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
		mModelInfoLabel = new Label("No model loaded");
		mModelInfoLabel.FontSize = 12;
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

		// Right side: Grid with tabs at top (row 0 auto), viewport fills remaining space (row 1 star)
		mViewportPanel = new Grid();
		mViewportPanel.RowDefinitions.Add(new .() { Height = .Auto });  // Row 0: Tab control (auto height)
		mViewportPanel.RowDefinitions.Add(new .() { Height = .Star });  // Row 1: Viewport (fills remaining)
		mViewportPanel.ColumnDefinitions.Add(new .() { Width = .Star });
		mRootPanel.AddChild(mViewportPanel);

		// Tab control (row 0, hidden when no tabs)
		mTabControl = new TabControl();
		mTabControl.TabStripPlacement = .Top;
		mTabControl.Height = 30;
		mTabControl.Visibility = .Collapsed;
		GridProperties.SetRow(mTabControl, 0);
		mTabControl.SelectionChanged.Subscribe(new (tc) => {
			if (tc.SelectedIndex >= 0 && tc.SelectedIndex != mActiveTabIndex)
				SwitchToTab((int32)tc.SelectedIndex);
		});
		mViewportPanel.AddChild(mTabControl);

		// Subscribe to tab close events
		// Note: We'll handle this when tabs are actually added

		// Viewport container (row 1, Grid to allow overlay)
		mViewportContainer = new Grid();
		mViewportContainer.RowDefinitions.Add(new .() { Height = .Star });
		mViewportContainer.ColumnDefinitions.Add(new .() { Width = .Star });
		GridProperties.SetRow(mViewportContainer, 1);
		mViewportPanel.AddChild(mViewportContainer);

		// 3D Viewport (fills remaining space)
		mViewport = new ViewportControl();
		mViewport.Initialize(Device, mDrawingRenderer);
		mViewport.Background = Color(40, 40, 50, 255);
		mViewport.HorizontalAlignment = .Stretch;
		mViewport.VerticalAlignment = .Stretch;
		mViewportContainer.AddChild(mViewport);

		// Drop indicator overlay (shown when no model loaded)
		mDropIndicator = new Label("Drop a model here\n\nGLTF, GLB, FBX");
		mDropIndicator.FontSize = 20;
		mDropIndicator.Foreground = Color(150, 150, 160, 255);
		mDropIndicator.HorizontalAlignment = .Center;
		mDropIndicator.VerticalAlignment = .Center;
		mViewportContainer.AddChild(mDropIndicator);

		context.RootElement = mRootPanel;

		UpdateModelInfoLabel();
		UpdateEmptyState();
	}

	protected override void OnKeyDown(Sedulous.Shell.Input.KeyCode key)
	{
		let tab = ActiveTab;
		if (key == .R && tab != null && tab.Model != null)
			tab.Camera.FitToModel(tab.Model.Bounds);
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

		// Clean up all tabs
		for (let tab in mTabs)
		{
			tab.Destroy(mRenderSystem);
		}

		// Shutdown render system (this cleans up features, pipelines, etc.)
		mRenderSystem?.Shutdown();

		// Delete view and render system (after shutdown)
		if (mView != null) { delete mView; mView = null; }
		if (mRenderSystem != null) { delete mRenderSystem; mRenderSystem = null; }

		// Clean up UI (after render system since viewport uses it)
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
