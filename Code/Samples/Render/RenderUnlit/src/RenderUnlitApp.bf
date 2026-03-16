namespace RenderUnlit;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Runtime.Client;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Materials;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Animation;
using Sedulous.Imaging;

/// Unlit material sample demonstrating unlit vs PBR materials side-by-side
/// with animated Fox models via the Sedulous.Render pipeline.
class RenderUnlitApp : Application
{
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Features
	private GPUSkinningFeature mSkinningFeature;
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private OverlayRenderFeature mOverlayFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;

	// Fox (shared resources — skeleton/clips owned by import result)
	private ModelImportResult mFoxImportResult ~ delete _;
	private Model mFoxSourceModel ~ delete _;
	private Skeleton mSkeleton; // Non-owning ref into import result
	private GPUMeshHandle mFoxMeshHandle;
	private GPUTextureHandle mFoxTextureHandle;

	// Fox instances (3 foxes with separate animation/bones)
	private const int FOX_COUNT = 3;
	private SkinnedMeshProxyHandle[FOX_COUNT] mFoxProxies;
	private GPUBoneBufferHandle[FOX_COUNT] mBoneBufferHandles;
	private AnimationPlayer[FOX_COUNT] mPlayers ~ { for (let p in _) delete p; };

	// Lights
	private LightProxyHandle mSunLight = .Invalid;
	private float mLightYaw = 0.5f;
	private float mLightPitch = -0.7f;

	// Materials
	private List<MaterialInstance> mMaterials = new .() ~ { for (let m in _) m?.ReleaseRef(); delete _; };
	private Material mUnlitBaseMaterial ~ delete _;

	// Camera
	private Vector3 mCameraPosition = .(0, 5, 15);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.3f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;

	public this(IShell shell, IDevice device, IBackend backend) : base(shell, device, backend) { }

	protected override void OnInitialize(Sedulous.Runtime.Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null, .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{ Console.WriteLine("ERROR: Failed to initialize RenderSystem"); return; }

		mWorld = mRenderSystem.CreateWorld();
		mRenderSystem.SetActiveWorld(mWorld);

		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 100.0f;

		RegisterFeatures();
		CreateScene();
		CreateLights();
		LoadFoxModel();

		mWorld.AmbientColor = .(0.05f, 0.05f, 0.08f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Unlit initialized");
		Console.WriteLine("  Top row: UNLIT cubes (constant color, ignores lighting)");
		Console.WriteLine("  Bottom row: PBR cubes (affected by lighting)");
		Console.WriteLine("  3 Foxes: PBR (left), UNLIT (center), Default (right)");
		Console.WriteLine("  Arrow keys: adjust light direction");
		Console.WriteLine("  WASD/QE: move, Right-click: look, ESC: exit");
	}

	private void RegisterFeatures()
	{
		mSkinningFeature = new GPUSkinningFeature();
		mRenderSystem.RegisterFeature(mSkinningFeature);

		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		mOverlayFeature = new OverlayRenderFeature();
		mRenderSystem.RegisterFeature(mOverlayFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void CreateScene()
	{
		let cubeMesh = MeshBuilder.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let h)) mCubeMeshHandle = h;
		delete cubeMesh;

		let planeMesh = MeshBuilder.CreatePlane(30.0f, 30.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let h2)) mPlaneMeshHandle = h2;
		delete planeMesh;

		let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;

		// Create unlit base material
		mUnlitBaseMaterial = Materials.CreateUnlit("unlit_base");

		// Floor - gray, matching RendererUnlit ground surface at y=-1.4
		MaterialInstance floorMat = null;
		if (baseMat != null)
		{
			floorMat = new MaterialInstance(baseMat);
			floorMat.SetColor("BaseColor", .(0.3f, 0.3f, 0.3f, 1.0f));
			floorMat.SetFloat("Roughness", 0.9f);
			mMaterials.Add(floorMat);
		}

		let floor = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(floor))
		{
			proxy.MeshHandle = mPlaneMeshHandle;
			proxy.Materials[0] = floorMat ?? defaultMat;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-15, 0, -15), Vector3(15, 0.01f, 15)));
			proxy.SetTransformImmediate(Matrix.CreateTranslation(.(0, -1.4f, 0)));
			proxy.Flags = .DefaultOpaque;
		}

		// Cube colors matching RendererUnlit
		Vector4[8] colors = .(
			.(1.0f, 0.3f, 0.3f, 1.0f),  // Red
			.(0.3f, 1.0f, 0.3f, 1.0f),  // Green
			.(0.3f, 0.3f, 1.0f, 1.0f),  // Blue
			.(1.0f, 1.0f, 0.3f, 1.0f),  // Yellow
			.(1.0f, 0.3f, 1.0f, 1.0f),  // Magenta
			.(0.3f, 1.0f, 1.0f, 1.0f),  // Cyan
			.(1.0f, 0.6f, 0.3f, 1.0f),  // Orange
			.(0.6f, 0.3f, 1.0f, 1.0f)   // Purple
		);

		float spacing = 2.0f;
		float startX = -((8 - 1) * spacing) / 2.0f;

		// Front row: Unlit cubes at z=-2
		for (int i = 0; i < 8; i++)
		{
			let mat = new MaterialInstance(mUnlitBaseMaterial);
			mat.SetColor("BaseColor", colors[i]);
			mMaterials.Add(mat);

			let cube = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(cube))
			{
				proxy.MeshHandle = mCubeMeshHandle;
				proxy.Materials[0] = mat;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
				proxy.SetTransformImmediate(Matrix.CreateTranslation(.(startX + i * spacing, 1.5f, -2.0f)));
				proxy.Flags = .DefaultOpaque;
			}
		}

		// Back row: PBR cubes at z=2
		for (int i = 0; i < 8; i++)
		{
			MaterialInstance mat = null;
			if (baseMat != null)
			{
				mat = new MaterialInstance(baseMat);
				mat.SetColor("BaseColor", colors[i]);
				mat.SetFloat("Roughness", 0.5f);
				mat.SetFloat("Metallic", 0.0f);
				mMaterials.Add(mat);
			}

			let cube = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(cube))
			{
				proxy.MeshHandle = mCubeMeshHandle;
				proxy.Materials[0] = mat ?? defaultMat;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
				proxy.SetTransformImmediate(Matrix.CreateTranslation(.(startX + i * spacing, 1.5f, 2.0f)));
				proxy.Flags = .DefaultOpaque;
			}
		}
	}

	private void CreateLights()
	{
		let lightDir = GetLightDirection();
		mSunLight = mWorld.CreateDirectionalLight(lightDir, .(1.0f, 0.98f, 0.9f), 2.0f);
		if (let light = mWorld.GetLight(mSunLight)) light.CastsShadows = true;
		if (mForwardFeature?.ShadowRenderer != null) mForwardFeature.ShadowRenderer.EnableShadows = true;
	}

	private Vector3 GetLightDirection()
	{
		float cosP = Math.Cos(mLightPitch);
		return Vector3.Normalize(.(
			Math.Sin(mLightYaw) * cosP,
			Math.Sin(mLightPitch),
			Math.Cos(mLightYaw) * cosP
		));
	}

	private void UpdateLightDirection()
	{
		if (let light = mWorld.GetLight(mSunLight))
			light.Direction = GetLightDirection();
	}

	// ==================== Fox Model ====================

	private void LoadFoxModel()
	{
		GltfModels.Initialize();

		let modelPath = scope $"{AssetDirectory}/samples/models/Fox/glTF/Fox.gltf";
		mFoxSourceModel = new Model();
		if (ModelLoaderFactory.LoadModel(modelPath, mFoxSourceModel) != .Ok)
		{
			Console.WriteLine("Warning: Failed to load Fox model");
			delete mFoxSourceModel;
			mFoxSourceModel = null;
			return;
		}

		// Import using ModelImporter (handles skeleton, animations, mesh, textures)
		let importOptions = new ModelImportOptions();
		importOptions.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Textures;
		let lastSlash = modelPath.LastIndexOf('/');
		if (lastSlash >= 0)
			importOptions.BasePath.Set(StringView(modelPath, 0, lastSlash));

		let importer = scope ModelImporter(importOptions);
		mFoxImportResult = importer.Import(mFoxSourceModel);

		if (!mFoxImportResult.Success || mFoxImportResult.SkinnedMeshes.Count == 0 || mFoxImportResult.Skeletons.Count == 0)
		{
			Console.WriteLine("Warning: Fox model import failed");
			for (let err in mFoxImportResult.Errors)
				Console.WriteLine("  {}", err);
			return;
		}

		mSkeleton = mFoxImportResult.Skeletons[0];
		let skinnedMesh = mFoxImportResult.SkinnedMeshes[0];

		if (mRenderSystem.ResourceManager.UploadMesh(skinnedMesh) case .Ok(let gpuHandle))
		{
			mFoxMeshHandle = gpuHandle;
			let boneCount = (uint16)mSkeleton.BoneCount;

			// Upload texture from import result
			if (mFoxImportResult.Textures.Count > 0)
				if (let image = mFoxImportResult.Textures[0].PixelData)
					if (mRenderSystem.ResourceManager.UploadTexture(TextureData.FromImage(image)) case .Ok(let texHandle))
						mFoxTextureHandle = texHandle;

			// Create materials for each fox
			let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
			let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

			// Fox 0 (PBR): textured PBR material
			MaterialInstance foxPBRMat = null;
			if (baseMat != null)
			{
				foxPBRMat = new MaterialInstance(baseMat);
				foxPBRMat.SetColor("BaseColor", .(1, 1, 1, 1));
				foxPBRMat.SetFloat("Metallic", 0.0f);
				foxPBRMat.SetFloat("Roughness", 0.6f);
				if (mFoxTextureHandle.IsValid)
					if (let texView = mRenderSystem.ResourceManager.GetTextureView(mFoxTextureHandle))
						foxPBRMat.SetTexture("AlbedoMap", texView);
				mMaterials.Add(foxPBRMat);
			}

			// Fox 1 (Unlit): textured unlit material
			MaterialInstance foxUnlitMat = null;
			if (mUnlitBaseMaterial != null)
			{
				foxUnlitMat = new MaterialInstance(mUnlitBaseMaterial);
				foxUnlitMat.SetColor("BaseColor", .(1, 1, 1, 1));
				if (mFoxTextureHandle.IsValid)
					if (let texView = mRenderSystem.ResourceManager.GetTextureView(mFoxTextureHandle))
						foxUnlitMat.SetTexture("AlbedoMap", texView);
				mMaterials.Add(foxUnlitMat);
			}

			// Fox positions matching RendererUnlit
			float foxSpacing = 8.0f;
			float foxZ = -4.0f;
			Vector3[FOX_COUNT] foxPositions = .(
				.(-foxSpacing, -1.4f, foxZ),  // PBR (left)
				.(0, -1.4f, foxZ),             // Unlit (center)
				.(foxSpacing, -1.4f, foxZ)     // Default (right)
			);
			float[FOX_COUNT] foxYaws = .(
				Math.PI_f * 0.25f,   // Angled right
				Math.PI_f,           // Facing camera
				-Math.PI_f * 0.25f   // Angled left
			);
			MaterialInstance[FOX_COUNT] foxMats = .(
				foxPBRMat,
				foxUnlitMat,
				defaultMat    // No material = default gray PBR
			);

			let clips = mFoxImportResult.Animations;

			for (int f = 0; f < FOX_COUNT; f++)
			{
				if (mRenderSystem.ResourceManager.CreateBoneBuffer(boneCount) case .Ok(let boneHandle))
				{
					mBoneBufferHandles[f] = boneHandle;
					mPlayers[f] = new AnimationPlayer(mSkeleton);

					mFoxProxies[f] = mWorld.CreateSkinnedMesh();
					if (let proxy = mWorld.GetSkinnedMesh(mFoxProxies[f]))
					{
						proxy.MeshHandle = mFoxMeshHandle;
						proxy.BoneBufferHandle = boneHandle;
						proxy.Materials[0] = foxMats[f] ?? defaultMat;
						proxy.MaterialCount = 1;
						proxy.SetLocalBounds(skinnedMesh.Bounds);
						proxy.BoneCount = boneCount;

						let transform = Matrix.CreateScale(0.04f)
							* Matrix.CreateRotationY(foxYaws[f])
							* Matrix.CreateTranslation(foxPositions[f]);
						proxy.SetTransformImmediate(transform);
						proxy.Flags = .DefaultOpaque;
					}

					// Each fox plays a different animation clip
					if (clips.Count > 0)
					{
						int clipIndex = Math.Min(f, clips.Count - 1);
						let clip = clips[clipIndex];
						clip.IsLooping = true;
						mPlayers[f].Play(clip);
					}
				}
			}

			Console.WriteLine("  Fox 1: PBR material (left)");
			Console.WriteLine("  Fox 2: UNLIT material (center)");
			Console.WriteLine("  Fox 3: Default gray PBR (right)");
		}
	}

	// ==================== Input / Update / Render ====================

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;
		if (keyboard.IsKeyPressed(.Escape)) Exit();
		if (keyboard.IsKeyPressed(.Tab))
		{ mMouseCaptured = !mMouseCaptured; mouse.RelativeMode = mMouseCaptured; mouse.Visible = !mMouseCaptured; }
		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{ mYaw += mouse.DeltaX * 0.003f; mPitch -= mouse.DeltaY * 0.003f; mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f); }
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;
		let keyboard = mShell.InputManager.Keyboard;
		float speed = keyboard.IsKeyDown(.LeftShift) ? 20.0f : 10.0f;
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
		if (move.LengthSquared() > 0) mCameraPosition += Vector3.Normalize(move) * speed * dt;

		// Light direction control
		float lightSpeed = 1.0f * dt;
		bool lightChanged = false;
		if (keyboard.IsKeyDown(.Left))  { mLightYaw -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Right)) { mLightYaw += lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Up))    { mLightPitch -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Down))  { mLightPitch += lightSpeed; lightChanged = true; }
		mLightPitch = Math.Clamp(mLightPitch, -Math.PI_f * 0.45f, -0.1f);
		if (lightChanged) UpdateLightDirection();

		// Update fox animations
		for (int f = 0; f < FOX_COUNT; f++)
		{
			if (mPlayers[f] != null)
			{
				mPlayers[f].Update(dt);
				mPlayers[f].Evaluate();

				if (mBoneBufferHandles[f].IsValid)
				{
					let currentMatrices = mPlayers[f].GetSkinningMatrices();
					let prevMatrices = mPlayers[f].GetPrevSkinningMatrices();
					mRenderSystem.ResourceManager.UpdateBoneBuffer(
						mBoneBufferHandles[f],
						currentMatrices.Ptr,
						prevMatrices.Ptr,
						(uint16)mSkeleton.BoneCount
					);
				}
			}
		}

		// Debug drawing
		UpdateDebugDrawing();

		mCameraForward = Vector3.Normalize(.(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw)));
		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	private void UpdateDebugDrawing()
	{
		if (mOverlayFeature == null) return;

		let lightDir = GetLightDirection();
		let lightStart = Vector3(0, 5, 0);
		let lightEnd = lightStart + lightDir * 5.0f;

		// XYZ axes
		mOverlayFeature.AddAxes(lightStart, 1.5f, .Overlay);

		// Yellow line for light direction
		mOverlayFeature.AddLine(lightStart, lightEnd, .(255, 255, 0, 255), .Overlay);

		// Arrow head (orange)
		let arrowRight = Vector3.Normalize(Vector3.Cross(lightDir, Vector3.Up));
		let arrowUp = Vector3.Normalize(Vector3.Cross(arrowRight, lightDir));
		let arrowSize = 0.3f;
		let arrowColor = Color(255, 128, 0, 255);

		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize + arrowRight * arrowSize * 0.5f, arrowColor, .Overlay);
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize - arrowRight * arrowSize * 0.5f, arrowColor, .Overlay);
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize + arrowUp * arrowSize * 0.5f, arrowColor, .Overlay);
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize - arrowUp * arrowSize * 0.5f, arrowColor, .Overlay);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);
		if (mFinalOutputFeature != null) mFinalOutputFeature.SetSwapChain(render.SwapChain);
		mRenderSystem.SetCamera(mCameraPosition, mCameraForward, .(0, 1, 0), mView.FieldOfView, mView.AspectRatio, mView.NearPlane, mView.FarPlane, mView.Width, mView.Height);
		if (mRenderSystem.BuildRenderGraph(mView) case .Ok) mRenderSystem.Execute(render.Encoder);
		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		mWorld?.Dispose();

		if (mCubeMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mPlaneMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);
		if (mFoxMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mFoxMeshHandle, mRenderSystem.FrameNumber);
		if (mFoxTextureHandle.IsValid) mRenderSystem.ResourceManager.ReleaseTexture(mFoxTextureHandle, mRenderSystem.FrameNumber);

		for (int f = 0; f < FOX_COUNT; f++)
		{
			if (mBoneBufferHandles[f].IsValid)
				mRenderSystem.ResourceManager.ReleaseBoneBuffer(mBoneBufferHandles[f], mRenderSystem.FrameNumber);
		}

		mRenderSystem?.Shutdown();
		Console.WriteLine("Render Unlit shutting down");
	}
}
