namespace RendererIntegrated;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Renderer;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Console;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Imaging;
using SampleFramework;
using Sedulous.Logging.Debug;
using Sedulous.Geometry.Tooling;
using Sedulous.Renderer.Resources;

/// Demonstrates Framework.Core integration with Framework.Renderer.
/// Uses entities with MeshRendererComponent, LightComponent, and CameraComponent.
///
/// This sample shows the high-level API where you only work with ECS components
/// and the renderer handles all GPU details internally.
class RendererIntegratedSample : RHISampleApp
{
	// Grid size
	private const int32 GRID_SIZE = 8;  // 8x8 = 64 cubes

	// Framework.Core components
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;  // Owned by SceneManager

	// Renderer components
	private RendererService mRendererService;
	private RenderSceneComponent mRenderSceneComponent;

	// Material handles
	private MaterialHandle mPBRMaterial = .Invalid;
	private MaterialInstanceHandle mGroundMaterial = .Invalid;
	private MaterialInstanceHandle[8] mCubeMaterials;  // 8 different colors
	private MaterialInstanceHandle mFoxMaterial = .Invalid;
	private GPUTextureHandle mFoxTexture = .Invalid;

	// Camera entity and control
	private Entity mCameraEntity;
	private float mCameraYaw = Math.PI_f;  // Start looking toward -Z (toward origin)
	private float mCameraPitch = -0.3f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 15.0f;
	private float mCameraLookSpeed = 0.003f;

	// Current frame index for rendering
	private int32 mCurrentFrameIndex = 0;

	// Fox (skinned mesh) resources
	private SkinnedMeshResource mFoxResource ~ delete _;
	private Entity mFoxEntity;
	private int32 mCurrentAnimIndex = 0;

	// Light direction control (spherical coordinates)
	private Entity mSunLightEntity;
	private float mLightYaw = 0.5f;
	private float mLightPitch = -0.7f;
	private float mLightIntensity = 1.0f;

	// Debug drawing service
	private DebugDrawService mDebugDrawService;

	// Particle effect positions for labeling
	private struct ParticleEffectLabel
	{
		public Vector3 Position;
		public Color MarkerColor;
		public String Name;

		public this(Vector3 pos, Color color, String name)
		{
			Position = pos;
			MarkerColor = color;
			Name = name;
		}
	}
	private List<ParticleEffectLabel> mParticleLabels = new .() ~ delete _;

	public this() : base(.()
	{
		Title = "Framework.Core + Renderer Integration",
		Width = 1280,
		Height = 720,
		ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f),
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
		// Set formats to match swap chain BEFORE initializing
		mRendererService.SetFormats(SwapChain.Format, .Depth24PlusStencil8);
		let shaderPath = GetAssetPath("framework/shaders", .. scope .());
		if (mRendererService.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}
		mContext.RegisterService<RendererService>(mRendererService);

		// Create and register DebugDrawService after RendererService
		mDebugDrawService = new DebugDrawService();
		mContext.RegisterService<DebugDrawService>(mDebugDrawService);

		// Start context before creating scenes (enables automatic component creation)
		mContext.Startup();

		// Create scene - RenderSceneComponent is added automatically by RendererService
		mScene = mContext.SceneManager.CreateScene("MainScene");
		mRenderSceneComponent = mScene.GetSceneComponent<RenderSceneComponent>();
		mContext.SceneManager.SetActiveScene(mScene);

		// Create materials
		CreateMaterials();

		// Create all entities (cubes, lights, camera)
		CreateEntities();

		Console.WriteLine("Framework.Core + Renderer integration sample initialized");
		Console.WriteLine($"Created {GRID_SIZE * GRID_SIZE} cube entities with MeshRendererComponent");
		Console.WriteLine("Created 10 sprite entities");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Tab=Toggle mouse capture, Shift=Fast");
		Console.WriteLine("          Space=Cycle Fox animations, Arrow keys=Light direction");
		Console.WriteLine("          Z/X=Light intensity");

		// Debug: initial state
		Console.WriteLine($"[INIT DEBUG] MeshCount={mRenderSceneComponent.MeshCount}, HasCamera={mRenderSceneComponent.GetMainCameraProxy() != null}");

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

		// Create PBR material
		let pbrMaterial = Material.CreatePBR("PBRMaterial");
		mPBRMaterial = materialSystem.RegisterMaterial(pbrMaterial);

		if (!mPBRMaterial.IsValid)
		{
			Console.WriteLine("Failed to register PBR material");
			return;
		}

		// Create ground material (gray)
		mGroundMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mGroundMaterial.IsValid)
		{
			let instance = materialSystem.GetInstance(mGroundMaterial);
			if (instance != null)
			{
				instance.SetFloat4("baseColor", .(0.4f, 0.4f, 0.4f, 1.0f));
				instance.SetFloat("metallic", 0.0f);
				instance.SetFloat("roughness", 0.9f);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(mGroundMaterial);
			}
		}

		// Create 8 cube materials with different colors
		Vector4[8] cubeColors = .(
			.(1.0f, 0.3f, 0.3f, 1.0f),  // Red
			.(0.3f, 1.0f, 0.3f, 1.0f),  // Green
			.(0.3f, 0.3f, 1.0f, 1.0f),  // Blue
			.(1.0f, 1.0f, 0.3f, 1.0f),  // Yellow
			.(1.0f, 0.3f, 1.0f, 1.0f),  // Magenta
			.(0.3f, 1.0f, 1.0f, 1.0f),  // Cyan
			.(1.0f, 0.6f, 0.3f, 1.0f),  // Orange
			.(0.6f, 0.3f, 1.0f, 1.0f)   // Purple
		);

		for (int32 i = 0; i < 8; i++)
		{
			mCubeMaterials[i] = materialSystem.CreateInstance(mPBRMaterial);
			if (mCubeMaterials[i].IsValid)
			{
				let instance = materialSystem.GetInstance(mCubeMaterials[i]);
				if (instance != null)
				{
					instance.SetFloat4("baseColor", cubeColors[i]);
					instance.SetFloat("metallic", 0.2f);
					instance.SetFloat("roughness", 0.5f);
					instance.SetFloat("ao", 1.0f);
					instance.SetFloat4("emissive", .(0, 0, 0, 1));
					materialSystem.UploadInstance(mCubeMaterials[i]);
				}
			}
		}

		// Create Fox material (will set texture later in CreateFoxEntity)
		mFoxMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mFoxMaterial.IsValid)
		{
			let instance = materialSystem.GetInstance(mFoxMaterial);
			if (instance != null)
			{
				instance.SetFloat4("baseColor", .(1.0f, 1.0f, 1.0f, 1.0f));  // White to show texture
				instance.SetFloat("metallic", 0.0f);
				instance.SetFloat("roughness", 0.6f);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0, 0, 0, 1));
			}
		}

		Console.WriteLine("Created PBR materials for ground, cubes, and Fox");
	}

	private void CreateEntities()
	{
		// Create shared CPU mesh - uploaded to GPU automatically by MeshRendererComponent
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		defer delete cubeMesh;

		// Create ground plane (large flat cube)
		{
			let groundEntity = mScene.CreateEntity("Ground");
			groundEntity.Transform.SetPosition(.(0, -0.5f, 0));
			groundEntity.Transform.SetScale(.(50.0f, 1.0f, 50.0f));

			let meshComponent = new StaticMeshComponent();
			groundEntity.AddComponent(meshComponent);
			meshComponent.SetMesh(cubeMesh);
			meshComponent.SetMaterialInstance(0, mGroundMaterial);
		}

		float spacing = 3.0f;
		float startOffset = -(GRID_SIZE * spacing) / 2.0f;

		// Create grid of cube entities
		for (int32 x = 0; x < GRID_SIZE; x++)
		{
			for (int32 z = 0; z < GRID_SIZE; z++)
			{
				float posX = startOffset + x * spacing;
				float posZ = startOffset + z * spacing;

				// Create entity with transform
				let entity = mScene.CreateEntity(scope $"Cube_{x}_{z}");
				entity.Transform.SetPosition(.(posX, 0.5f, posZ));  // Raise cubes to sit on ground

				// Add MeshRendererComponent first, then set mesh
				// (SetMesh needs access to RendererService via entity's scene)
				let meshComponent = new StaticMeshComponent();
				entity.AddComponent(meshComponent);

				// Now set the mesh - GPU upload happens automatically
				meshComponent.SetMesh(cubeMesh);
				meshComponent.SetMaterialInstance(0, mCubeMaterials[(x + z) % 8]);
			}
		}

		// Create directional light entity with shadows
		{
			mSunLightEntity = mScene.CreateEntity("SunLight");
			mSunLightEntity.Transform.LookAt(GetLightDirection());

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.95f, 0.8f), mLightIntensity, true);  // Enable shadows
			mSunLightEntity.AddComponent(lightComp);
		}

		// Create point lights (fixed seed for consistent placement between runs)
		Random rng = scope .(12345);
		for (int i = 0; i < 8; i++)
		{
			float px = ((float)rng.NextDouble() - 0.5f) * 30.0f;
			float py = (float)rng.NextDouble() * 5.0f + 2.0f;
			float pz = ((float)rng.NextDouble() - 0.5f) * 30.0f;

			let lightEntity = mScene.CreateEntity(scope $"PointLight_{i}");
			lightEntity.Transform.SetPosition(.(px, py, pz));

			Vector3 color = .(
				(float)rng.NextDouble() * 0.5f + 0.5f,
				(float)rng.NextDouble() * 0.5f + 0.5f,
				(float)rng.NextDouble() * 0.5f + 0.5f
			);

			let lightComp = LightComponent.CreatePoint(color, 5.0f, 15.0f);
			lightEntity.AddComponent(lightComp);
		}
		

		// Create camera entity with CameraComponent
		{
			mCameraEntity = mScene.CreateEntity("MainCamera");
			mCameraEntity.Transform.SetPosition(.(0, 10, 30));
			UpdateCameraDirection();

			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 1000.0f, true);
			cameraComp.UseReverseZ = false;  // Match RendererShadow sample
			cameraComp.SetViewport(SwapChain.Width, SwapChain.Height);
			mCameraEntity.AddComponent(cameraComp);
		}

		// Create various particle effects around the scene
		CreateParticleEffects();

		// Create some sprite entities
		for (int i = 0; i < 10; i++)
		{
			float angle = (float)i / 10.0f * Math.PI_f * 2.0f;
			float radius = 8.0f;

			let spriteEntity = mScene.CreateEntity(scope $"Sprite_{i}");
			spriteEntity.Transform.SetPosition(.(
				Math.Cos(angle) * radius,
				2.0f + (float)i * 0.3f,
				Math.Sin(angle) * radius
			));

			let sprite = new SpriteComponent(.(1.0f, 1.0f));
			// Vary colors
			sprite.Color = .((uint8)(128 + i * 12), (uint8)(200 - i * 10), (uint8)(100 + i * 15), 255);
			spriteEntity.AddComponent(sprite);
		}

		// Create fox entity (skinned mesh)
		CreateFoxEntity();

		// Check debug draw service initialized
		if (!mDebugDrawService.IsInitialized)
			Console.WriteLine("Warning: DebugDrawService not initialized");
	}

	private void CreateParticleEffects()
	{
		// Helper to register an effect for debug labeling
		void RegisterEffect(Vector3 pos, Color color, String name)
		{
			mParticleLabels.Add(.(pos, color, name));
		}

		// ==================== FIRE EFFECTS ====================
		// Fire pit at center-back of scene
		{
			let pos = Vector3(0, 0.2f, -15);
			let fireEntity = mScene.CreateEntity("FirePit");
			fireEntity.Transform.SetPosition(pos);

			let config = ParticleEmitterConfig.CreateFire();
			config.EmissionRate = 80;
			config.MaxParticles = 500;

			let emitter = new ParticleEmitterComponent(config);
			fireEntity.AddComponent(emitter);

			RegisterEffect(pos, .(255, 100, 0, 255), "FIRE");
		}

		// Smaller torch fires at corners
		{
			Vector3[4] torchPositions = .(
				.(-18, 2.0f, -18),
				.(18, 2.0f, -18),
				.(-18, 2.0f, 18),
				.(18, 2.0f, 18)
			);

			for (int i = 0; i < 4; i++)
			{
				let torchEntity = mScene.CreateEntity(scope $"Torch_{i}");
				torchEntity.Transform.SetPosition(torchPositions[i]);

				let config = ParticleEmitterConfig.CreateFire();
				config.EmissionRate = 25;
				config.InitialSize = .(0.15f, 0.3f);
				config.MaxParticles = 150;

				let emitter = new ParticleEmitterComponent(config);
				torchEntity.AddComponent(emitter);

				RegisterEffect(torchPositions[i], .(255, 150, 50, 255), "TORCH");
			}
		}

		// ==================== SMOKE EFFECT ====================
		// Smoke rising from fire pit
		{
			let pos = Vector3(0, 1.5f, -15);
			let smokeEntity = mScene.CreateEntity("Smoke");
			smokeEntity.Transform.SetPosition(pos);

			let config = ParticleEmitterConfig.CreateSmoke();
			config.EmissionRate = 8;
			config.MaxParticles = 100;

			let emitter = new ParticleEmitterComponent(config);
			smokeEntity.AddComponent(emitter);

			RegisterEffect(.(0, 3.0f, -15), .(128, 128, 128, 255), "SMOKE");
		}

		// ==================== MAGIC SPARKLE EFFECTS ====================
		// Magical orb floating near the fox
		{
			let pos = Vector3(12, 2.5f, 0);
			let magicEntity = mScene.CreateEntity("MagicOrb");
			magicEntity.Transform.SetPosition(pos);

			let config = ParticleEmitterConfig.CreateMagicSparkle();
			config.EmissionRate = 40;
			config.MaxParticles = 200;
			// Blue-purple magic
			config.SetColorOverLifetime(.(100, 150, 255, 255), .(200, 50, 255, 0));

			let emitter = new ParticleEmitterComponent(config);
			magicEntity.AddComponent(emitter);

			RegisterEffect(pos, .(150, 100, 255, 255), "MAGIC ORB");
		}

		// Green healing magic
		{
			let pos = Vector3(-10, 0.5f, 8);
			let healEntity = mScene.CreateEntity("HealingMagic");
			healEntity.Transform.SetPosition(pos);

			let config = ParticleEmitterConfig.CreateMagicSparkle();
			config.EmissionRate = 25;
			config.MaxParticles = 150;
			config.SetSphereEmission(1.0f);
			config.Gravity = .(0, 1.5f, 0);
			// Green healing colors
			config.SetColorOverLifetime(.(50, 255, 100, 255), .(100, 255, 150, 0));

			let emitter = new ParticleEmitterComponent(config);
			healEntity.AddComponent(emitter);

			RegisterEffect(pos, .(50, 255, 100, 255), "HEAL");
		}

		// ==================== SPARKS EFFECT ====================
		// Welding/grinding sparks
		{
			let pos = Vector3(10, 1.0f, -8);
			let sparksEntity = mScene.CreateEntity("Sparks");
			sparksEntity.Transform.SetPosition(pos);

			let config = ParticleEmitterConfig.CreateSparks();
			config.EmissionRate = 60;
			config.MaxParticles = 300;

			let emitter = new ParticleEmitterComponent(config);
			sparksEntity.AddComponent(emitter);

			RegisterEffect(pos, .(255, 255, 100, 255), "SPARKS");
		}

		// ==================== WATER FOUNTAIN ====================
		// Classic fountain with blue particles
		{
			let pos = Vector3(-12, 0.5f, -8);
			let fountainEntity = mScene.CreateEntity("WaterFountain");
			fountainEntity.Transform.SetPosition(pos);

			let config = new ParticleEmitterConfig();
			config.EmissionRate = 100;
			config.Lifetime = .(1.5f, 2.5f);
			config.InitialSpeed = .(8.0f, 12.0f);
			config.InitialSize = .(0.08f, 0.15f);
			config.MaxParticles = 500;
			config.SetConeEmission(8);
			config.BlendMode = .AlphaBlend;
			config.Gravity = .(0, -15.0f, 0);
			// Blue water colors
			config.StartColor = .(.(100, 180, 255, 220));
			config.EndColor = .(.(50, 120, 200, 0));
			config.SetSizeOverLifetime(1.0f, 0.5f);

			let emitter = new ParticleEmitterComponent(config);
			fountainEntity.AddComponent(emitter);

			RegisterEffect(pos, .(100, 180, 255, 255), "FOUNTAIN");
		}

		// ==================== SNOW/ASH EFFECT ====================
		// Gentle falling particles over part of the scene
		{
			let pos = Vector3(8, 8, 10);  // Label at lower height for visibility
			let snowEntity = mScene.CreateEntity("Snow");
			snowEntity.Transform.SetPosition(.(8, 12, 10));

			let config = new ParticleEmitterConfig();
			config.EmissionRate = 30;
			config.Lifetime = .(4.0f, 6.0f);
			config.InitialSpeed = .(0.2f, 0.8f);
			config.InitialSize = .(0.05f, 0.12f);
			config.MaxParticles = 300;
			config.SetBoxEmission(.(8, 0.5f, 8), false);
			config.BlendMode = .AlphaBlend;
			config.Gravity = .(0, -1.0f, 0);
			config.Drag = 0.3f;
			// White snow
			config.StartColor = .(.(255, 255, 255, 200));
			config.EndColor = .(.(200, 200, 220, 0));
			config.InitialRotationSpeed = .(-1.0f, 1.0f);

			let emitter = new ParticleEmitterComponent(config);
			snowEntity.AddComponent(emitter);

			RegisterEffect(pos, .(255, 255, 255, 255), "SNOW");
		}

		// ==================== FAIRY DUST / FIREFLIES ====================
		// Floating glowing particles
		{
			let pos = Vector3(-8, 1.5f, 12);
			let fairyEntity = mScene.CreateEntity("FairyDust");
			fairyEntity.Transform.SetPosition(pos);

			let config = new ParticleEmitterConfig();
			config.EmissionRate = 15;
			config.Lifetime = .(2.0f, 4.0f);
			config.InitialSpeed = .(0.3f, 1.0f);
			config.InitialSize = .(0.08f, 0.15f);
			config.MaxParticles = 100;
			config.SetSphereEmission(2.0f);
			config.BlendMode = .Additive;
			config.Gravity = .(0, 0.2f, 0);
			config.Drag = 0.8f;
			// Golden yellow glow
			config.StartColor = .(.(255, 220, 100, 255));
			config.EndColor = .(.(255, 180, 50, 0));
			config.SetSizeOverLifetime(0.5f, 1.5f);
			config.SetAlphaOverLifetime(1.0f, 0.0f);

			let emitter = new ParticleEmitterComponent(config);
			fairyEntity.AddComponent(emitter);

			RegisterEffect(pos, .(255, 220, 100, 255), "FIREFLIES");
		}

		// ==================== STEAM/MIST RISING ====================
		// Steam vent effect
		{
			let pos = Vector3(0, 0.1f, 10);
			let steamEntity = mScene.CreateEntity("Steam");
			steamEntity.Transform.SetPosition(pos);

			let config = new ParticleEmitterConfig();
			config.EmissionRate = 20;
			config.Lifetime = .(2.0f, 3.5f);
			config.InitialSpeed = .(2.0f, 4.0f);
			config.InitialSize = .(0.3f, 0.6f);
			config.MaxParticles = 150;
			config.SetConeEmission(20);
			config.BlendMode = .AlphaBlend;
			config.Gravity = .(0, 1.5f, 0);
			config.Drag = 0.4f;
			// White/light gray steam
			config.StartColor = .(.(240, 240, 255, 180));
			config.EndColor = .(.(200, 200, 220, 0));
			config.SetSizeOverLifetime(1.0f, 3.0f);

			let emitter = new ParticleEmitterComponent(config);
			steamEntity.AddComponent(emitter);

			RegisterEffect(pos, .(200, 200, 255, 255), "STEAM");
		}

		// Print legend to console
		Console.WriteLine("\n=== PARTICLE EFFECTS LEGEND ===");
		for (let label in mParticleLabels)
		{
			Console.WriteLine($"  [{label.Name}] at ({label.Position.X:0.0}, {label.Position.Y:0.0}, {label.Position.Z:0.0})");
		}
		Console.WriteLine("================================\n");
	}

	private void CreateFoxEntity()
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

		// Exit if we failed to load the fox
		if (mFoxResource == null)
			return;

		// Create fox entity - position outside the cube grid
		mFoxEntity = mScene.CreateEntity("Fox");
		mFoxEntity.Transform.SetPosition(.(15, 0, 0));  // Outside cube grid (cubes span -12 to +9)
		mFoxEntity.Transform.SetScale(Vector3(0.05f));

		// Create skinned mesh renderer component
		let meshComponent = new SkinnedMeshComponent();
		mFoxEntity.AddComponent(meshComponent);

		// Use the resource's skeleton directly (shared, not owned)
		if (mFoxResource.Skeleton != null)
			meshComponent.SetSkeleton(mFoxResource.Skeleton);

		// Add animation clips from resource (shared references)
		for (let clip in mFoxResource.Animations)
			meshComponent.AddAnimationClip(clip);

		// Set the mesh (triggers GPU upload)
		meshComponent.SetMesh(mFoxResource.Mesh);

		// Load fox texture and set on material
		let texPath = GetAssetPath("samples/models/Fox/glTF/Texture.png", .. scope .());
		let resourceManager = mRendererService.ResourceManager;
		let materialSystem = mRendererService.MaterialSystem;

		if (resourceManager != null && materialSystem != null)
		{
			let imageLoader = scope SDLImageLoader();
			if (imageLoader.LoadFromFile(texPath) case .Ok(var loadInfo))
			{
				defer loadInfo.Dispose();
				Console.WriteLine($"Fox texture: {loadInfo.Width}x{loadInfo.Height}");

				// Upload texture via ResourceManager
				mFoxTexture = resourceManager.CreateTextureFromData(
					loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .(loadInfo.Data.Ptr, loadInfo.Data.Count));

				if (mFoxTexture.IsValid)
				{
					// Set texture on Fox material instance
					if (mFoxMaterial.IsValid)
					{
						let foxInstance = materialSystem.GetInstance(mFoxMaterial);
						if (foxInstance != null)
						{
							foxInstance.SetTexture("albedoMap", mFoxTexture);
							materialSystem.UploadInstance(mFoxMaterial);
							Console.WriteLine("Fox texture set on material");
						}
					}
				}
			}
			else
			{
				Console.WriteLine($"Failed to load fox texture: {texPath}");
			}
		}

		// Set PBR material on skinned mesh
		if (mFoxMaterial.IsValid)
			meshComponent.SetMaterial(mFoxMaterial);

		// Start playing first animation
		if (meshComponent.AnimationClips.Count > 0)
		{
			meshComponent.PlayAnimation(0, true);
			Console.WriteLine($"Fox animation playing: {meshComponent.AnimationClips[0].Name}");
		}
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		// Update camera viewport through component
		if (let cameraComp = mCameraEntity?.GetComponent<CameraComponent>())
		{
			cameraComp.SetViewport(width, height);
		}
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

		// WASD movement using entity Transform
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

		// Cycle through Fox animations with Space
		if (mFoxEntity != null && keyboard.IsKeyPressed(.Space))
		{
			if (let meshComponent = mFoxEntity.GetComponent<SkinnedMeshComponent>())
			{
				let animCount = (int32)meshComponent.AnimationClips.Count;
				if (animCount > 0)
				{
					mCurrentAnimIndex = (mCurrentAnimIndex + 1) % animCount;
					meshComponent.PlayAnimation(mCurrentAnimIndex, true);
					Console.WriteLine($"Playing animation: {meshComponent.AnimationClips[mCurrentAnimIndex].Name}");
				}
			}
		}

		// Light direction control with arrow keys
		float lightSpeed = 1.0f * DeltaTime;
		bool lightChanged = false;

		if (keyboard.IsKeyDown(.Left))  { mLightYaw -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Right)) { mLightYaw += lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Up))    { mLightPitch -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Down))  { mLightPitch += lightSpeed; lightChanged = true; }

		// Clamp pitch to avoid light pointing up
		mLightPitch = Math.Clamp(mLightPitch, -Math.PI_f * 0.45f, -0.1f);

		if (lightChanged)
			UpdateLightDirection();

		// Light intensity control with Z/X
		float intensitySpeed = 1.0f * DeltaTime;
		bool intensityChanged = false;

		if (keyboard.IsKeyDown(.Z)) { mLightIntensity = Math.Max(0.1f, mLightIntensity - intensitySpeed); intensityChanged = true; }
		if (keyboard.IsKeyDown(.X)) { mLightIntensity = Math.Min(5.0f, mLightIntensity + intensitySpeed); intensityChanged = true; }

		if (intensityChanged)
			UpdateLightIntensity();
	}

	private void UpdateCameraDirection()
	{
		if (mCameraEntity == null)
			return;

		// Compute forward from yaw/pitch and use LookAt to set rotation
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
		// Convert spherical coordinates to direction vector
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
		{
			lightComp.Intensity = mLightIntensity;
		}
	}

	private void UpdateDebugDrawing()
	{
		if (!mDebugDrawService.IsInitialized)
			return;

		// Set screen size for 2D text and draw FPS
		mDebugDrawService.SetScreenSize(SwapChain.Width, SwapChain.Height);

		// Draw FPS at top-right corner
		// Label is fixed, number is right-aligned separately to avoid shifting
		let fps = (DeltaTime > 0) ? (1.0f / DeltaTime) : 0;
		let fpsScale = 2.0f;
		let charWidth = 8.0f * fpsScale;  // 16 pixels per char at scale 2
		let numberWidth = 6 * charWidth;  // Reserve space for "999.9" + margin
		let rightMargin = 10.0f;

		// Draw "FPS:" label at fixed position
		let labelX = (float)SwapChain.Width - rightMargin - numberWidth - (4 * charWidth);
		mDebugDrawService.DrawText2D("FPS:", labelX, 10, .(255, 255, 0, 255), fpsScale);

		// Draw number right-aligned
		let fpsNumber = scope String();
		fpsNumber.AppendF("{0:0.0}", fps);
		mDebugDrawService.DrawText2DRight(fpsNumber, rightMargin, 10, .(255, 255, 0, 255), fpsScale);

		// Draw light direction as an arrow from above origin
		let lightDir = GetLightDirection();
		let lightStart = Vector3(0, 5, 0);  // Start above ground

		// Draw XYZ axis at the light arrow start for reference
		mDebugDrawService.DrawAxes(lightStart, 1.5f);

		// Yellow line for light direction with arrow
		let lightEnd = lightStart + lightDir * 5.0f;
		mDebugDrawService.DrawLine(lightStart, lightEnd, .(255, 255, 0, 255));

		// Arrow head
		let right = Vector3.Normalize(Vector3.Cross(lightDir, Vector3.Up));
		let up = Vector3.Normalize(Vector3.Cross(right, lightDir));
		let arrowSize = 0.3f;
		let arrowColor = Color(255, 128, 0, 255);

		mDebugDrawService.DrawLine(lightEnd, lightEnd - lightDir * arrowSize + right * arrowSize * 0.5f, arrowColor);
		mDebugDrawService.DrawLine(lightEnd, lightEnd - lightDir * arrowSize - right * arrowSize * 0.5f, arrowColor);
		mDebugDrawService.DrawLine(lightEnd, lightEnd - lightDir * arrowSize + up * arrowSize * 0.5f, arrowColor);
		mDebugDrawService.DrawLine(lightEnd, lightEnd - lightDir * arrowSize - up * arrowSize * 0.5f, arrowColor);

		// Draw a small grid on the ground (as demonstration)
		mDebugDrawService.DrawGrid(.(0, 0.01f, 0), 10, 10, .(128, 128, 128, 128));

		// Draw a wireframe sphere around one of the cubes
		mDebugDrawService.DrawWireSphere(.(3, 1.5f, 3), 1.0f, .(0, 255, 255, 255));

		// Draw a wireframe box around the fox
		if (mFoxEntity != null)
		{
			let foxPos = mFoxEntity.Transform.WorldPosition;
			mDebugDrawService.DrawWireBox(foxPos - .(1.5f, 0, 1.5f), foxPos + .(1.5f, 3.0f, 1.5f), .(255, 0, 255, 255));
		}

		// Draw colored markers at each particle effect location
		// Get camera vectors for text billboarding
		let cameraRight = mCameraEntity.Transform.Right;
		let cameraUp = mCameraEntity.Transform.Up;
		mDebugDrawService.SetCameraVectors(cameraRight, cameraUp);

		for (let label in mParticleLabels)
		{
			let pos = label.Position;
			let color = label.MarkerColor;

			// Draw a diamond/octahedron marker
			let size = 0.5f;
			let top = pos + .(0, size * 1.5f, 0);
			let bottom = pos - .(0, size * 0.5f, 0);
			let center = pos + .(0, size * 0.5f, 0);

			// Vertical line
			mDebugDrawService.DrawLine(top, bottom, color);

			// Cross at center
			mDebugDrawService.DrawLine(center + .(size, 0, 0), center - .(size, 0, 0), color);
			mDebugDrawService.DrawLine(center + .(0, 0, size), center - .(0, 0, size), color);

			// Connect to top and bottom to form diamond shape
			mDebugDrawService.DrawLine(top, center + .(size, 0, 0), color);
			mDebugDrawService.DrawLine(top, center - .(size, 0, 0), color);
			mDebugDrawService.DrawLine(top, center + .(0, 0, size), color);
			mDebugDrawService.DrawLine(top, center - .(0, 0, size), color);

			mDebugDrawService.DrawLine(bottom, center + .(size, 0, 0), color);
			mDebugDrawService.DrawLine(bottom, center - .(size, 0, 0), color);
			mDebugDrawService.DrawLine(bottom, center + .(0, 0, size), color);
			mDebugDrawService.DrawLine(bottom, center - .(0, 0, size), color);

			// Draw text label above the marker
			let textPos = top + .(0, 0.3f, 0);
			mDebugDrawService.DrawTextCentered(label.Name, textPos, color, 1.5f);
		}
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Update the context - handles entity transforms, proxy sync, visibility culling
		mContext.Update(deltaTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		// Debug: print stats on first few frames
		static int32 debugFrameCount = 0;
		if (debugFrameCount < 5)
		{
			debugFrameCount++;
			Console.WriteLine($"[DEBUG] Frame {debugFrameCount}: Meshes={mRenderSceneComponent.MeshCount}, Visible={mRenderSceneComponent.VisibleInstanceCount}, HasCamera={mRenderSceneComponent.GetMainCameraProxy() != null}");
		}

		mCurrentFrameIndex = frameIndex;

		// Add debug drawing (axes, grid, wireframes)
		UpdateDebugDrawing();

		// Begin render graph frame - adds shadow cascades, Scene3D, and debug draw passes
		mRendererService.BeginFrame(
			(uint32)frameIndex, DeltaTime, TotalTime,
			SwapChain.CurrentTexture, SwapChain.CurrentTextureView,
			mDepthTexture, DepthTextureView);
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Execute all render graph passes (shadow cascades, Scene3D, debug lines)
		mRendererService.ExecuteFrame(encoder);
		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we use OnRenderFrame for shadow support
	}

	protected override void OnCleanup()
	{
		mContext?.Shutdown();

		// Wait for GPU to finish before cleanup
		Device.WaitIdle();

		// Clean up materials
		if (mRendererService?.MaterialSystem != null)
		{
			let materialSystem = mRendererService.MaterialSystem;

			if (mFoxMaterial.IsValid)
				materialSystem.ReleaseInstance(mFoxMaterial);

			for (let cubeMat in mCubeMaterials)
			{
				if (cubeMat.IsValid)
					materialSystem.ReleaseInstance(cubeMat);
			}

			if (mGroundMaterial.IsValid)
				materialSystem.ReleaseInstance(mGroundMaterial);

			if (mPBRMaterial.IsValid)
				materialSystem.ReleaseMaterial(mPBRMaterial);
		}

		// Clean up fox texture
		if (mFoxTexture.IsValid && mRendererService?.ResourceManager != null)
			mRendererService.ResourceManager.ReleaseTexture(mFoxTexture);

		// Services are deleted in reverse order of creation
		delete mDebugDrawService;
		delete mRendererService;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let sample = scope RendererIntegratedSample();
		return sample.Run();
	}
}
