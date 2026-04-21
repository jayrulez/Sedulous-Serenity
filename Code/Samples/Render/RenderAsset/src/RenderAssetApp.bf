namespace RenderAsset;

using System;
using System.Collections;
using System.IO;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Runtime.Client;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Geometry.Tooling.Resources;
using Sedulous.Materials;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Textures.Resources;
using Sedulous.Imaging;
using Sedulous.Textures;
using Sedulous.Geometry.Resources;
using Sedulous.Serialization.OpenDDL;

/// Asset cache demo demonstrating:
/// - Check for cached assets on startup
/// - Import from GLTF if not cached
/// - Save to cache for faster loading next time
/// - Load skeleton, animations, and textures from cache
class RenderAssetApp : Application
{
	// Render system (cleaned up in OnShutdown, before device destruction)
	private RenderSystem mRenderSystem;
	private RenderWorld mWorld;
	private RenderView mView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	private SkinnedMeshResourceManager mSkinnedMeshResMgr;
	private SkeletonResourceManager mSkeletonResMgr;
	private AnimationClipResourceManager mAnimClipResMgr;
	private TextureResourceManager mTextureResMgr;

	// Model data
	private Model mModel ~ delete _;
	private Skeleton mSkeleton ~ delete _;
	private AnimationPlayer mPlayer ~ delete _;
	private List<AnimationClipResource> mAnimResources ~ {for(var item in _){ item.ReleaseRef(); } delete _;};
	private AnimationClip[] mClips ~ delete _; // non-owning pointers into mAnimResources
	private int32 mCurrentClip = 0;

	// GPU resources
	private GPUMeshHandle mMeshHandle;
	private GPUBoneBufferHandle mBoneBufferHandle;
	private GPUTextureHandle mTextureHandle;
	private SkinnedMeshRenderHandle mMeshProxy;
	private MaterialInstance mMaterial ~ _?.ReleaseRef();

	// Floor
	private GPUMeshHandle mFloorMeshHandle;

	// Lights
	private LightRenderHandle mSunLight = .Invalid;

	// Camera
	private Vector3 mCameraPosition = .(0, 50, 150);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.1f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;

	// Cache tracking
	private bool mLoadedFromCache = false;

	public this() : base()
	{
	}

	protected override void OnInitialize(Sedulous.Runtime.Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		mSkinnedMeshResMgr = new .();
		mSkinnedMeshResMgr.SerializerProvider = context.Resources.SerializerProvider;

		mSkeletonResMgr = new .();
		mSkeletonResMgr.SerializerProvider = context.Resources.SerializerProvider;

		mAnimClipResMgr = new .();
		mAnimClipResMgr.SerializerProvider = context.Resources.SerializerProvider;

		mTextureResMgr = new .();
		mTextureResMgr.SerializerProvider = context.Resources.SerializerProvider;

		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, mSwapChain.Width, mSwapChain.Height, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null, .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}

		mWorld = mRenderSystem.CreateWorld();
		mRenderSystem.SetActiveWorld(mWorld);

		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 500.0f;

		RegisterFeatures();
		CreateFloor();
		LoadFoxModel();
		CreateLights();

		mWorld.AmbientColor = .(0.05f, 0.05f, 0.08f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("");
		Console.WriteLine("=== Asset Cache Demo ===");
		Console.WriteLine(mLoadedFromCache ? "Fox loaded from CACHE (fast path)" : "Fox imported from GLTF (slow path, cached for next time)");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Left/Right=Cycle Anims");
		Console.WriteLine("          Tab=Toggle mouse capture, Shift=Fast, ESC=Exit");
	}

	private void RegisterFeatures()
	{
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void CreateFloor()
	{
		let planeMesh = MeshBuilder.CreatePlane(200.0f, 200.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let handle))
			mFloorMeshHandle = handle;
		delete planeMesh;

		let floor = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(floor))
		{
			proxy.MeshHandle = mFloorMeshHandle;
			proxy.Materials[0] = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-100, 0, -100), Vector3(100, 0.01f, 100)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}
	}

	private void LoadFoxModel()
	{
		let cacheDir = scope $"{AssetDirectory}/cache/RenderAsset";
		let cachePath = scope $"{cacheDir}/fox1.skinnedmesh";
		let gltfPath = scope $"{AssetDirectory}/samples/models/Fox/glTF/Fox.gltf";
		let gltfBasePath = scope $"{AssetDirectory}/samples/models/Fox/glTF";

		SkinnedMesh meshData = null;
		BoundingBox meshBounds = .(.Zero, .Zero);

		// Try to load from cache first
		if (File.Exists(cachePath))
		{
			Console.WriteLine("Checking cache...");
			if (mSkinnedMeshResMgr.Load(cachePath) case .Ok(var meshHandle))
			{
				var resource = meshHandle.Resource as SkinnedMeshResource;
				Console.WriteLine($"  Mesh from cache: {resource.Mesh.VertexCount} vertices");
				meshData = resource.Mesh;
				meshBounds = resource.Mesh.Bounds;

				// Load skeleton from cache
				LoadSkeletonFromCache(cacheDir);

				// Load animations from cache
				LoadAnimationsFromCache(cacheDir);

				// Load texture (try cache first, then PNG)
				LoadTexture(cacheDir);

				mLoadedFromCache = true;

				// We need the mesh data to outlive the resource for upload
				// Upload mesh before deleting the resource
				UploadAndSetupProxy(meshData, meshBounds);
				mSkinnedMeshResMgr.Unload(ref meshHandle);
				meshHandle.Resource.ReleaseRef();

				Console.WriteLine($"  Total: {mSkeleton?.BoneCount ?? 0} bones, {mClips?.Count ?? 0} animations");
				return;
			}
			else
			{
				Console.WriteLine("  Cache file exists but failed to load, falling back to GLTF import...");
			}
		}
		else
		{
			Console.WriteLine($"Cache not found at: {cachePath}");
			Console.WriteLine("Importing from GLTF...");
		}

		// Import from GLTF
		GltfModels.Initialize();
		mModel = new Model();
		if (ModelLoaderFactory.LoadModel(gltfPath, mModel) != .Ok)
		{
			Console.WriteLine("ERROR: Failed to load Fox model");
			delete mModel;
			mModel = null;
			return;
		}

		Console.WriteLine($"  GLTF parsed: {mModel.Meshes.Count} meshes, {mModel.Bones.Count} bones, {mModel.Animations.Count} animations");

		// Use ModelImporter for batch conversion
		let importOptions = new ModelImportOptions();
		importOptions.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Textures | .Materials;
		importOptions.BasePath.Set(gltfBasePath);

		let importer = scope ModelImporter(importOptions);
		let importResult = importer.Import(mModel);
		defer delete importResult;

		if (!importResult.Success || importResult.SkinnedMeshes.Count == 0)
		{
			Console.WriteLine("  Import failed or no skinned meshes found");
			for (let err in importResult.Errors)
				Console.WriteLine($"    Error: {err}");
			return;
		}

		// Save to cache for next time
		Console.WriteLine("Saving to cache...");
		if (!Directory.Exists(cacheDir))
			Directory.CreateDirectory(cacheDir);

		if (ResourceSerializer.SaveImportResult(importResult, cacheDir, Context.Resources.SerializerProvider) case .Ok(let resourceResult))
		{
			Console.WriteLine($"  Saved to: {cacheDir}");
			delete resourceResult;
		}
		else
			Console.WriteLine("  Failed to save cache file");

		// Build skeleton from import result
		if (importResult.Skeletons.Count > 0)
			BuildSkeleton(importResult.Skeletons[0]);

		// Extract animations from GLTF model
		ExtractAnimationsFromModel();

		// Load texture from model (no cache dir for GLTF path)
		LoadTexture("");

		// Use the first skinned mesh
		let mesh = importResult.SkinnedMeshes[0];
		Console.WriteLine($"  Imported: {mesh.VertexCount} vertices, {mSkeleton?.BoneCount ?? 0} bones, {mClips?.Count ?? 0} animations");

		UploadAndSetupProxy(mesh, mesh.Bounds);

		mLoadedFromCache = false;
	}

	private void BuildSkeleton(Skeleton src)
	{
		if (src == null) return;

		let boneCount = src.BoneCount;
		mSkeleton = new Skeleton(boneCount);

		for (int32 j = 0; j < boneCount; j++)
		{
			let srcBone = src.Bones[j];
			let dstBone = mSkeleton.Bones[j];
			dstBone.Name.Set(srcBone.Name);
			dstBone.Index = srcBone.Index;
			dstBone.ParentIndex = srcBone.ParentIndex;
			dstBone.LocalBindPose = srcBone.LocalBindPose;
			dstBone.InverseBindPose = srcBone.InverseBindPose;
			dstBone.RootCorrection = srcBone.RootCorrection;
		}

		mSkeleton.BuildNameMap();
		mSkeleton.FindRootBones();
		mSkeleton.BuildChildIndices();
		mPlayer = new AnimationPlayer(mSkeleton);
	}

	private void LoadSkeletonFromCache(StringView cacheDir)
	{
		for (let entry in Directory.EnumerateFiles(cacheDir))
		{
			let fileName = scope String();
			entry.GetFileName(fileName);
			if (!fileName.EndsWith(".skeleton"))
				continue;

			let skelPath = scope String();
			entry.GetFilePath(skelPath);
			if (mSkeletonResMgr.Load(skelPath) case .Ok(var skelResHandle))
			{
				var skelRes = skelResHandle.Resource as SkeletonResource;
				Console.WriteLine($"  Skeleton from cache: {skelRes.BoneCount} bones");
				BuildSkeleton(skelRes.Skeleton);
				mSkeletonResMgr.Unload(ref skelResHandle);
				skelResHandle.Release();
				return;
			}
		}
		Console.WriteLine("  Warning: No skeleton found in cache");
	}

	private void LoadAnimationsFromCache(StringView cacheDir)
	{
		mAnimResources = new .();

		for (let entry in Directory.EnumerateFiles(cacheDir))
		{
			let fileName = scope String();
			entry.GetFileName(fileName);
			if (!fileName.EndsWith(".animation"))
				continue;

			let animPath = scope String();
			entry.GetFilePath(animPath);
			if (mAnimClipResMgr.Load(animPath) case .Ok(var animRes)){
				mAnimResources.Add((animRes.Resource as AnimationClipResource));
				animRes.Release();
			}
		}

		// Build non-owning clip array for convenient access
		mClips = new AnimationClip[mAnimResources.Count];
		for (int i = 0; i < mAnimResources.Count; i++)
			mClips[i] = mAnimResources[i].Clip;

		if (mClips.Count > 0)
			Console.WriteLine($"  Animations from cache: {mClips.Count} clips");
	}

	private void ExtractAnimationsFromModel()
	{
		if (mModel == null || mModel.Animations.Count == 0 || mModel.Skins.Count == 0)
		{
			mAnimResources = new .();
			mClips = new AnimationClip[0];
			return;
		}

		let skin = mModel.Skins[0];
		Dictionary<int32, int32> boneToJoint = scope .();
		for (int32 j = 0; j < (int32)skin.Joints.Count; j++)
			boneToJoint[skin.Joints[j]] = j;

		mAnimResources = new .();

		for (int i = 0; i < mModel.Animations.Count; i++)
		{
			let modelAnim = mModel.Animations[i];
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
			mAnimResources.Add(animRes);
		}

		// Build non-owning clip array
		mClips = new AnimationClip[mAnimResources.Count];
		for (int i = 0; i < mAnimResources.Count; i++)
			mClips[i] = mAnimResources[i].Clip;
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

	private void LoadTexture(StringView cacheDir)
	{
		// Try cached texture first
		if (cacheDir.Length > 0)
		{
			for (let entry in Directory.EnumerateFiles(cacheDir))
			{
				let fileName = scope String();
				entry.GetFileName(fileName);
				if (!fileName.EndsWith(".texture"))
					continue;

				let texPath = scope String();
				entry.GetFilePath(texPath);
				if (mTextureResMgr.Load(texPath) case .Ok(var texResHandle))
				{
					var texRes = texResHandle.Resource as TextureResource;
					let img = texRes.Image;
					Console.WriteLine($"  Texture from cache: {img.Width}x{img.Height}");

					let texData = TextureData.FromImage(img);
					if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let texHandle))
					{
						mTextureHandle = texHandle;
						CreateFoxMaterial();
					}
					mTextureResMgr.Unload(ref texResHandle);
					texResHandle.Release();
					return;
				}
			}
		}

		// Fall back to loading from PNG
		let texPath = scope $"{AssetDirectory}/samples/models/Fox/glTF/Texture.png";
		if (ImageLoaderFactory.LoadImage(texPath) case .Ok(var image))
		{
			defer delete image;
			Console.WriteLine($"  Texture from PNG: {image.Width}x{image.Height}");

			int pixelCount = (int)image.Width * (int)image.Height;
			int channels = image.Data.Length / pixelCount;
			uint8* pixelData = image.Data.Ptr;
			uint8[] rgbaData = null;

			if (channels == 3)
			{
				rgbaData = new uint8[pixelCount * 4];
				for (int p = 0; p < pixelCount; p++)
				{
					rgbaData[p * 4 + 0] = image.Data[p * 3 + 0];
					rgbaData[p * 4 + 1] = image.Data[p * 3 + 1];
					rgbaData[p * 4 + 2] = image.Data[p * 3 + 2];
					rgbaData[p * 4 + 3] = 255;
				}
				pixelData = &rgbaData[0];
			}

			let texData = TextureData.Create2D(pixelData, (uint64)image.Width * (uint64)image.Height * 4, image.Width, image.Height, Sedulous.Textures.TextureFormatUtils.Convert(image.Format));
			if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let texHandle))
			{
				mTextureHandle = texHandle;
				CreateFoxMaterial();
			}
			delete rgbaData;
		}
	}

	private void CreateFoxMaterial()
	{
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMat != null)
		{
			mMaterial = new MaterialInstance(baseMat);
			mMaterial.SetColor("BaseColor", .(1, 1, 1, 1));
			mMaterial.SetFloat("Metallic", 0.0f);
			mMaterial.SetFloat("Roughness", 0.6f);
			if (let texView = mRenderSystem.ResourceManager.GetTextureView(mTextureHandle))
				mMaterial.SetTexture("AlbedoMap", texView);
		}
	}

	private void UploadAndSetupProxy(SkinnedMesh skinnedMesh, BoundingBox bounds)
	{
		if (mRenderSystem.ResourceManager.UploadMesh(skinnedMesh) case .Ok(let gpuHandle))
		{
			mMeshHandle = gpuHandle;

			let boneCount = (uint16)(mSkeleton?.BoneCount ?? 0);
			if (boneCount > 0)
			{
				if (mRenderSystem.ResourceManager.CreateBoneBuffer(boneCount) case .Ok(let boneHandle))
					mBoneBufferHandle = boneHandle;
			}

			// Create skinned mesh proxy
			mMeshProxy = mWorld.CreateSkinnedMesh();
			if (let proxy = mWorld.GetSkinnedMesh(mMeshProxy))
			{
				proxy.MeshHandle = mMeshHandle;
				proxy.BoneBufferHandle = mBoneBufferHandle;
				proxy.Materials[0] = mMaterial ?? mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(bounds);
				proxy.BoneCount = boneCount;
				proxy.SetTransformImmediate(.Identity);
				proxy.Flags = .DefaultOpaque;
			}

			// Play first animation
			if (mClips != null && mClips.Count > 0 && mPlayer != null)
			{
				mClips[0].IsLooping = true;
				mPlayer.Play(mClips[0]);
				Console.WriteLine($"  Playing: {mClips[0].Name}");
			}
		}
	}

	private void CreateLights()
	{
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -1.0f, 0.3f)),
			.(1.0f, 1.0f, 0.95f), 2.5f);
		if (let light = mWorld.GetLight(mSunLight))
			light.CastsShadows = true;
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;

		mWorld.CreatePointLight(.(0, 50, 50), .(0.8f, 0.9f, 1.0f), 5.0f, 80.0f);
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;
		if (keyboard.IsKeyPressed(.Escape)) Exit();

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mYaw += mouse.DeltaX * 0.003f;
			mPitch -= mouse.DeltaY * 0.003f;
			mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
		}

		// Cycle animations
		if (mClips != null && mClips.Count > 0 && mPlayer != null)
		{
			bool changed = false;
			if (keyboard.IsKeyPressed(.Right) || keyboard.IsKeyPressed(.Period))
			{
				mCurrentClip = (mCurrentClip + 1) % (int32)mClips.Count;
				changed = true;
			}
			if (keyboard.IsKeyPressed(.Left) || keyboard.IsKeyPressed(.Comma))
			{
				mCurrentClip = (mCurrentClip - 1 + (int32)mClips.Count) % (int32)mClips.Count;
				changed = true;
			}
			if (changed)
			{
				mClips[mCurrentClip].IsLooping = true;
				mPlayer.Play(mClips[mCurrentClip]);
				Console.WriteLine("Playing: {}", mClips[mCurrentClip].Name);
			}
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;
		let keyboard = mShell.InputManager.Keyboard;
		float speed = (keyboard.IsKeyDown(.LeftShift) ? 100.0f : 50.0f) * dt;

		float cosP = Math.Cos(mPitch);
		Vector3 forward = .(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw));
		Vector3 right = Vector3.Normalize(Vector3.Cross(forward, .(0, 1, 0)));
		Vector3 move = .Zero;
		if (keyboard.IsKeyDown(.W)) move += forward;
		if (keyboard.IsKeyDown(.S)) move -= forward;
		if (keyboard.IsKeyDown(.D)) move += right;
		if (keyboard.IsKeyDown(.A)) move -= right;
		if (keyboard.IsKeyDown(.E)) move += .(0, 1, 0);
		if (keyboard.IsKeyDown(.Q)) move -= .(0, 1, 0);
		if (move.LengthSquared() > 0) mCameraPosition += Vector3.Normalize(move) * speed;

		mCameraForward = Vector3.Normalize(.(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw)));

		// Update animation
		if (mPlayer != null)
		{
			mPlayer.Update(dt);
			mPlayer.Evaluate();

			// Upload bone matrices
			if (mBoneBufferHandle.IsValid)
			{
				let currentMatrices = mPlayer.GetSkinningMatrices();
				let prevMatrices = mPlayer.GetPrevSkinningMatrices();
				mRenderSystem.ResourceManager.UpdateBoneBuffer(
					mBoneBufferHandle,
					currentMatrices.Ptr,
					prevMatrices.Ptr,
					(uint16)mSkeleton.BoneCount
				);
			}
		}

		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices();
	}

	protected override void OnResize(int32 width, int32 height)
	{
		mRenderSystem?.SetViewportSize((uint32)width, (uint32)height);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);
		if (mFinalOutputFeature != null) mFinalOutputFeature.SetSwapChain(render.SwapChain);
		mRenderSystem.SetCamera(mCameraPosition, mCameraForward, .(0, 1, 0),
			mView.FieldOfView, mView.AspectRatio, mView.NearPlane, mView.FarPlane, mView.Width, mView.Height);
		if (mRenderSystem.BuildRenderGraph(mView) case .Ok) mRenderSystem.Execute(render.Encoder);
		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		mWorld?.Dispose();

		if (mRenderSystem != null)
		{
			if (mMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mMeshHandle, mRenderSystem.FrameNumber);
			if (mFloorMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mFloorMeshHandle, mRenderSystem.FrameNumber);
			if (mBoneBufferHandle.IsValid) mRenderSystem.ResourceManager.ReleaseBoneBuffer(mBoneBufferHandle, mRenderSystem.FrameNumber);
			if (mTextureHandle.IsValid) mRenderSystem.ResourceManager.ReleaseTexture(mTextureHandle, mRenderSystem.FrameNumber);
			mRenderSystem.Shutdown();
			delete mRenderSystem;
			mRenderSystem = null;
		}
		delete mWorld;
		delete mView;

		delete mSkinnedMeshResMgr;
		delete mSkeletonResMgr;
		delete mAnimClipResMgr;
		delete mTextureResMgr;
		Console.WriteLine("Render Asset shutting down");
	}
}
