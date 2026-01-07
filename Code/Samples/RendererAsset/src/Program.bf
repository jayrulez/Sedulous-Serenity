namespace RendererAsset;

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

/// Demonstrates the asset cache system.
/// - Checks for cached assets on startup
/// - Imports from GLTF if not cached
/// - Saves to cache for faster loading next time
class RendererAssetSample : RHISampleApp
{
	// Asset paths (relative to AssetDirectory)
	private const StringView CACHE_REL_DIR = "cache";
	private const StringView CACHE_REL_PATH = "cache/fox1.skinnedmesh";
	private const StringView GLTF_REL_PATH = "samples/models/Fox/glTF/Fox.gltf";
	private const StringView GLTF_BASE_REL_PATH = "samples/models/Fox/glTF";
	private const StringView TEXTURE_REL_PATH = "samples/models/Fox/glTF/Texture.png";
	private const StringView SHADER_REL_PATH = "framework/shaders";

	// Framework.Core components
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;

	// Renderer components
	private RendererService mRendererService;
	private RenderSceneComponent mRenderSceneComponent;

	// Material handles
	private MaterialHandle mPBRMaterial = .Invalid;
	private MaterialInstanceHandle mFoxMaterial = .Invalid;
	private MaterialInstanceHandle mGroundMaterial = .Invalid;

	// Fox resources
	private Model mFoxModel ~ delete _;
	private SkinnedMeshResource mFoxResource ~ delete _;
	private MaterialResource mFoxMaterialResource ~ delete _;
	private GPUTextureHandle mFoxTexture = .Invalid;

	// Camera entity and control
	private Entity mCameraEntity;
	private float mCameraYaw = Math.PI_f;
	private float mCameraPitch = -0.2f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 10.0f;
	private float mCameraLookSpeed = 0.003f;

	// Light entity
	private Entity mSunLightEntity;

	// Stats
	private bool mLoadedFromCache = false;

	public this() : base(.()
	{
		Title = "Asset Cache Demo",
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
		let shaderPath = GetAssetPath(SHADER_REL_PATH, .. scope .());
		if (mRendererService.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}
		mContext.RegisterService<RendererService>(mRendererService);

		// Create scene with RenderSceneComponent
		mScene = mContext.SceneManager.CreateScene("AssetScene");
		mRenderSceneComponent = mScene.AddSceneComponent(new RenderSceneComponent(mRendererService));

		// Initialize rendering
		if (mRenderSceneComponent.InitializeRendering(SwapChain.Format, .Depth24PlusStencil8, Device.FlipProjectionRequired) case .Err)
		{
			Console.WriteLine("Failed to initialize scene rendering");
			return false;
		}

		// Load fox model (with cache)
		if (!LoadFoxWithCache())
		{
			Console.WriteLine("Failed to load Fox model");
			return false;
		}

		// Create materials and entities
		CreateMaterials();
		CreateEntities();

		// Set active scene and start context
		mContext.SceneManager.SetActiveScene(mScene);
		mContext.Startup();

		Console.WriteLine("");
		Console.WriteLine("=== Asset Cache Demo ===");
		Console.WriteLine(mLoadedFromCache ? "Fox loaded from CACHE (fast path)" : "Fox imported from GLTF (slow path, cached for next time)");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Tab=Toggle mouse capture, Shift=Fast");

		return true;
	}

	/// Loads the Fox model, checking cache first.
	private bool LoadFoxWithCache()
	{
		// Build asset paths
		let cacheDir = GetAssetPath(CACHE_REL_DIR, .. scope .());
		let cachePath = GetAssetPath(CACHE_REL_PATH, .. scope .());
		let gltfPath = GetAssetPath(GLTF_REL_PATH, .. scope .());
		let gltfBasePath = GetAssetPath(GLTF_BASE_REL_PATH, .. scope .());

		// Try to load from cache first
		if (File.Exists(cachePath))
		{
			Console.WriteLine("Checking cache...");
			if (ResourceSerializer.LoadSkinnedMeshBundle(cachePath) case .Ok(let resource))
			{
				mFoxResource = resource;
				mLoadedFromCache = true;
				Console.WriteLine($"  Loaded from cache: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.AnimationCount} animations");
				return true;
			}
			else
			{
				Console.WriteLine("  Cache file exists but failed to load, falling back to GLTF import...");
			}
		}
		else
		{
			Console.WriteLine($"Cache not found: {cachePath}");
			Console.WriteLine("Importing from GLTF...");
		}

		// Import from GLTF
		mFoxModel = new Model();
		let loader = scope GltfLoader();

		let result = loader.Load(gltfPath, mFoxModel);
		if (result != .Ok)
		{
			Console.WriteLine($"  Failed to load Fox model: {result}");
			delete mFoxModel;
			mFoxModel = null;
			return false;
		}

		Console.WriteLine($"  GLTF parsed: {mFoxModel.Meshes.Count} meshes, {mFoxModel.Bones.Count} bones, {mFoxModel.Animations.Count} animations");

		// Use ModelImporter to convert all resources
		let importOptions = new ModelImportOptions();
		importOptions.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Textures | .Materials;
		importOptions.BasePath.Set(gltfBasePath);

		let imageLoader = scope SDLImageLoader();
		let importer = scope ModelImporter(importOptions, imageLoader);
		let importResult = importer.Import(mFoxModel);
		defer delete importResult;

		if (!importResult.Success)
		{
			Console.WriteLine("  Import errors:");
			for (let err in importResult.Errors)
				Console.WriteLine($"    - {err}");
			return false;
		}

		if (importResult.SkinnedMeshes.Count == 0)
		{
			Console.WriteLine("  No skinned meshes in import result");
			return false;
		}
		
		// Save to cache for next time
		Console.WriteLine("Saving to cache...");
		if (EnsureCacheDirectory(cachePath))
		{
			if (ResourceSerializer.SaveImportResult(importResult, cacheDir) case .Ok)
				Console.WriteLine($"  Saved to: {cacheDir}");
			else
				Console.WriteLine("  Failed to save cache file");
		}

		// Take ownership of the first skinned mesh
		mFoxResource = importResult.TakeSkinnedMesh(0);
		Console.WriteLine($"  Imported: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.AnimationCount} animations");

		// Take ownership of the first material (if any)
		if (importResult.Materials.Count > 0)
		{
			mFoxMaterialResource = importResult.Materials[0];
			importResult.Materials.RemoveAt(0);
			Console.WriteLine($"  Material: {mFoxMaterialResource.Name} (type={mFoxMaterialResource.Type})");

			// Log texture references from the imported material
			for (let kv in mFoxMaterialResource.Textures)
				Console.WriteLine($"    Texture slot '{kv.key}': {kv.value}");
		}

		mLoadedFromCache = false;
		return true;
	}

	/// Ensures the cache directory exists.
	private bool EnsureCacheDirectory(StringView cachePath)
	{
		let cacheDir = Path.GetDirectoryPath(cachePath, .. scope .());
		if (!Directory.Exists(cacheDir))
		{
			if (Directory.CreateDirectory(cacheDir) case .Err)
			{
				Console.WriteLine($"  Failed to create cache directory: {cacheDir}");
				return false;
			}
		}
		return true;
	}

	private void CreateMaterials()
	{
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null)
		{
			Console.WriteLine("MaterialSystem not available!");
			return;
		}

		// Create PBR material template
		let pbrMaterial = Material.CreatePBR("PBRMaterial");
		mPBRMaterial = materialSystem.RegisterMaterial(pbrMaterial);
		if (!mPBRMaterial.IsValid)
		{
			Console.WriteLine("Failed to register PBR material");
			return;
		}

		// Create fox material instance from imported material
		mFoxMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mFoxMaterial.IsValid)
		{
			let inst = materialSystem.GetInstance(mFoxMaterial);
			if (inst != null)
			{
				// Use imported material values if available, otherwise use defaults
				if (mFoxMaterialResource != null)
				{
					inst.SetFloat4("baseColor", mFoxMaterialResource.BaseColor);
					inst.SetFloat("metallic", mFoxMaterialResource.Metallic);
					inst.SetFloat("roughness", mFoxMaterialResource.Roughness);
					inst.SetFloat("ao", mFoxMaterialResource.AO);
					inst.SetFloat4("emissive", mFoxMaterialResource.Emissive);

					Console.WriteLine($"Using imported material values: baseColor={mFoxMaterialResource.BaseColor}, metallic={mFoxMaterialResource.Metallic}, roughness={mFoxMaterialResource.Roughness}");

					// Load texture - check cache first, then fall back to original file
					if (mFoxMaterialResource.HasTexture("albedoMap"))
					{
						let textureName = mFoxMaterialResource.GetTexture("albedoMap");
						let cachedTexturePath = GetAssetPath(scope $"{CACHE_REL_DIR}/{textureName}.texture", .. scope .());
						let originalTexturePath = GetAssetPath(scope $"{GLTF_BASE_REL_PATH}/{textureName}", .. scope .());

						// Try cached texture first
						if (File.Exists(cachedTexturePath))
						{
							if (ResourceSerializer.LoadTexture(cachedTexturePath) case .Ok(let texResource))
							{
								Console.WriteLine($"Loaded texture from cache: {cachedTexturePath}");
								let img = texResource.Image;
								mFoxTexture = mRendererService.ResourceManager.CreateTextureFromData(
									img.Width, img.Height, .RGBA8Unorm, img.Data);
								delete texResource;
								if (mFoxTexture.IsValid)
									inst.SetTexture("albedoMap", mFoxTexture);
							}
						}
						else
						{
							// Load from original file
							Console.WriteLine($"Loading texture from: {originalTexturePath}");
							let imageLoader = scope SDLImageLoader();
							if (imageLoader.LoadFromFile(originalTexturePath) case .Ok(var loadInfo))
							{
								defer loadInfo.Dispose();
								mFoxTexture = mRendererService.ResourceManager.CreateTextureFromData(
									loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .(loadInfo.Data.Ptr, loadInfo.Data.Count));
								if (mFoxTexture.IsValid)
									inst.SetTexture("albedoMap", mFoxTexture);
							}
						}
					}
				}
				else
				{
					// Fallback to default values (e.g., when loaded from cache without material)
					inst.SetFloat4("baseColor", .(1.0f, 1.0f, 1.0f, 1.0f));
					inst.SetFloat("metallic", 0.0f);
					inst.SetFloat("roughness", 0.6f);
					inst.SetFloat("ao", 1.0f);
					inst.SetFloat4("emissive", .(0, 0, 0, 1));

					// Try cached texture first, then original
					let cachedTexturePath = GetAssetPath(scope $"{CACHE_REL_DIR}/Texture.png.texture", .. scope .());
					let originalTexturePath = GetAssetPath(TEXTURE_REL_PATH, .. scope .());

					if (File.Exists(cachedTexturePath))
					{
						if (ResourceSerializer.LoadTexture(cachedTexturePath) case .Ok(let texResource))
						{
							Console.WriteLine($"Loaded texture from cache: {cachedTexturePath}");
							let img = texResource.Image;
							mFoxTexture = mRendererService.ResourceManager.CreateTextureFromData(
								img.Width, img.Height, .RGBA8Unorm, img.Data);
							delete texResource;
							if (mFoxTexture.IsValid)
								inst.SetTexture("albedoMap", mFoxTexture);
						}
					}
					else
					{
						Console.WriteLine($"Loading texture from: {originalTexturePath}");
						let imageLoader = scope SDLImageLoader();
						if (imageLoader.LoadFromFile(originalTexturePath) case .Ok(var loadInfo))
						{
							defer loadInfo.Dispose();
							mFoxTexture = mRendererService.ResourceManager.CreateTextureFromData(
								loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .(loadInfo.Data.Ptr, loadInfo.Data.Count));
							if (mFoxTexture.IsValid)
								inst.SetTexture("albedoMap", mFoxTexture);
						}
					}
				}
				materialSystem.UploadInstance(mFoxMaterial);
			}
		}

		// Create ground material
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
	}

	private void CreateEntities()
	{
		// Create cube mesh for ground
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		defer delete cubeMesh;

		// Create ground plane
		{
			let groundEntity = mScene.CreateEntity("Ground");
			groundEntity.Transform.SetPosition(.(0, -1.5f, 0));
			groundEntity.Transform.SetScale(.(30.0f, 0.2f, 30.0f));

			let staticMeshComponent = new StaticMeshComponent();
			groundEntity.AddComponent(staticMeshComponent);
			staticMeshComponent.SetMesh(cubeMesh);
			staticMeshComponent.SetMaterialInstance(0, mGroundMaterial);
		}

		// Create directional light
		{
			mSunLightEntity = mScene.CreateEntity("SunLight");
			mSunLightEntity.Transform.LookAt(Vector3.Normalize(.(0.5f, -0.7f, 0.3f)));

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.98f, 0.9f), 2.0f, true);
			mSunLightEntity.AddComponent(lightComp);
		}

		// Create camera
		{
			mCameraEntity = mScene.CreateEntity("MainCamera");
			mCameraEntity.Transform.SetPosition(.(0, 3, 8));
			UpdateCameraDirection();

			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 500.0f, true);
			cameraComp.UseReverseZ = false;
			cameraComp.SetViewport(SwapChain.Width, SwapChain.Height);
			mCameraEntity.AddComponent(cameraComp);
		}

		// Create fox entity with skinned mesh
		if (mFoxResource != null)
		{
			let foxEntity = mScene.CreateEntity("Fox");
			foxEntity.Transform.SetPosition(.(0, -1.4f, 0));
			foxEntity.Transform.SetScale(Vector3(0.04f));
			foxEntity.Transform.SetRotation(Quaternion.CreateFromYawPitchRoll(Math.PI_f, 0, 0));

			let skinnedMeshComponent = new SkinnedMeshComponent();
			foxEntity.AddComponent(skinnedMeshComponent);

			if (mFoxResource.Skeleton != null)
				skinnedMeshComponent.SetSkeleton(mFoxResource.Skeleton, false);

			for (let clip in mFoxResource.Animations)
				skinnedMeshComponent.AddAnimationClip(clip);

			skinnedMeshComponent.SetMesh(mFoxResource.Mesh);
			skinnedMeshComponent.SetMaterial(mFoxMaterial);

			// Start playing animation
			if (skinnedMeshComponent.AnimationClips.Count > 0)
				skinnedMeshComponent.PlayAnimation(0, true);
		}
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

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mContext.Update(deltaTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		mRenderSceneComponent.PrepareGPU(frameIndex);
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

		renderPass.End();
		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - OnRenderFrame handles rendering
	}

	protected override void OnCleanup()
	{
		mContext?.Shutdown();

		Device.WaitIdle();

		// Clean up materials
		if (mRendererService?.MaterialSystem != null)
		{
			let materialSystem = mRendererService.MaterialSystem;

			if (mFoxMaterial.IsValid)
				materialSystem.ReleaseInstance(mFoxMaterial);

			if (mGroundMaterial.IsValid)
				materialSystem.ReleaseInstance(mGroundMaterial);

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
		let sample = scope RendererAssetSample();
		return sample.Run();
	}
}
