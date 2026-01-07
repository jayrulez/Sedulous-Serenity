namespace RendererUnlit;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Imaging;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Framework.Core;
using Sedulous.Framework.Renderer;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Debug;
using SampleFramework;

/// Debug line vertex
[CRepr]
struct LineVertex
{
	public Vector3 Position;
	public Vector4 Color;

	public this(Vector3 pos, Vector4 col)
	{
		Position = pos;
		Color = col;
	}
}

/// Demonstrates Unlit materials vs PBR materials.
/// Shows how unlit materials are not affected by lighting.
class RendererUnlitSample : RHISampleApp
{
	// Framework.Core components
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;

	// Renderer components
	private RendererService mRendererService;
	private RenderSceneComponent mRenderSceneComponent;

	// Material handles
	private MaterialHandle mUnlitMaterial = .Invalid;
	private MaterialHandle mPBRMaterial = .Invalid;
	private List<MaterialInstanceHandle> mUnlitInstances = new .() ~ delete _;
	private List<MaterialInstanceHandle> mPBRInstances = new .() ~ delete _;
	private MaterialInstanceHandle mGroundMaterial = .Invalid;

	// Fox resources
	private SkinnedMeshResource mFoxResource ~ delete _;
	private GPUTextureHandle mFoxTexture = .Invalid;
	private MaterialInstanceHandle mFoxPBRMaterial = .Invalid;
	private MaterialInstanceHandle mFoxUnlitMaterial = .Invalid;
	// Note: Third fox has no material assigned (uses default)

	// Camera entity and control
	private Entity mCameraEntity;
	private float mCameraYaw = Math.PI_f;
	private float mCameraPitch = -0.3f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 10.0f;
	private float mCameraLookSpeed = 0.003f;

	// Light direction control
	private Entity mSunLightEntity;
	private float mLightYaw = 0.5f;
	private float mLightPitch = -0.7f;
	private float mLightIntensity = 2.0f;

	// Debug line rendering
	private const int32 MAX_DEBUG_LINES = 100;
	private IRenderPipeline mLinePipeline;
	private IBindGroupLayout mLineBindGroupLayout;
	private IPipelineLayout mLinePipelineLayout;
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mLineVertexBuffers;
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mLineUniformBuffers;
	private IBindGroup[MAX_FRAMES_IN_FLIGHT] mLineBindGroups;
	private List<LineVertex> mDebugLines = new .() ~ delete _;

	// Current frame index
	private int32 mCurrentFrameIndex = 0;

	public this() : base(.()
	{
		Title = "Unlit Material Demo",
		Width = 1280,
		Height = 720,
		ClearColor = .(0.05f, 0.05f, 0.1f, 1.0f),
		EnableDepth = true
	})
	{
	}

	protected override bool OnInitialize()
	{
		// Create logger
		mLogger = new DebugLogger(.Information);

		// Initialize Framework.Core context
		mContext = new Context(mLogger, 4);

		// Create and register RendererService
		mRendererService = new RendererService();
		let shaderPath = GetAssetPath("framework/shaders", .. scope .());
		if (mRendererService.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}
		mContext.RegisterService<RendererService>(mRendererService);

		// Create scene with RenderSceneComponent
		mScene = mContext.SceneManager.CreateScene("UnlitScene");
		mRenderSceneComponent = mScene.AddSceneComponent(new RenderSceneComponent(mRendererService));

		// Initialize rendering
		if (mRenderSceneComponent.InitializeRendering(SwapChain.Format, .Depth24PlusStencil8, Device.FlipProjectionRequired) case .Err)
		{
			Console.WriteLine("Failed to initialize scene rendering");
			return false;
		}

		// Load fox model
		LoadFox();

		// Create materials and entities
		CreateMaterials();
		CreateEntities();

		// Set active scene and start context
		mContext.SceneManager.SetActiveScene(mScene);
		mContext.Startup();

		// Create debug line pipeline
		if (!CreateLinePipeline())
		{
			Console.WriteLine("Failed to create line pipeline");
			return false;
		}

		Console.WriteLine("Unlit Material Demo initialized");
		Console.WriteLine("Top row: UNLIT cubes (constant color, ignores lighting)");
		Console.WriteLine("Bottom row: PBR cubes (affected by lighting)");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Tab=Toggle mouse capture, Shift=Fast");
		Console.WriteLine("          Arrow keys=Light direction, Z/X=Light intensity");

		return true;
	}

	private void LoadFox()
	{
		// Asset paths (relative to AssetDirectory)
		let cachedPath = GetAssetPath("cache/Fox.skinnedmesh", .. scope .());
		let gltfPath = GetAssetPath("samples/models/Fox/glTF/Fox.gltf", .. scope .());
		let gltfBasePath = GetAssetPath("samples/models/Fox/glTF", .. scope .());

		// Try to load from cache first
		if (File.Exists(cachedPath))
		{
			Console.WriteLine("Loading Fox from cache...");
			if (ResourceSerializer.LoadSkinnedMeshBundle(cachedPath) case .Ok(let resource))
			{
				mFoxResource = resource;
				Console.WriteLine($"  Loaded: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.AnimationCount} animations");
			}
			else
			{
				Console.WriteLine("  Cache file exists but failed to load, falling back to GLTF import...");
			}
		}

		// Import from GLTF if not loaded from cache
		if (mFoxResource == null)
		{
			Console.WriteLine("Importing Fox from GLTF...");
			let foxModel = scope Model();
			let loader = scope GltfLoader();

			let result = loader.Load(gltfPath, foxModel);
			if (result != .Ok)
			{
				Console.WriteLine($"  Failed to load Fox model: {result}");
				return;
			}

			Console.WriteLine($"  GLTF parsed: {foxModel.Meshes.Count} meshes, {foxModel.Bones.Count} bones, {foxModel.Animations.Count} animations");

			// Use ModelImporter to convert all resources
			let importOptions = new ModelImportOptions();
			importOptions.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Textures | .Materials;
			importOptions.BasePath.Set(gltfBasePath);

			let imageLoader = scope SDLImageLoader();
			let importer = scope ModelImporter(importOptions, imageLoader);
			let importResult = importer.Import(foxModel);
			defer delete importResult;

			if (!importResult.Success || importResult.SkinnedMeshes.Count == 0)
			{
				Console.WriteLine("  Import failed or no skinned meshes found");
				for (let err in importResult.Errors)
					Console.WriteLine($"    Error: {err}");
				return;
			}

			// Take ownership of the first skinned mesh
			mFoxResource = importResult.TakeSkinnedMesh(0);
			Console.WriteLine($"  Imported: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.AnimationCount} animations");

			// Save to cache for next time
			let cacheDir = Path.GetDirectoryPath(cachedPath, .. scope .());
			if (!Directory.Exists(cacheDir))
				Directory.CreateDirectory(cacheDir);

			if (ResourceSerializer.SaveSkinnedMeshBundle(mFoxResource, cachedPath) case .Ok)
				Console.WriteLine($"  Saved to cache: {cachedPath}");
		}

		// Load fox texture
		let texPath = GetAssetPath("samples/models/Fox/glTF/Texture.png", .. scope .());
		let resourceManager = mRendererService.ResourceManager;

		if (resourceManager != null)
		{
			let imageLoader = scope SDLImageLoader();
			if (imageLoader.LoadFromFile(texPath) case .Ok(var loadInfo))
			{
				defer loadInfo.Dispose();
				Console.WriteLine($"Fox texture: {loadInfo.Width}x{loadInfo.Height}");

				mFoxTexture = resourceManager.CreateTextureFromData(
					loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .(loadInfo.Data.Ptr, loadInfo.Data.Count));

				if (mFoxTexture.IsValid)
					Console.WriteLine("Fox texture uploaded to GPU");
			}
			else
			{
				Console.WriteLine($"Failed to load fox texture: {texPath}");
			}
		}
	}

	private void CreateMaterials()
	{
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null)
		{
			Console.WriteLine("MaterialSystem not available!");
			return;
		}

		// Create Unlit material
		let unlitMaterial = Material.CreateUnlit("UnlitMaterial");
		mUnlitMaterial = materialSystem.RegisterMaterial(unlitMaterial);
		if (!mUnlitMaterial.IsValid)
		{
			Console.WriteLine("Failed to register Unlit material");
			return;
		}
		Console.WriteLine("Created Unlit material");

		// Create PBR material for comparison
		let pbrMaterial = Material.CreatePBR("PBRMaterial");
		mPBRMaterial = materialSystem.RegisterMaterial(pbrMaterial);
		if (!mPBRMaterial.IsValid)
		{
			Console.WriteLine("Failed to register PBR material");
			return;
		}
		Console.WriteLine("Created PBR material");

		// Create unlit material instances with different colors
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

		// Create unlit instances
		for (int32 i = 0; i < 8; i++)
		{
			let instance = materialSystem.CreateInstance(mUnlitMaterial);
			if (instance.IsValid)
			{
				let inst = materialSystem.GetInstance(instance);
				if (inst != null)
				{
					inst.SetFloat4("color", colors[i]);
					materialSystem.UploadInstance(instance);
				}
				mUnlitInstances.Add(instance);
			}
		}
		Console.WriteLine($"Created {mUnlitInstances.Count} unlit material instances");

		// Create PBR instances with same colors for comparison
		for (int32 i = 0; i < 8; i++)
		{
			let instance = materialSystem.CreateInstance(mPBRMaterial);
			if (instance.IsValid)
			{
				let inst = materialSystem.GetInstance(instance);
				if (inst != null)
				{
					inst.SetFloat4("baseColor", colors[i]);
					inst.SetFloat("metallic", 0.0f);
					inst.SetFloat("roughness", 0.5f);
					inst.SetFloat("ao", 1.0f);
					inst.SetFloat4("emissive", .(0, 0, 0, 1));
					materialSystem.UploadInstance(instance);
				}
				mPBRInstances.Add(instance);
			}
		}
		Console.WriteLine($"Created {mPBRInstances.Count} PBR material instances");

		// Create ground material (PBR gray)
		mGroundMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mGroundMaterial.IsValid)
		{
			let inst = materialSystem.GetInstance(mGroundMaterial);
			if (inst != null)
			{
				inst.SetFloat4("baseColor", .(0.3f, 0.3f, 0.3f, 1.0f));
				inst.SetFloat("metallic", 0.0f);
				inst.SetFloat("roughness", 0.9f);
				inst.SetFloat("ao", 1.0f);
				inst.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(mGroundMaterial);
			}
		}

		// Create fox materials (if fox loaded)
		if (mFoxResource != null)
		{
			// Fox PBR material (with texture)
			mFoxPBRMaterial = materialSystem.CreateInstance(mPBRMaterial);
			if (mFoxPBRMaterial.IsValid)
			{
				let inst = materialSystem.GetInstance(mFoxPBRMaterial);
				if (inst != null)
				{
					inst.SetFloat4("baseColor", .(1.0f, 1.0f, 1.0f, 1.0f));
					inst.SetFloat("metallic", 0.0f);
					inst.SetFloat("roughness", 0.6f);
					inst.SetFloat("ao", 1.0f);
					inst.SetFloat4("emissive", .(0, 0, 0, 1));
					if (mFoxTexture.IsValid)
						inst.SetTexture("albedoMap", mFoxTexture);
					materialSystem.UploadInstance(mFoxPBRMaterial);
				}
			}

			// Fox Unlit material (with texture)
			mFoxUnlitMaterial = materialSystem.CreateInstance(mUnlitMaterial);
			if (mFoxUnlitMaterial.IsValid)
			{
				let inst = materialSystem.GetInstance(mFoxUnlitMaterial);
				if (inst != null)
				{
					inst.SetFloat4("color", .(1.0f, 1.0f, 1.0f, 1.0f));
					if (mFoxTexture.IsValid)
						inst.SetTexture("mainTexture", mFoxTexture);
					materialSystem.UploadInstance(mFoxUnlitMaterial);
				}
			}

			Console.WriteLine("Created Fox PBR and Unlit materials");
		}
	}

	private void CreateEntities()
	{
		// Create cube mesh
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		defer delete cubeMesh;

		// Create ground plane
		{
			let groundEntity = mScene.CreateEntity("Ground");
			groundEntity.Transform.SetPosition(.(0, -1.5f, 0));
			groundEntity.Transform.SetScale(.(30.0f, 0.2f, 30.0f));

			let meshComponent = new StaticMeshComponent();
			groundEntity.AddComponent(meshComponent);
			meshComponent.SetMesh(cubeMesh);
			meshComponent.SetMaterialInstance(0, mGroundMaterial);
		}

		float spacing = 2.0f;
		float startX = -((8 - 1) * spacing) / 2.0f;

		// Create top row: UNLIT cubes (Y = 1.5)
		for (int32 i = 0; i < 8 && i < mUnlitInstances.Count; i++)
		{
			float posX = startX + i * spacing;

			let entity = mScene.CreateEntity(scope $"UnlitCube_{i}");
			entity.Transform.SetPosition(.(posX, 1.5f, -2.0f));

			let meshComponent = new StaticMeshComponent();
			entity.AddComponent(meshComponent);
			meshComponent.SetMesh(cubeMesh);
			meshComponent.SetMaterialInstance(0, mUnlitInstances[i]);
		}

		// Create bottom row: PBR cubes (Y = 1.5, Z offset)
		for (int32 i = 0; i < 8 && i < mPBRInstances.Count; i++)
		{
			float posX = startX + i * spacing;

			let entity = mScene.CreateEntity(scope $"PBRCube_{i}");
			entity.Transform.SetPosition(.(posX, 1.5f, 2.0f));

			let meshComponent = new StaticMeshComponent();
			entity.AddComponent(meshComponent);
			meshComponent.SetMesh(cubeMesh);
			meshComponent.SetMaterialInstance(0, mPBRInstances[i]);
		}

		// Create directional light
		{
			mSunLightEntity = mScene.CreateEntity("SunLight");
			mSunLightEntity.Transform.LookAt(GetLightDirection());

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.98f, 0.9f), mLightIntensity, true);
			mSunLightEntity.AddComponent(lightComp);
		}

		// Create camera
		{
			mCameraEntity = mScene.CreateEntity("MainCamera");
			mCameraEntity.Transform.SetPosition(.(0, 5, 15));
			UpdateCameraDirection();

			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 500.0f, true);
			cameraComp.UseReverseZ = false;
			cameraComp.SetViewport(SwapChain.Width, SwapChain.Height);
			mCameraEntity.AddComponent(cameraComp);
		}

		// Create 3 fox entities with different materials (shared resource)
		if (mFoxResource != null)
		{
			float foxSpacing = 8.0f;
			float foxZ = -4.0f;

			// Fox 1: PBR material (affected by lighting) - LEFT
			{
				let foxEntity = mScene.CreateEntity("Fox_PBR");
				foxEntity.Transform.SetPosition(.(-foxSpacing, -1.4f, foxZ));
				foxEntity.Transform.SetScale(Vector3(0.04f));
				foxEntity.Transform.SetRotation(Quaternion.CreateFromYawPitchRoll(Math.PI_f * 0.25f, 0, 0));

				let meshComponent = new SkinnedMeshComponent();
				foxEntity.AddComponent(meshComponent);

				if (mFoxResource.Skeleton != null)
					meshComponent.SetSkeleton(mFoxResource.Skeleton, false);

				for (let clip in mFoxResource.Animations)
					meshComponent.AddAnimationClip(clip);

				meshComponent.SetMesh(mFoxResource.Mesh);
				meshComponent.SetMaterial(mFoxPBRMaterial);

				if (meshComponent.AnimationClips.Count > 0)
					meshComponent.PlayAnimation(0, true);

				Console.WriteLine("Fox 1: PBR material (left) - affected by lighting");
			}

			// Fox 2: Unlit material (constant brightness) - CENTER
			{
				let foxEntity = mScene.CreateEntity("Fox_Unlit");
				foxEntity.Transform.SetPosition(.(0, -1.4f, foxZ));
				foxEntity.Transform.SetScale(Vector3(0.04f));
				foxEntity.Transform.SetRotation(Quaternion.CreateFromYawPitchRoll(Math.PI_f, 0, 0));

				let skinnedRenderer = new SkinnedMeshComponent();
				foxEntity.AddComponent(skinnedRenderer);

				if (mFoxResource.Skeleton != null)
					skinnedRenderer.SetSkeleton(mFoxResource.Skeleton, false);

				for (let clip in mFoxResource.Animations)
					skinnedRenderer.AddAnimationClip(clip);

				skinnedRenderer.SetMesh(mFoxResource.Mesh);
				skinnedRenderer.SetMaterial(mFoxUnlitMaterial);

				if (skinnedRenderer.AnimationClips.Count > 1)
					skinnedRenderer.PlayAnimation(1, true);
				else if (skinnedRenderer.AnimationClips.Count > 0)
					skinnedRenderer.PlayAnimation(0, true);

				Console.WriteLine("Fox 2: UNLIT material (center) - constant brightness");
			}

			// Fox 3: No material assigned (uses default gray material) - RIGHT
			{
				let foxEntity = mScene.CreateEntity("Fox_NoMaterial");
				foxEntity.Transform.SetPosition(.(foxSpacing, -1.4f, foxZ));
				foxEntity.Transform.SetScale(Vector3(0.04f));
				foxEntity.Transform.SetRotation(Quaternion.CreateFromYawPitchRoll(-Math.PI_f * 0.25f, 0, 0));

				let skinnedRenderer = new SkinnedMeshComponent();
				foxEntity.AddComponent(skinnedRenderer);

				if (mFoxResource.Skeleton != null)
					skinnedRenderer.SetSkeleton(mFoxResource.Skeleton, false);

				for (let clip in mFoxResource.Animations)
					skinnedRenderer.AddAnimationClip(clip);

				skinnedRenderer.SetMesh(mFoxResource.Mesh);
				// No material assigned - uses default gray PBR

				if (skinnedRenderer.AnimationClips.Count > 2)
					skinnedRenderer.PlayAnimation(2, true);
				else if (skinnedRenderer.AnimationClips.Count > 0)
					skinnedRenderer.PlayAnimation(0, true);

				Console.WriteLine("Fox 3: NO material (right) - uses default gray PBR");
			}
		}

		Console.WriteLine("Created 8 unlit cubes (front) + 8 PBR cubes (back)");
		if (mFoxResource != null)
			Console.WriteLine("Created 3 foxes: PBR (left), UNLIT (center), Default (right)");
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		if (let cameraComp = mCameraEntity?.GetComponent<CameraComponent>())
			cameraComp.SetViewport(width, height);
	}

	protected override void OnInput()
	{
		if (mCameraEntity == null)
			return;

		let keyboard = Shell.InputManager.Keyboard;
		let mouse = Shell.InputManager.Mouse;

		// Toggle mouse capture
		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		// Mouse look
		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mCameraYaw -= mouse.DeltaX * mCameraLookSpeed;
			mCameraPitch -= mouse.DeltaY * mCameraLookSpeed;
			mCameraPitch = Math.Clamp(mCameraPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
			UpdateCameraDirection();
		}

		// WASD movement
		let forward = mCameraEntity.Transform.Forward;
		let right = mCameraEntity.Transform.Right;
		let up = Vector3(0, 1, 0);
		float speed = mCameraMoveSpeed * DeltaTime;

		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
			speed *= 2.0f;

		var pos = mCameraEntity.Transform.Position;
		if (keyboard.IsKeyDown(.W)) pos = pos + forward * speed;
		if (keyboard.IsKeyDown(.S)) pos = pos - forward * speed;
		if (keyboard.IsKeyDown(.A)) pos = pos - right * speed;
		if (keyboard.IsKeyDown(.D)) pos = pos + right * speed;
		if (keyboard.IsKeyDown(.Q)) pos = pos - up * speed;
		if (keyboard.IsKeyDown(.E)) pos = pos + up * speed;
		mCameraEntity.Transform.SetPosition(pos);

		// Light direction control with arrow keys
		float lightSpeed = 1.0f * DeltaTime;
		bool lightChanged = false;

		if (keyboard.IsKeyDown(.Left))  { mLightYaw -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Right)) { mLightYaw += lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Up))    { mLightPitch -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Down))  { mLightPitch += lightSpeed; lightChanged = true; }

		mLightPitch = Math.Clamp(mLightPitch, -Math.PI_f * 0.45f, -0.1f);

		if (lightChanged)
			UpdateLightDirection();

		// Light intensity control with Z/X
		float intensitySpeed = 2.0f * DeltaTime;
		bool intensityChanged = false;

		if (keyboard.IsKeyDown(.Z)) { mLightIntensity = Math.Max(0.1f, mLightIntensity - intensitySpeed); intensityChanged = true; }
		if (keyboard.IsKeyDown(.X)) { mLightIntensity = Math.Min(10.0f, mLightIntensity + intensitySpeed); intensityChanged = true; }

		if (intensityChanged)
			UpdateLightIntensity();
	}

	private void UpdateCameraDirection()
	{
		if (mCameraEntity == null)
			return;

		float cosP = Math.Cos(mCameraPitch);
		let forward = Vector3.Normalize(.(
			Math.Sin(mCameraYaw) * cosP,
			Math.Sin(mCameraPitch),
			Math.Cos(mCameraYaw) * cosP
		));

		let target = mCameraEntity.Transform.Position + forward;
		mCameraEntity.Transform.LookAt(target);
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
		if (mSunLightEntity == null)
			return;

		mSunLightEntity.Transform.LookAt(GetLightDirection());
	}

	private void UpdateLightIntensity()
	{
		if (mSunLightEntity == null)
			return;

		if (let lightComp = mSunLightEntity.GetComponent<LightComponent>())
			lightComp.Intensity = mLightIntensity;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mContext.Update(deltaTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		mCurrentFrameIndex = frameIndex;
		mRenderSceneComponent.PrepareGPU(frameIndex);

		// Update debug lines
		UpdateDebugLines();

		// Upload debug line vertices
		if (mDebugLines.Count > 0 && mLineVertexBuffers[frameIndex] != null)
		{
			let dataSize = (uint64)(mDebugLines.Count * sizeof(LineVertex));
			Span<uint8> data = .((uint8*)mDebugLines.Ptr, (int)dataSize);
			var buf = mLineVertexBuffers[frameIndex];
			Device.Queue.WriteBuffer(buf, 0, data);
		}

		// Upload camera VP for debug lines
		if (mCameraEntity != null && mLineUniformBuffers[frameIndex] != null)
		{
			if (let cameraComp = mCameraEntity.GetComponent<CameraComponent>())
			{
				let camPos = mCameraEntity.Transform.WorldPosition;
				let camFwd = mCameraEntity.Transform.Forward;
				let camUp = mCameraEntity.Transform.Up;
				let viewMatrix = Matrix.CreateLookAt(camPos, camPos + camFwd, camUp);

				float aspectRatio = (float)cameraComp.ViewportWidth / (float)cameraComp.ViewportHeight;
				var projection = Matrix.CreatePerspectiveFieldOfView(cameraComp.FieldOfView, aspectRatio, cameraComp.NearPlane, cameraComp.FarPlane);

				if (Device.FlipProjectionRequired)
					projection.M22 = -projection.M22;

				var vp = viewMatrix * projection;
				Span<uint8> vpSpan = .((uint8*)&vp, sizeof(Matrix));
				var buf = mLineUniformBuffers[frameIndex];
				Device.Queue.WriteBuffer(buf, 0, vpSpan);
			}
		}
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Render shadow passes
		mRenderSceneComponent.RenderShadows(encoder, frameIndex);

		// Main render pass
		let textureView = SwapChain.CurrentTextureView;
		if (textureView == null) return true;

		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = textureView,
			ResolveTarget = null,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = .(0.05f, 0.05f, 0.1f, 1.0f)
		});

		RenderPassDescriptor renderPassDesc = .(colorAttachments);
		RenderPassDepthStencilAttachment depthAttachment = .()
		{
			View = DepthTextureView,
			DepthLoadOp = .Clear,
			DepthStoreOp = .Store,
			DepthClearValue = 1.0f,
			StencilLoadOp = .Clear,
			StencilStoreOp = .Discard,
			StencilClearValue = 0
		};
		renderPassDesc.DepthStencilAttachment = depthAttachment;

		let renderPass = encoder.BeginRenderPass(&renderPassDesc);
		if (renderPass == null) return true;
		defer delete renderPass;

		mRenderSceneComponent.Render(renderPass, SwapChain.Width, SwapChain.Height);

		// Draw debug lines (light direction gizmo)
		if (mDebugLines.Count > 0 && mLinePipeline != null)
		{
			renderPass.SetPipeline(mLinePipeline);
			renderPass.SetBindGroup(0, mLineBindGroups[frameIndex]);
			renderPass.SetVertexBuffer(0, mLineVertexBuffers[frameIndex], 0);
			renderPass.Draw((uint32)mDebugLines.Count, 1, 0, 0);
		}

		renderPass.End();
		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - OnRenderFrame handles rendering
	}

	private bool CreateLinePipeline()
	{
		let vertCode = """
			#pragma pack_matrix(row_major)

			cbuffer Camera : register(b0) {
				float4x4 viewProjection;
			};

			struct VSInput {
				float3 position : POSITION;
				float4 color : COLOR;
			};

			struct VSOutput {
				float4 position : SV_Position;
				float4 color : COLOR;
			};

			VSOutput main(VSInput input) {
				VSOutput output;
				output.position = mul(float4(input.position, 1.0), viewProjection);
				output.color = input.color;
				return output;
			}
			""";

		let fragCode = """
			struct PSInput {
				float4 position : SV_Position;
				float4 color : COLOR;
			};

			float4 main(PSInput input) : SV_Target {
				return input.color;
			}
			""";

		let vertResult = ShaderUtils.CompileShader(Device, vertCode, "main", .Vertex);
		if (vertResult case .Err)
			return false;
		let lineVertShader = vertResult.Get();
		defer delete lineVertShader;

		let fragResult = ShaderUtils.CompileShader(Device, fragCode, "main", .Fragment);
		if (fragResult case .Err)
			return false;
		let lineFragShader = fragResult.Get();
		defer delete lineFragShader;

		BindGroupLayoutEntry[1] lineLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);

		BindGroupLayoutDescriptor lineLayoutDesc = .(lineLayoutEntries);
		if (Device.CreateBindGroupLayout(&lineLayoutDesc) case .Ok(let bindLayout))
			mLineBindGroupLayout = bindLayout;
		else return false;

		IBindGroupLayout[1] lineBindGroupLayouts = .(mLineBindGroupLayout);
		PipelineLayoutDescriptor linePipelineLayoutDesc = .(lineBindGroupLayouts);
		if (Device.CreatePipelineLayout(&linePipelineLayoutDesc) case .Ok(let pipLayout))
			mLinePipelineLayout = pipLayout;
		else return false;

		Sedulous.RHI.VertexAttribute[2] lineAttrs = .(
			.(VertexFormat.Float3, 0, 0),
			.(VertexFormat.Float4, 12, 1)
		);

		VertexBufferLayout[1] lineVertexBuffers = .(
			.(28, lineAttrs, .Vertex)
		);

		DepthStencilState lineDepthState = .();
		lineDepthState.DepthTestEnabled = true;
		lineDepthState.DepthWriteEnabled = false;
		lineDepthState.DepthCompare = .Less;
		lineDepthState.Format = .Depth24PlusStencil8;

		ColorTargetState[1] lineColorTargets = .(.(SwapChain.Format));
		RenderPipelineDescriptor linePipelineDesc = .()
		{
			Layout = mLinePipelineLayout,
			Vertex = .() { Shader = .(lineVertShader, "main"), Buffers = lineVertexBuffers },
			Fragment = .() { Shader = .(lineFragShader, "main"), Targets = lineColorTargets },
			Primitive = .() { Topology = .LineList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = lineDepthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&linePipelineDesc) case .Ok(let pipeline))
			mLinePipeline = pipeline;
		else return false;

		for (int32 i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BufferDescriptor uniformDesc = .((uint64)sizeof(Matrix), .Uniform, .Upload);
			if (Device.CreateBuffer(&uniformDesc) case .Ok(let uniformBuf))
				mLineUniformBuffers[i] = uniformBuf;
			else return false;

			BufferDescriptor vertexDesc = .((uint64)(sizeof(LineVertex) * MAX_DEBUG_LINES * 2), .Vertex, .Upload);
			if (Device.CreateBuffer(&vertexDesc) case .Ok(let vertexBuf))
				mLineVertexBuffers[i] = vertexBuf;
			else return false;

			BindGroupEntry[1] lineBindGroupEntries = .(
				BindGroupEntry.Buffer(0, mLineUniformBuffers[i])
			);
			BindGroupDescriptor lineBindGroupDesc = .(mLineBindGroupLayout, lineBindGroupEntries);
			if (Device.CreateBindGroup(&lineBindGroupDesc) case .Ok(let group))
				mLineBindGroups[i] = group;
			else return false;
		}

		return true;
	}

	private void UpdateDebugLines()
	{
		mDebugLines.Clear();

		let lightDir = GetLightDirection();
		let lightStart = Vector3(0, 5, 0);

		// XYZ axis
		let axisLength = 1.5f;

		mDebugLines.Add(LineVertex(lightStart, .(1, 0, 0, 1)));
		mDebugLines.Add(LineVertex(lightStart + Vector3(axisLength, 0, 0), .(1, 0, 0, 1)));

		mDebugLines.Add(LineVertex(lightStart, .(0, 1, 0, 1)));
		mDebugLines.Add(LineVertex(lightStart + Vector3(0, axisLength, 0), .(0, 1, 0, 1)));

		mDebugLines.Add(LineVertex(lightStart, .(0, 0, 1, 1)));
		mDebugLines.Add(LineVertex(lightStart + Vector3(0, 0, axisLength), .(0, 0, 1, 1)));

		// Light direction arrow
		let lightEnd = lightStart + lightDir * 5.0f;
		mDebugLines.Add(LineVertex(lightStart, .(1, 1, 0, 1)));
		mDebugLines.Add(LineVertex(lightEnd, .(1, 0.5f, 0, 1)));

		let right = Vector3.Normalize(Vector3.Cross(lightDir, Vector3.Up));
		let up = Vector3.Normalize(Vector3.Cross(right, lightDir));
		let arrowSize = 0.3f;

		mDebugLines.Add(LineVertex(lightEnd, .(1, 0.5f, 0, 1)));
		mDebugLines.Add(LineVertex(lightEnd - lightDir * arrowSize + right * arrowSize * 0.5f, .(1, 0.5f, 0, 1)));

		mDebugLines.Add(LineVertex(lightEnd, .(1, 0.5f, 0, 1)));
		mDebugLines.Add(LineVertex(lightEnd - lightDir * arrowSize - right * arrowSize * 0.5f, .(1, 0.5f, 0, 1)));

		mDebugLines.Add(LineVertex(lightEnd, .(1, 0.5f, 0, 1)));
		mDebugLines.Add(LineVertex(lightEnd - lightDir * arrowSize + up * arrowSize * 0.5f, .(1, 0.5f, 0, 1)));

		mDebugLines.Add(LineVertex(lightEnd, .(1, 0.5f, 0, 1)));
		mDebugLines.Add(LineVertex(lightEnd - lightDir * arrowSize - up * arrowSize * 0.5f, .(1, 0.5f, 0, 1)));
	}

	protected override void OnCleanup()
	{
		mContext?.Shutdown();

		Device.WaitIdle();

		// Clean up debug line resources
		for (int32 i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			delete mLineBindGroups[i];
			delete mLineVertexBuffers[i];
			delete mLineUniformBuffers[i];
		}
		delete mLinePipeline;
		delete mLinePipelineLayout;
		delete mLineBindGroupLayout;

		// Clean up materials
		if (mRendererService?.MaterialSystem != null)
		{
			let materialSystem = mRendererService.MaterialSystem;

			// Fox materials
			if (mFoxPBRMaterial.IsValid)
				materialSystem.ReleaseInstance(mFoxPBRMaterial);

			if (mFoxUnlitMaterial.IsValid)
				materialSystem.ReleaseInstance(mFoxUnlitMaterial);

			for (let handle in mUnlitInstances)
				materialSystem.ReleaseInstance(handle);

			for (let handle in mPBRInstances)
				materialSystem.ReleaseInstance(handle);

			if (mGroundMaterial.IsValid)
				materialSystem.ReleaseInstance(mGroundMaterial);

			if (mUnlitMaterial.IsValid)
				materialSystem.ReleaseMaterial(mUnlitMaterial);

			if (mPBRMaterial.IsValid)
				materialSystem.ReleaseMaterial(mPBRMaterial);
		}

		// Clean up fox texture
		if (mFoxTexture.IsValid && mRendererService?.ResourceManager != null)
			mRendererService.ResourceManager.ReleaseTexture(mFoxTexture);

		delete mRendererService;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let sample = scope RendererUnlitSample();
		return sample.Run();
	}
}
