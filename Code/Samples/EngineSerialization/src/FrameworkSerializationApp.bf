namespace EngineSerialization;

using System;
using System.IO;
using Sedulous.Core.Mathematics;
using Sedulous.Runtime.Client;
using Sedulous.Runtime;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Render;
using Sedulous.Engine.Animation;
using Sedulous.RHI;
using Sedulous.Render;
using Sedulous.Profiler;
using Sedulous.Resources;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Geometry.Tooling;
using Sedulous.Geometry.Tooling.Resources;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Models.FBX;
using Sedulous.Imaging;
using Sedulous.Materials.Resources;
using Sedulous.Textures.Resources;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using System.Collections;

class EngineSerializationApp : Application
{
	private const StringView GLTF_MODEL_PATH = "samples/models/UltimateMonsters/Blob/glTF/GreenBlob.gltf";
	private const StringView GLTF_BASE_PATH = "samples/models/UltimateMonsters/Blob/glTF";
	private const StringView FBX_MODEL_PATH = "samples/models/UltimateMonsters/Blob/FBX/GreenBlob.fbx";
	private const StringView FBX_BASE_PATH = "samples/models/UltimateMonsters/Blob/FBX";
	private const StringView FOX_MODEL_PATH = "samples/models/Fox/glTF/Fox.gltf";
	private const StringView FOX_BASE_PATH = "samples/models/Fox/glTF";
	private const StringView CACHE_REL_PATH = "cache";

	// Framework
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private Scene mMainScene;

	// Render system
	private RenderSystem mRenderSystem;
	private RenderView mRenderView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private ForwardTransparentFeature mTransparentFeature;
	private ParticleFeature mParticleFeature;
	private SpriteFeature mSpriteFeature;
	private SkyFeature mSkyFeature;
	private OverlayRenderFeature mOverlayFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Camera
	private OrbitFlyCamera mCamera ~ delete _;
	private float mDeltaTime = 0.016f;

	// Scene resource
	private SceneResource mSceneResource ~ delete _;

	// Asset registry
	private ResourceRegistry mRegistry = new .() ~ delete _;

	// Cached resource info for GLTF import (populated during import)
	private String mGltfSkinnedMeshPath ~ delete _;
	private String mGltfStaticMeshPath ~ delete _;
	private String mGltfSkeletonPath ~ delete _;
	private Guid mGltfSkinnedMeshId;
	private Guid mGltfStaticMeshId;
	private Guid mGltfSkeletonId;

	// Cached resource info for FBX import (populated during import)
	private String mFbxSkinnedMeshPath ~ delete _;
	private String mFbxStaticMeshPath ~ delete _;
	private String mFbxSkeletonPath ~ delete _;
	private Guid mFbxSkinnedMeshId;
	private Guid mFbxStaticMeshId;
	private Guid mFbxSkeletonId;

	// Cached resource info for Fox import (populated during import)
	private String mFoxSkinnedMeshPath ~ delete _;
	private String mFoxStaticMeshPath ~ delete _;
	private String mFoxSkeletonPath ~ delete _;
	private Guid mFoxSkinnedMeshId;
	private Guid mFoxStaticMeshId;
	private Guid mFoxSkeletonId;

	// Material refs (multiple per model for multi-submesh support)
	private List<ResourceRef> mGltfMaterialRefs = new .() ~ { for (var r in _) r.Dispose(); delete _; };
	private List<ResourceRef> mFbxMaterialRefs = new .() ~ { for (var r in _) r.Dispose(); delete _; };
	private List<ResourceRef> mFoxMaterialRefs = new .() ~ { for (var r in _) r.Dispose(); delete _; };

	// All animation resource refs (for cycling - GLTF animations)
	private List<ResourceRef> mGltfAnimationRefs = new .() ~ { for (var r in _) r.Dispose(); delete _; };
	// FBX animation refs
	private List<ResourceRef> mFbxAnimationRefs = new .() ~ { for (var r in _) r.Dispose(); delete _; };
	// Fox animation refs
	private List<ResourceRef> mFoxAnimationRefs = new .() ~ { for (var r in _) r.Dispose(); delete _; };

	// Runtime animation cycling state
	private List<ResourceHandle<AnimationClipResource>> mLoadedAnimClips = new .() ~ { for (var h in _) h.Release(); delete _; };
	private int mCurrentAnimIndex = 0;
	private EntityId mGltfEntity;

	// Checkerboard texture for sprite (procedurally generated, not saved to file)
	private ResourceHandle<TextureResource> mCheckerboardTexture /*~ _.Release()*/;

	// Deferred sky setup (must happen after first BeginFrame flushes the init transfer batch)
	private bool mNeedsSkySetup = true;

	public this() : base()
	{
		mCamera = new .();
		mCamera.CurrentMode = .Flythrough;
		mCamera.OrbitalYaw = 0.5f;
		mCamera.OrbitalPitch = 0.4f;
		mCamera.OrbitalDistance = 5.0f;
		mCamera.OrbitalTarget = .(0, 0.8f, 0);
		mCamera.FlyPosition = .(0, 1.5f, 5.0f);
		mCamera.FlyPitch = -0.1f;
		mCamera.Update();
	}

	protected override void OnInitialize(Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		Console.WriteLine("=== Framework Serialization Sample ===\n");

		InitializeRenderSystem();
		RegisterSubsystems(context);
	}

	protected override void OnContextStarted()
	{
		SProfiler.Initialize();

		// Import and cache assets, then create/load scene
		ImportAndCacheAssets();
		CreateCheckerboardTexture();
		LoadOrCreateScene();

		// Assign procedural textures to loaded entities
		SetupSpriteTexture();

		// Load all animation clips for runtime cycling
		SetupAnimationCycling();
	}

	private void InitializeRenderSystem()
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, mSwapChain.Width, mSwapChain.Height, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null, .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}

		mRenderView = new RenderView();
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.FieldOfView = Math.PI_f / 4.0f;
		mRenderView.NearPlane = 0.1f;
		mRenderView.FarPlane = 100.0f;

		// Register render features (matching EngineSandbox)
		RegisterRenderFeatures();
	}

	private void RegisterRenderFeatures()
	{
		// Depth prepass
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		// Forward opaque
		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		// Forward transparent
		mTransparentFeature = new ForwardTransparentFeature();
		mRenderSystem.RegisterFeature(mTransparentFeature);

		// Sky (gradient environment map — sky setup deferred to first render frame)
		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		// Particles
		mParticleFeature = new ParticleFeature();
		mRenderSystem.RegisterFeature(mParticleFeature);

		// Sprites
		mSpriteFeature = new SpriteFeature();
		mRenderSystem.RegisterFeature(mSpriteFeature);

		// Debug render
		mOverlayFeature = new OverlayRenderFeature();
		mRenderSystem.RegisterFeature(mOverlayFeature);

		// Final output
		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void RegisterSubsystems(Context context)
	{
		// Scene
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);

		// Animation
		let animSubsystem = new AnimationSubsystem();
		context.RegisterSubsystem(animSubsystem);

		// Render
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);
	}

	// ==================== Asset Import & Cache ====================

	private void ImportAndCacheAssets()
	{
		// Initialize model loaders
		GltfModels.Initialize();
		FbxModels.Initialize();

		String cacheDir = scope .();
		GetAssetPath(CACHE_REL_PATH, cacheDir);

		String registryPath = scope .();
		registryPath.AppendF("{}/registry.txt", cacheDir);

		Console.WriteLine("--- Asset Import & Cache ---");

		if (File.Exists(registryPath))
		{
			// Cache exists - load registry from file
			if (mRegistry.LoadFromFile(registryPath) case .Ok)
			{
				Console.WriteLine($"Loaded registry from cache: {mRegistry.Count} entries");
				// Recover cached paths for entity creation (in case scene file was deleted)
				RecoverCachedPaths(cacheDir);
			}
			else
				Console.WriteLine("WARNING: Failed to load registry, will re-import");
		}

		if (mRegistry.Count == 0)
		{
			// No cache - import same model via both GLTF and FBX for comparison
			ImportModel(GLTF_MODEL_PATH, GLTF_BASE_PATH, "greenblob_gltf", cacheDir,
				ref mGltfSkinnedMeshPath, ref mGltfSkinnedMeshId,
				ref mGltfStaticMeshPath, ref mGltfStaticMeshId,
				mGltfMaterialRefs,
				ref mGltfSkeletonPath, ref mGltfSkeletonId,
				mGltfAnimationRefs);

			ImportModel(FBX_MODEL_PATH, FBX_BASE_PATH, "greenblob_fbx", cacheDir,
				ref mFbxSkinnedMeshPath, ref mFbxSkinnedMeshId,
				ref mFbxStaticMeshPath, ref mFbxStaticMeshId,
				mFbxMaterialRefs,
				ref mFbxSkeletonPath, ref mFbxSkeletonId,
				mFbxAnimationRefs);

			ImportModel(FOX_MODEL_PATH, FOX_BASE_PATH, "fox_gltf", cacheDir,
				ref mFoxSkinnedMeshPath, ref mFoxSkinnedMeshId,
				ref mFoxStaticMeshPath, ref mFoxStaticMeshId,
				mFoxMaterialRefs,
				ref mFoxSkeletonPath, ref mFoxSkeletonId,
				mFoxAnimationRefs);

			// Save registry
			Directory.CreateDirectory(cacheDir);
			if (mRegistry.SaveToFile(registryPath) case .Ok)
				Console.WriteLine($"  Registry saved: {mRegistry.Count} entries");
			else
				Console.WriteLine("  WARNING: Failed to save registry file");
		}

		// Register the registry with the resource system
		mContext.Resources.AddRegistry(mRegistry);
		Console.WriteLine($"Registry registered with ResourceSystem ({mRegistry.Count} entries)");

		// Print registry contents
		PrintRegistryEntries();
		Console.WriteLine();
	}

	private void ImportModel(StringView modelRelPath, StringView baseRelPath, StringView subfolder, StringView cacheDir,
		ref String skinnedMeshPath, ref Guid skinnedMeshId,
		ref String staticMeshPath, ref Guid staticMeshId,
		List<ResourceRef> materialRefs,
		ref String skeletonPath, ref Guid skeletonId,
		List<ResourceRef> animationRefs)
	{
		String modelPath = scope .();
		GetAssetPath(modelRelPath, modelPath);

		String basePath = scope .();
		GetAssetPath(baseRelPath, basePath);

		Console.WriteLine($"Importing model from: {modelPath}");

		// Load model via factory (auto-selects GLTF or FBX loader by extension)
		let model = new Model();
		if (ModelLoaderFactory.LoadModel(modelPath, model) != .Ok)
		{
			Console.WriteLine($"ERROR: Failed to load model: {modelPath}");
			delete model;
			return;
		}
		defer delete model;

		// Import all resource types (order: Skeletons→Textures→Materials→SkinnedMeshes→Animations)
		let importOptions = new ModelImportOptions();
		importOptions.BasePath.Set(basePath);
		importOptions.Flags = .Skeletons | .Meshes | .SkinnedMeshes | .Animations | .Materials | .Textures;

		let importer = scope ModelImporter(importOptions);
		let result = importer.Import(model);
		defer delete result;

		Console.WriteLine($"  Imported: {result.TotalCount} resources");
		Console.WriteLine($"    Skeletons: {result.Skeletons.Count}");
		Console.WriteLine($"    Textures: {result.Textures.Count}");
		Console.WriteLine($"    NewMaterials: {result.Materials.Count}");
		Console.WriteLine($"    StaticMeshes: {result.StaticMeshes.Count}");
		Console.WriteLine($"    SkinnedMeshes: {result.SkinnedMeshes.Count}");
		Console.WriteLine($"    Animations: {result.Animations.Count}");

		if (!result.Success)
		{
			Console.WriteLine("  Errors:");
			for (let err in result.Errors)
				Console.WriteLine($"    - {err}");
		}

		if (result.Warnings.Count > 0)
		{
			Console.WriteLine("  Warnings:");
			for (let warn in result.Warnings)
				Console.WriteLine($"    - {warn}");
		}

		// Save all resources to model-specific cache subdirectory
		let modelCacheDir = scope String();
		modelCacheDir.AppendF("{}/{}", cacheDir, subfolder);
		Directory.CreateDirectory(modelCacheDir);

		Console.WriteLine($"\nSaving resources to: {modelCacheDir}");
		if (ResourceSerializer.SaveImportResult(result, modelCacheDir, Context.Resources.SerializerProvider) case .Ok(let resourceResult))
		{
			Console.WriteLine("  Resources saved successfully");

			// Build registry from resource result (has GUIDs)
			BuildRegistryFromResult(resourceResult, modelCacheDir,
				ref skinnedMeshPath, ref skinnedMeshId,
				ref staticMeshPath, ref staticMeshId,
				materialRefs,
				ref skeletonPath, ref skeletonId,
				animationRefs);

			delete resourceResult;
		}
		else
		{
			Console.WriteLine("  ERROR: Failed to save resources");
			return;
		}
	}

	private void BuildRegistryFromResult(ResourceImportResult result, StringView cacheDir,
		ref String skinnedMeshPath, ref Guid skinnedMeshId,
		ref String staticMeshPath, ref Guid staticMeshId,
		List<ResourceRef> materialRefs,
		ref String skeletonPath, ref Guid skeletonId,
		List<ResourceRef> animationRefs)
	{
		for (let skeleton in result.Skeletons)
		{
			RegisterResource(skeleton, cacheDir, "skeleton");
			if (skeletonPath == null)
			{
				skeletonPath = new String();
				skeletonPath.AppendF("{}/{}.skeleton", cacheDir, skeleton.Name);
				ResourceSerializer.SanitizePath(skeletonPath);
				skeletonId = skeleton.Id;
			}
		}

		for (let texture in result.Textures)
			RegisterResource(texture, cacheDir, "texture");

		for (let material in result.Materials)
		{
			RegisterResource(material, cacheDir, "material");
			if (materialRefs != null)
			{
				let matPath = scope String();
				matPath.AppendF("{}/{}.material", cacheDir, material.Name);
				ResourceSerializer.SanitizePath(matPath);
				materialRefs.Add(ResourceRef(material.Id, matPath));
			}
		}

		for (let mesh in result.SkinnedMeshes)
		{
			RegisterResource(mesh, cacheDir, "skinnedmesh");
			if (skinnedMeshPath == null)
			{
				skinnedMeshPath = new String();
				skinnedMeshPath.AppendF("{}/{}.skinnedmesh", cacheDir, mesh.Name);
				ResourceSerializer.SanitizePath(skinnedMeshPath);
				skinnedMeshId = mesh.Id;
			}
		}

		for (let mesh in result.StaticMeshes)
		{
			RegisterResource(mesh, cacheDir, "mesh");
			if (staticMeshPath == null)
			{
				staticMeshPath = new String();
				staticMeshPath.AppendF("{}/{}.mesh", cacheDir, mesh.Name);
				ResourceSerializer.SanitizePath(staticMeshPath);
				staticMeshId = mesh.Id;
			}
		}

		if (animationRefs != null)
		{
			for (let animation in result.Animations)
			{
				RegisterResource(animation, cacheDir, "animation");
				let animPath = scope String();
				animPath.AppendF("{}/{}.animation", cacheDir, animation.Name);
				ResourceSerializer.SanitizePath(animPath);
				animationRefs.Add(ResourceRef(animation.Id, animPath));
			}
		}
		else
		{
			for (let animation in result.Animations)
				RegisterResource(animation, cacheDir, "animation");
		}
	}

	private void RegisterResource(IResource resource, StringView cacheDir, StringView @extension)
	{
		let path = scope String();
		path.AppendF("{}/{}.{}", cacheDir, resource.Name, @extension);
		ResourceSerializer.SanitizePath(path);
		mRegistry.Register(resource.Id, path);
	}

	/// Recovers cached resource paths by scanning the cache subdirectories.
	/// Used when the registry was loaded from file (so we didn't import).
	private void RecoverCachedPaths(StringView cacheDir)
	{
		if (mGltfSkinnedMeshPath != null)
			return; // Already populated

		// Recover GLTF import paths
		let gltfDir = scope String();
		gltfDir.AppendF("{}/greenblob_gltf", cacheDir);
		RecoverModelPaths(gltfDir,
			ref mGltfSkinnedMeshPath, ref mGltfSkinnedMeshId,
			ref mGltfStaticMeshPath, ref mGltfStaticMeshId,
			mGltfMaterialRefs,
			ref mGltfSkeletonPath, ref mGltfSkeletonId,
			mGltfAnimationRefs);

		// Recover FBX import paths
		let fbxDir = scope String();
		fbxDir.AppendF("{}/greenblob_fbx", cacheDir);
		RecoverModelPaths(fbxDir,
			ref mFbxSkinnedMeshPath, ref mFbxSkinnedMeshId,
			ref mFbxStaticMeshPath, ref mFbxStaticMeshId,
			mFbxMaterialRefs,
			ref mFbxSkeletonPath, ref mFbxSkeletonId,
			mFbxAnimationRefs);

		// Recover Fox import paths
		let foxDir = scope String();
		foxDir.AppendF("{}/fox_gltf", cacheDir);
		RecoverModelPaths(foxDir,
			ref mFoxSkinnedMeshPath, ref mFoxSkinnedMeshId,
			ref mFoxStaticMeshPath, ref mFoxStaticMeshId,
			mFoxMaterialRefs,
			ref mFoxSkeletonPath, ref mFoxSkeletonId,
			mFoxAnimationRefs);
	}

	private void RecoverModelPaths(StringView dir,
		ref String skinnedMeshPath, ref Guid skinnedMeshId,
		ref String staticMeshPath, ref Guid staticMeshId,
		List<ResourceRef> materialRefs,
		ref String skeletonPath, ref Guid skeletonId,
		List<ResourceRef> animationRefs)
	{
		if (!Directory.Exists(dir))
			return;

		for (let entry in Directory.EnumerateFiles(dir))
		{
			let filePath = scope String();
			entry.GetFilePath(filePath);
			filePath.Replace('\\', '/');

			if (filePath.EndsWith(".skinnedmesh") && skinnedMeshPath == null)
			{
				skinnedMeshPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out skinnedMeshId);
			}
			else if (filePath.EndsWith(".mesh") && staticMeshPath == null)
			{
				staticMeshPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out staticMeshId);
			}
			else if (filePath.EndsWith(".material") && materialRefs != null)
			{
				Guid matId = .();
				mRegistry.TryResolveId(filePath, out matId);
				materialRefs.Add(ResourceRef(matId, filePath));
			}
			else if (filePath.EndsWith(".skeleton") && skeletonPath == null)
			{
				skeletonPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out skeletonId);
			}
			else if (filePath.EndsWith(".animation") && animationRefs != null)
			{
				Guid animId = .();
				mRegistry.TryResolveId(filePath, out animId);
				animationRefs.Add(ResourceRef(animId, filePath));
			}
		}
	}

	private void PrintRegistryEntries()
	{
		Console.WriteLine("Registry entries:");
		Console.WriteLine($"  Total: {mRegistry.Count} GUID-to-path mappings");
	}

	// ==================== Scene Management ====================

	private void LoadOrCreateScene()
	{
		// Create scene via subsystem — modules get attached immediately,
		// so both module APIs and module serializers are available.
		mMainScene = mSceneSubsystem.CreateScene("SerializationTest");
		mSceneSubsystem.SetActiveScene(mMainScene);

		// SceneResource is a non-owning serialization wrapper
		mSceneResource = new SceneResource(mMainScene);

		String scenePath = scope .();
		GetScenePath(scenePath);

		if (File.Exists(scenePath))
		{
			// Load existing scene — modules are present so all component
			// serializers can read data and create components via module APIs.
			switch (mSceneResource.Load(scenePath))
			{
			case .Ok:
				Console.WriteLine($"Loaded scene from file: {mMainScene.Name} ({mMainScene.EntityCount} entities)");
				PrintComponentData(mMainScene);

			case .Err:
				Console.WriteLine("ERROR: Failed to load scene from file, creating new one");
				PopulateAndSaveScene();
			}
		}
		else
		{
			PopulateAndSaveScene();
		}
	}

	private void GetScenePath(String outPath)
	{
		GetAssetPath(CACHE_REL_PATH, outPath);
		outPath.Append("/scene.oddl");
	}

	private void PopulateAndSaveScene()
	{
		let scene = mMainScene;

		// Root entity at origin with component
		let root = scene.CreateEntity();
		scene.SetName(root, "Root");
		scene.SetComponent<TestComponent>(root, .() { Speed = 5.0f, Health = 100, Active = true });

		// Child entity parented to root with component
		let child = scene.CreateEntity();
		scene.SetName(child, "Child");
		scene.SetTransform(child, .(.(2, 1, 0)));
		scene.SetParent(child, root);
		scene.SetComponent<TestComponent>(child, .() { Speed = 2.5f, Health = 50, Active = false });

		// Another root entity (no component - tests sparse serialization)
		let otherRoot = scene.CreateEntity();
		scene.SetName(otherRoot, "OtherRoot");
		scene.SetTransform(otherRoot, .(.(- 3, 0, 5)));

		// Directional light — modules are attached, so module APIs work
		let dirLight = scene.CreateEntity();
		scene.SetName(dirLight, "DirectionalLight");
		scene.SetTransform(dirLight, .(.(0, 10, 0), Quaternion.CreateFromAxisAngle(.(1, 0, 0), -0.8f)));
		if (let renderModule = scene.GetModule<RenderSceneModule>())
		{
			renderModule.CreateDirectionalLight(dirLight, .(1.0f, 0.95f, 0.8f), 2.0f);
			if (let proxy = renderModule.GetLightProxy(dirLight))
			{
				proxy.ShadowBias = 0.005f;
				proxy.ShadowNormalBias = 0.02f;
				proxy.LayerMask = 0xFFFFFFFF;
			}
		}

		// Point light
		let pointLight = scene.CreateEntity();
		scene.SetName(pointLight, "PointLight");
		scene.SetTransform(pointLight, .(.(3, 2, -1)));
		if (let renderModule = scene.GetModule<RenderSceneModule>())
		{
			renderModule.CreatePointLight(pointLight, .(1.0f, 0.8f, 0.6f), 5.0f, 15.0f);
			if (let proxy = renderModule.GetLightProxy(pointLight))
			{
				proxy.ShadowBias = 0.005f;
				proxy.ShadowNormalBias = 0.02f;
				proxy.LayerMask = 0xFFFFFFFF;
			}
		}

		// Model entities - GLTF and FBX imports side by side for comparison
		CreateSkinnedEntity(scene, "GreenBlob_GLTF", .(- 1, 0, 0),
			mGltfSkinnedMeshPath, mGltfSkinnedMeshId,
			mGltfMaterialRefs,
			mGltfSkeletonPath, mGltfSkeletonId,
			mGltfAnimationRefs);
		CreateStaticEntity(scene, "GreenBlob_GLTF_Static", .(- 3, 0, 0),
			mGltfStaticMeshPath, mGltfStaticMeshId,
			mGltfMaterialRefs);

		CreateSkinnedEntity(scene, "GreenBlob_FBX", .(1, 0, 0),
			mFbxSkinnedMeshPath, mFbxSkinnedMeshId,
			mFbxMaterialRefs,
			mFbxSkeletonPath, mFbxSkeletonId,
			mFbxAnimationRefs);
		CreateStaticEntity(scene, "GreenBlob_FBX_Static", .(3, 0, 0),
			mFbxStaticMeshPath, mFbxStaticMeshId,
			mFbxMaterialRefs);

		// Fox model - testing skinned mesh through same pipeline (scaled down, fox is ~100 units tall)
		CreateSkinnedEntity(scene, "Fox_GLTF", .(5, 0, 0),
			mFoxSkinnedMeshPath, mFoxSkinnedMeshId,
			mFoxMaterialRefs,
			mFoxSkeletonPath, mFoxSkeletonId,
			mFoxAnimationRefs);
		let foxSkinnedEntity = scene.FindByName("Fox_GLTF");
		if (scene.IsValid(foxSkinnedEntity))
			scene.SetTransform(foxSkinnedEntity, .(.(5, 0, 0), .Identity, .(0.04f, 0.04f, 0.04f)));

		CreateStaticEntity(scene, "Fox_GLTF_Static", .(7, 0, 0),
			mFoxStaticMeshPath, mFoxStaticMeshId,
			mFoxMaterialRefs);
		let foxStaticEntity = scene.FindByName("Fox_GLTF_Static");
		if (scene.IsValid(foxStaticEntity))
			scene.SetTransform(foxStaticEntity, .(.(7, 0, 0), .Identity, .(0.04f, 0.04f, 0.04f)));

		// Sprite entity with procedural checkerboard texture
		CreateSpriteEntity(scene);

		// Particle emitters
		CreateFireEmitter(scene);
		CreateSmokeEmitter(scene);

		// Save to file
		String scenePath = scope .();
		GetScenePath(scenePath);
		switch (mSceneResource.SaveToFile(scenePath))
		{
		case .Ok:
			Console.WriteLine($"\nCreated and saved scene: {scene.Name} ({scene.EntityCount} entities)");
			PrintComponentData(scene);

			// Register scene in asset registry and re-save
			mRegistry.Register(mSceneResource.Id, scenePath);
			String registryPath = scope .();
			GetAssetPath(CACHE_REL_PATH, registryPath);
			registryPath.Append("/registry.txt");
			mRegistry.SaveToFile(registryPath);
		case .Err:
			Console.WriteLine("ERROR: Failed to save scene to file");
		}
	}

	private void CreateSkinnedEntity(Scene scene, StringView name, Vector3 position,
		String skinnedMeshPath, Guid skinnedMeshId,
		List<ResourceRef> materialRefs,
		String skeletonPath, Guid skeletonId,
		List<ResourceRef> animationRefs)
	{
		if (skinnedMeshPath == null)
		{
			Console.WriteLine($"  WARNING: No cached skinned mesh for '{name}', skipping");
			return;
		}

		let entity = scene.CreateEntity();
		scene.SetName(entity, name);
		scene.SetTransform(entity, .(position));

		if (let renderModule = scene.GetModule<RenderSceneModule>())
		{
			var meshRef = ResourceRef(skinnedMeshId, skinnedMeshPath);
			renderModule.CreateSkinnedMeshFromRef(entity, meshRef);
			meshRef.Dispose();

			if (materialRefs != null && materialRefs.Count > 0)
			{
				let count = Math.Min((int32)materialRefs.Count, (int32)RenderConfig.MaxMaterialsPerMesh);
				for (int32 i = 0; i < count; i++)
					renderModule.SetSkinnedMeshMaterialRef(entity, i, materialRefs[i]);
			}
		}

		// Add skeletal animation via module API
		if (skeletonPath != null && animationRefs != null && animationRefs.Count > 0)
		{
			let firstAnim = animationRefs[0];
			if (let animModule = scene.GetModule<AnimationSceneModule>())
			{
				var skeletonRef = ResourceRef(skeletonId, skeletonPath);
				var animClipRef = ResourceRef(firstAnim.Id, firstAnim.Path);
				animModule.CreateSkeletalAnimation(entity, skeletonRef, animClipRef, playing: true, loop: true);
				skeletonRef.Dispose();
				animClipRef.Dispose();
			}

			Console.WriteLine($"    SkeletonRef: id={skeletonId}, path={skeletonPath}");
			Console.WriteLine($"    AnimClipRef: id={firstAnim.Id}, path={firstAnim.Path}");
			Console.WriteLine($"    Available animations: {animationRefs.Count}");
		}

		Console.WriteLine($"  Created '{name}' (skinned) entity with ResourceRefs:");
		Console.WriteLine($"    MeshRef: id={skinnedMeshId}, path={skinnedMeshPath}");
		if (materialRefs != null)
		{
			for (int32 i = 0; i < materialRefs.Count && i < RenderConfig.MaxMaterialsPerMesh; i++)
				Console.WriteLine($"    MaterialRefs[{i}]: id={materialRefs[i].Id}, path={materialRefs[i].Path}");
		}
	}

	private void CreateStaticEntity(Scene scene, StringView name, Vector3 position,
		String staticMeshPath, Guid staticMeshId,
		List<ResourceRef> materialRefs)
	{
		if (staticMeshPath == null)
		{
			Console.WriteLine($"  WARNING: No cached static mesh for '{name}', skipping");
			return;
		}

		let entity = scene.CreateEntity();
		scene.SetName(entity, name);
		scene.SetTransform(entity, .(position));

		if (let renderModule = scene.GetModule<RenderSceneModule>())
		{
			var meshRef = ResourceRef(staticMeshId, staticMeshPath);
			renderModule.CreateMeshFromRef(entity, meshRef, true);
			meshRef.Dispose();

			if (materialRefs != null && materialRefs.Count > 0)
			{
				let count = Math.Min((int32)materialRefs.Count, (int32)RenderConfig.MaxMaterialsPerMesh);
				for (int32 i = 0; i < count; i++)
					renderModule.SetMeshMaterialRef(entity, i, materialRefs[i]);
			}
		}

		Console.WriteLine($"  Created '{name}' (static) entity with ResourceRefs:");
		Console.WriteLine($"    MeshRef: id={staticMeshId}, path={staticMeshPath}");
		if (materialRefs != null)
		{
			for (int32 i = 0; i < materialRefs.Count && i < RenderConfig.MaxMaterialsPerMesh; i++)
				Console.WriteLine($"    MaterialRefs[{i}]: id={materialRefs[i].Id}, path={materialRefs[i].Path}");
		}
	}

	// ==================== Sprite ====================

	/// Creates a checkerboard texture procedurally and adds it to the resource system.
	private void CreateCheckerboardTexture()
	{
		uint32 size = 64;
		uint32 tileSize = 8;
		let image = new Image(size, size, .RGBA8);

		for (uint32 y = 0; y < size; y++)
		{
			for (uint32 x = 0; x < size; x++)
			{
				let isWhite = ((x / tileSize) + (y / tileSize)) % 2 == 0;
				image.SetPixel(x, y, isWhite ? Color(255, 255, 255, 255) : Color(80, 80, 80, 255));
			}
		}

		let texResource = new TextureResource(image, true);
		texResource.SetupForSprite();

		if (mContext.Resources.AddResource<TextureResource>(texResource) case .Ok(let handle))
		{
			mCheckerboardTexture = handle;
			Console.WriteLine("  Created checkerboard texture (64x64, 8px tiles)");
		}
	}

	private void CreateSpriteEntity(Scene scene)
	{
		let entity = scene.CreateEntity();
		scene.SetName(entity, "Sprite");
		scene.SetTransform(entity, .(.(0, 3, 0)));

		if (let renderModule = scene.GetModule<RenderSceneModule>())
		{
			renderModule.CreateSprite(entity);
			renderModule.SetSpriteSize(entity, .(2, 2));
		}

		Console.WriteLine("  Created Sprite entity at (0, 3, 0)");
	}

	/// Assigns the procedural checkerboard texture to the sprite entity.
	/// Runs after scene load/create since the texture handle is runtime-only (not serialized).
	private void SetupSpriteTexture()
	{
		if (mMainScene == null || !mCheckerboardTexture.IsValid)
			return;

		let entity = mMainScene.FindByName("Sprite");
		if (!mMainScene.IsValid(entity))
			return;

		if (let renderModule = mMainScene.GetModule<RenderSceneModule>())
			renderModule.SetSpriteTextureResource(entity, mCheckerboardTexture);
	}

	// ==================== Particles ====================

	private void CreateFireEmitter(Scene scene)
	{
		let entity = scene.CreateEntity();
		scene.SetName(entity, "Fire");
		scene.SetTransform(entity, .(.(-10, 0, 0)));

		if (let renderModule = scene.GetModule<RenderSceneModule>())
		{
			renderModule.CreateCPUParticleEmitter(entity, 500);
			if (let proxy = renderModule.GetParticleEmitterProxy(entity))
			{
				proxy.BlendMode = .Additive;
				proxy.SpawnRate = 60.0f;
				proxy.ParticleLifetime = 1.0f;
				proxy.StartSize = .(0.3f, 0.3f);
				proxy.EndSize = .(0.05f, 0.05f);
				proxy.StartColor = .(1.0f, 0.6f, 0.1f, 1.0f);  // Orange
				proxy.EndColor = .(1.0f, 0.1f, 0.0f, 0.0f);     // Red, fade out
				proxy.InitialVelocity = .(0, 2.0f, 0);
				proxy.VelocityRandomness = .(0.4f, 0.3f, 0.4f);
				proxy.GravityMultiplier = -0.3f;  // Slight upward push
				proxy.Drag = 1.0f;
				proxy.SortParticles = false;
			}
		}

		Console.WriteLine("  Created Fire particle emitter at (-10, 0, 0)");
	}

	private void CreateSmokeEmitter(Scene scene)
	{
		let entity = scene.CreateEntity();
		scene.SetName(entity, "Smoke");
		scene.SetTransform(entity, .(.(-10, 1.0f, 0)));

		if (let renderModule = scene.GetModule<RenderSceneModule>())
		{
			renderModule.CreateCPUParticleEmitter(entity, 300);
			if (let proxy = renderModule.GetParticleEmitterProxy(entity))
			{
				proxy.BlendMode = .Alpha;
				proxy.SpawnRate = 15.0f;
				proxy.ParticleLifetime = 3.0f;
				proxy.StartSize = .(0.2f, 0.2f);
				proxy.EndSize = .(1.0f, 1.0f);
				proxy.StartColor = .(0.4f, 0.4f, 0.4f, 0.6f);  // Gray, semi-transparent
				proxy.EndColor = .(0.3f, 0.3f, 0.3f, 0.0f);     // Fade out
				proxy.InitialVelocity = .(0, 0.8f, 0);
				proxy.VelocityRandomness = .(0.3f, 0.2f, 0.3f);
				proxy.GravityMultiplier = -0.1f;  // Slight upward drift
				proxy.Drag = 0.5f;
				proxy.SortParticles = true;
			}
		}

		Console.WriteLine("  Created Smoke particle emitter at (-10, 1, 0)");
	}

	// ==================== Animation Cycling ====================

	/// Loads all animation clips and finds the GLTF entity for runtime animation cycling.
	private void SetupAnimationCycling()
	{
		if (mMainScene == null || mGltfAnimationRefs.Count == 0)
			return;

		// Find the GLTF skinned entity
		mGltfEntity = mMainScene.FindByName("GreenBlob_GLTF");
		if (!mMainScene.IsValid(mGltfEntity))
			return;

		// Load all animation clips via ResourceSystem
		for (let animRef in mGltfAnimationRefs)
		{
			if (mContext.Resources.LoadByRef<AnimationClipResource>(animRef) case .Ok(let handle))
				mLoadedAnimClips.Add(handle);
		}

		if (mLoadedAnimClips.Count > 0)
		{
			Console.WriteLine($"\nAnimation cycling ready (press T to cycle):");
			for (int i = 0; i < mLoadedAnimClips.Count; i++)
			{
				let name = mLoadedAnimClips[i].Resource?.Clip?.Name ?? "?";
				Console.WriteLine($"  [{i}] {name}{(i == 0 ? " (active)" : "")}");
			}
		}
	}

	/// Cycles to the next animation clip on the fox entity.
	private void CycleAnimation()
	{
		if (mMainScene == null || mLoadedAnimClips.Count <= 1)
			return;

		if (!mMainScene.IsValid(mGltfEntity))
			return;

		if (let animModule = mMainScene.GetModule<AnimationSceneModule>())
		{
			mCurrentAnimIndex = (mCurrentAnimIndex + 1) % mLoadedAnimClips.Count;
			let clipResource = mLoadedAnimClips[mCurrentAnimIndex].Resource;
			if (clipResource?.Clip != null)
			{
				animModule.Play(mGltfEntity, clipResource.Clip, true);
				Console.WriteLine($"Animation: [{mCurrentAnimIndex}] {clipResource.Clip.Name}");
			}
		}
	}

	// ==================== Printing ====================

	private void PrintComponentData(Scene scene)
	{
		for (let (entity, comp) in scene.Query<TestComponent>())
		{
			let name = scene.GetName(entity);
			Console.WriteLine($"  {name}: Speed={comp.Speed}, Health={comp.Health}, Active={comp.Active}");
		}
		if (let renderModule = scene.GetModule<RenderSceneModule>())
		{
			for (let (entity, comp) in scene.Query<LightComponent>())
			{
				let name = scene.GetName(entity);
				if (let proxy = renderModule.GetLightProxy(entity))
					Console.WriteLine($"  {name}: Light(Type={proxy.Type}, Color=({proxy.Color.X:.2},{proxy.Color.Y:.2},{proxy.Color.Z:.2}), Intensity={proxy.Intensity}, Range={proxy.Range}, Enabled={proxy.IsEnabled})");
				else
					Console.WriteLine($"  {name}: Light(Handle={comp.InternalHandle}, no proxy)");
			}
			for (let (entity, comp) in scene.Query<CameraComponent>())
			{
				let name = scene.GetName(entity);
				if (let proxy = renderModule.GetCameraProxy(entity))
					Console.WriteLine($"  {name}: Camera(Projection={proxy.Projection}, FOV={proxy.FieldOfView:.2}, Near={proxy.NearPlane}, Far={proxy.FarPlane}, Active={proxy.IsActive}, IsMain={proxy.IsMainCamera})");
				else
					Console.WriteLine($"  {name}: Camera(Handle={comp.InternalHandle}, no proxy)");
			}
		}
		if (let renderModule = scene.GetModule<RenderSceneModule>())
		{
			for (var instance in ref renderModule.SkinnedMeshInstances)
			{
				if (!instance.Active) continue;
				let name = scene.GetName(instance.Entity);
				let meshValid = instance.MeshRef.IsValid;
				let matValid = instance.MaterialRefs[0].IsValid;
				Console.WriteLine($"  {name}: SkinnedMesh(MeshRef.valid={meshValid}, MaterialRefs[0].valid={matValid}, Enabled={instance.Enabled}, MaterialCount={instance.MaterialRefs.Count})");
			}
		}
		for (let (entity, comp) in scene.Query<MeshComponent>())
		{
			let name = scene.GetName(entity);
			if (let renderModule = scene.GetModule<RenderSceneModule>())
			{
				let resource = renderModule.GetMeshResource(entity);
				Console.WriteLine($"  {name}: Mesh(Handle={comp.InternalHandle}, HasResource={resource != null}, IsValid={comp.IsValid})");
			}
		}
		if (let animModule = scene.GetModule<AnimationSceneModule>())
		{
			for (var instance in ref animModule.SkeletalAnimInstances)
			{
				if (!instance.Active) continue;
				let name = scene.GetName(instance.Entity);
				Console.WriteLine($"  {name}: Animation(SkeletonRef.valid={instance.SkeletonRef.IsValid}, AnimClipRef.valid={instance.AnimationClipRef.IsValid}, Playing={instance.Playing}, Loop={instance.Loop})");
			}
		}
	}

	// ==================== Input & Render ====================

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		if (keyboard.IsKeyPressed(.T))
			CycleAnimation();

		mCamera.HandleInput(keyboard, mouse, mDeltaTime);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		// Begin frame
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		// Deferred sky setup — must happen after first BeginFrame flushes the init transfer batch
		if (mNeedsSkySetup && mSkyFeature != null)
		{
			mNeedsSkySetup = false;
			let topColor = Color(70, 130, 200, 255);
			let horizonColor = Color(180, 210, 240, 255);
			mSkyFeature.CreateGradientSky(topColor, horizonColor, 32);
		}

		// Set swapchain for final output
		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		// Set the active world from the scene's render module
		if (let renderModule = mMainScene?.GetModule<RenderSceneModule>())
		{
			if (let world = renderModule.World)
				mRenderSystem.SetActiveWorld(world);
		}

		// Update camera and render view
		mCamera.Update();
		mRenderView.CameraPosition = mCamera.Position;
		mRenderView.CameraForward = mCamera.Forward;
		mRenderView.CameraUp = .(0, 1, 0);
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.UpdateMatrices();

		// Set camera for rendering
		mRenderSystem.SetCamera(
			mRenderView.CameraPosition,
			mRenderView.CameraForward,
			.(0, 1, 0),
			mRenderView.FieldOfView,
			mRenderView.AspectRatio,
			mRenderView.NearPlane,
			mRenderView.FarPlane,
			mRenderView.Width,
			mRenderView.Height
		);

		// Build and execute render graph
		if (mRenderSystem.BuildRenderGraph(mRenderView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		// End frame
		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnResize(int32 width, int32 height)
	{
		mRenderSystem?.SetViewportSize((uint32)width, (uint32)height);
	}

	protected override void OnShutdown()
	{
		Profiler.Shutdown();

		// Remove registry before resource system shuts down
		mContext.Resources.RemoveRegistry(mRegistry);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		delete mRenderSystem; mRenderSystem = null;
		delete mRenderView;
	}
}
