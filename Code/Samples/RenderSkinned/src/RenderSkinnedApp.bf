namespace RenderSkinned;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Framework.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Materials;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Imaging;
using Sedulous.Textures.Resources;
using Sedulous.Animation;

/// Skeletal animation sample demonstrating GLTF skinned mesh loading,
/// bone animation playback, and animation cycling via the Sedulous.Render pipeline.
class RenderSkinnedApp : Application
{
	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Render features
	private GPUSkinningFeature mSkinningFeature;
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Model data
	private Model mModel ~ delete _;
	private ModelImportResult mImportResult ~ delete _;
	private Skeleton mSkeleton; // non-owning, from import result
	private AnimationPlayer mPlayer ~ delete _;
	private int32 mCurrentClip = 0;

	// GPU resources
	private GPUMeshHandle mMeshHandle;
	private GPUBoneBufferHandle mBoneBufferHandle;
	private GPUTextureHandle mTextureHandle;
	private SkinnedMeshProxyHandle mMeshProxy;
	private MaterialInstance mMaterial ~ _?.ReleaseRef();

	// Floor
	private GPUMeshHandle mFloorMeshHandle;

	// Lights
	private LightProxyHandle mSunLight;

	// Camera
	private Vector3 mCameraPosition = .(0, 50, 150);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.1f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 50.0f;
	private const float LookSpeed = 0.003f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Framework.Core.Context context)
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
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
		LoadModel();
		CreateLights();

		mWorld.AmbientColor = .(0.05f, 0.05f, 0.08f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Skinned initialized");
		Console.WriteLine("  Left/Right or ,/.: cycle animations");
		Console.WriteLine("  WASD/QE: move, Right-click: look, Tab: capture");
		Console.WriteLine("  ESC: exit");
	}

	private void RegisterFeatures()
	{
		mSkinningFeature = new GPUSkinningFeature();
		if (mRenderSystem.RegisterFeature(mSkinningFeature) case .Err)
			Console.WriteLine("Warning: Failed to register GPUSkinningFeature");

		mDepthFeature = new DepthPrepassFeature();
		if (mRenderSystem.RegisterFeature(mDepthFeature) case .Err)
			Console.WriteLine("Warning: Failed to register DepthPrepassFeature");

		mForwardFeature = new ForwardOpaqueFeature();
		if (mRenderSystem.RegisterFeature(mForwardFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ForwardOpaqueFeature");

		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");

		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");
	}

	private void CreateFloor()
	{
		let planeMesh = StaticMesh.CreatePlane(200.0f, 200.0f, 1, 1);
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

	private void LoadModel()
	{
		GltfModels.Initialize();

		let modelPath = scope $"{AssetDirectory}/samples/models/Fox/glTF/Fox.gltf";
		let gltfBasePath = scope $"{AssetDirectory}/samples/models/Fox/glTF";
		Console.WriteLine("Loading model from: {}", modelPath);

		mModel = new Model();
		if (ModelLoaderFactory.LoadModel(modelPath, mModel) != .Ok)
		{
			Console.WriteLine("ERROR: Failed to load model");
			delete mModel;
			mModel = null;
			return;
		}

		// Import using ModelImporter
		let importOptions = new ModelImportOptions();
		importOptions.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Textures | .Materials;
		importOptions.BasePath.Set(gltfBasePath);

		let importer = scope ModelImporter(importOptions);
		mImportResult = importer.Import(mModel);

		if (!mImportResult.Success || mImportResult.SkinnedMeshes.Count == 0)
		{
			Console.WriteLine("ERROR: Import failed");
			for (let err in mImportResult.Errors)
				Console.WriteLine("  {}", err);
			return;
		}

		for (let warn in mImportResult.Warnings)
			Console.WriteLine("  Warning: {}", warn);

		Console.WriteLine("  Imported: {} skinned meshes, {} skeletons, {} animations, {} textures",
			mImportResult.SkinnedMeshes.Count, mImportResult.Skeletons.Count,
			mImportResult.Animations.Count, mImportResult.Textures.Count);

		// Upload skinned mesh
		let skinnedMesh = mImportResult.SkinnedMeshes[0].Mesh;
		if (mRenderSystem.ResourceManager.UploadMesh(skinnedMesh) case .Ok(let gpuHandle))
			mMeshHandle = gpuHandle;
		else
		{
			Console.WriteLine("ERROR: Failed to upload skinned mesh");
			return;
		}

		// Get skeleton and create animation player
		if (mImportResult.Skeletons.Count > 0)
		{
			mSkeleton = mImportResult.Skeletons[0].Skeleton;
			mPlayer = new AnimationPlayer(mSkeleton);

			let boneCount = (uint16)mSkeleton.BoneCount;
			if (mRenderSystem.ResourceManager.CreateBoneBuffer(boneCount) case .Ok(let boneHandle))
				mBoneBufferHandle = boneHandle;
		}

		// Upload texture from import result
		if (mImportResult.Textures.Count > 0)
		{
			let image = mImportResult.Textures[0].Image;
			if (image != null && image.Width > 0 && image.Height > 0)
			{
				Console.WriteLine("  Texture: {}x{} ({})", image.Width, image.Height, image.Format);
				let gpuFormat = ConvertPixelFormat(image.Format);
				let texData = TextureData.Create2D(image.Data.Ptr, (uint64)image.Data.Length, image.Width, image.Height, gpuFormat);
				if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let texHandle))
				{
					mTextureHandle = texHandle;
					if (let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial)
					{
						mMaterial = new MaterialInstance(baseMat);
						if (let texView = mRenderSystem.ResourceManager.GetTextureView(mTextureHandle))
							mMaterial.SetTexture("AlbedoMap", texView);
					}
				}
			}
		}

		// Create skinned mesh proxy
		mMeshProxy = mWorld.CreateSkinnedMesh();
		if (let proxy = mWorld.GetSkinnedMesh(mMeshProxy))
		{
			proxy.MeshHandle = mMeshHandle;
			proxy.BoneBufferHandle = mBoneBufferHandle;
			proxy.Materials[0] = mMaterial ?? mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(skinnedMesh.Bounds);
			proxy.BoneCount = (uint16)(mSkeleton?.BoneCount ?? 0);
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}

		// Play first animation
		if (mImportResult.Animations.Count > 0 && mPlayer != null)
		{
			let clip = mImportResult.Animations[0].Clip;
			clip.IsLooping = true;
			mPlayer.Play(clip);
			Console.WriteLine("  Playing: {}", clip.Name);
		}
	}

	private void CreateLights()
	{
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -1.0f, 0.3f)),
			.(1.0f, 1.0f, 0.95f),
			2.0f
		);
		if (let light = mWorld.GetLight(mSunLight))
			light.CastsShadows = true;
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mYaw += mouse.DeltaX * LookSpeed;
			mPitch -= mouse.DeltaY * LookSpeed;
			mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
		}

		// Cycle animations
		if (mImportResult != null && mImportResult.Animations.Count > 0 && mPlayer != null)
		{
			let animCount = (int32)mImportResult.Animations.Count;
			bool changed = false;
			if (keyboard.IsKeyPressed(.Right) || keyboard.IsKeyPressed(.Period))
			{
				mCurrentClip = (mCurrentClip + 1) % animCount;
				changed = true;
			}
			if (keyboard.IsKeyPressed(.Left) || keyboard.IsKeyPressed(.Comma))
			{
				mCurrentClip = (mCurrentClip - 1 + animCount) % animCount;
				changed = true;
			}
			if (changed)
			{
				let clip = mImportResult.Animations[mCurrentClip].Clip;
				clip.IsLooping = true;
				mPlayer.Play(clip);
				Console.WriteLine("Playing: {} ({})", clip.Name, mCurrentClip);
			}
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;

		// Update animation
		if (mPlayer != null)
		{
			mPlayer.Update(dt);
			mPlayer.Evaluate();

			// Upload bones
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

		// Camera movement
		let keyboard = mShell.InputManager.Keyboard;
		float speed = keyboard.IsKeyDown(.LeftShift) ? MoveSpeed * 2 : MoveSpeed;

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

		if (move.LengthSquared() > 0)
			mCameraPosition += Vector3.Normalize(move) * speed * dt;

		mCameraForward = Vector3.Normalize(.(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw)));

		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		mRenderSystem.SetCamera(
			mCameraPosition, mCameraForward, .(0, 1, 0),
			mView.FieldOfView, mView.AspectRatio,
			mView.NearPlane, mView.FarPlane,
			mView.Width, mView.Height
		);

		if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		mRenderSystem.EndFrame();
		return true;
	}

	private static TextureFormat ConvertPixelFormat(Sedulous.Imaging.Image.PixelFormat format)
	{
		switch (format)
		{
		case .R8:       return .R8Unorm;
		case .RG8:      return .RG8Unorm;
		case .RGB8:     return .RGBA8Unorm;
		case .RGBA8:    return .RGBA8Unorm;
		case .BGR8:     return .BGRA8Unorm;
		case .BGRA8:    return .BGRA8Unorm;
		case .R16F:     return .R16Float;
		case .RG16F:    return .RG16Float;
		case .RGB16F:   return .RGBA16Float;
		case .RGBA16F:  return .RGBA16Float;
		case .R32F:     return .R32Float;
		case .RG32F:    return .RG32Float;
		case .RGB32F:   return .RGBA32Float;
		case .RGBA32F:  return .RGBA32Float;
		default:        return .RGBA8Unorm;
		}
	}

	protected override void OnShutdown()
	{
		if (mMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mMeshHandle, mRenderSystem.FrameNumber);
		if (mBoneBufferHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseBoneBuffer(mBoneBufferHandle, mRenderSystem.FrameNumber);
		if (mTextureHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseTexture(mTextureHandle, mRenderSystem.FrameNumber);
		if (mFloorMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mFloorMeshHandle, mRenderSystem.FrameNumber);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Render Skinned shutting down");
	}
}
