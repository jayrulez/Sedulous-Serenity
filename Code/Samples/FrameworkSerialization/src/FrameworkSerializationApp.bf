namespace FrameworkSerialization;

using System;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Animation;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Profiler;
using Sedulous.Resources;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Geometry.Tooling;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Imaging;
using Sedulous.Materials.Resources;
using Sedulous.Textures.Resources;
using Sedulous.Animation.Resources;

class FrameworkSerializationApp : Application
{
	private const StringView GLTF_REL_PATH = "samples/models/Fox/glTF/Fox.gltf";
	private const StringView GLTF_BASE_REL_PATH = "samples/models/Fox/glTF";
	private const StringView CACHE_REL_PATH = "cache";

	// Framework
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private Scene mMainScene;

	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderView mRenderView ~ delete _;

	// Render features
	private GPUSkinningFeature mSkinningFeature;
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private ForwardTransparentFeature mTransparentFeature;
	private ParticleFeature mParticleFeature;
	private SpriteFeature mSpriteFeature;
	private SkyFeature mSkyFeature;
	private DebugRenderFeature mDebugFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Camera
	private OrbitFlyCamera mCamera ~ delete _;
	private float mDeltaTime = 0.016f;

	// Scene resource
	private SceneResource mSceneResource ~ delete _;

	// Asset registry
	private ResourceRegistry mRegistry = new .() ~ delete _;

	// Cached resource info (populated during import, used to create fox entities)
	private String mCachedSkinnedMeshPath ~ delete _;
	private String mCachedStaticMeshPath ~ delete _;
	private String mCachedMaterialPath ~ delete _;
	private String mCachedSkeletonPath ~ delete _;
	private String mCachedAnimationPath ~ delete _;
	private Guid mCachedSkinnedMeshId;
	private Guid mCachedStaticMeshId;
	private Guid mCachedMaterialId;
	private Guid mCachedSkeletonId;
	private Guid mCachedAnimationId;

	public this(IShell shell, IDevice device, IBackend backend) : base(shell, device, backend)
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
		Console.WriteLine("=== Framework Serialization Sample ===\n");

		InitializeRenderSystem();
		RegisterSubsystems(context);
	}

	protected override void OnContextStarted()
	{
		SProfiler.Initialize();

		// Import and cache assets, then create/load scene
		ImportAndCacheAssets();
		LoadOrCreateScene();
	}

	private void InitializeRenderSystem()
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope $"{AssetDirectory}/Render/Shaders", .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
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

		// Register render features (matching FrameworkSandbox)
		RegisterRenderFeatures();
	}

	private void RegisterRenderFeatures()
	{
		// GPU skinning (must be before depth prepass and forward passes)
		mSkinningFeature = new GPUSkinningFeature();
		mRenderSystem.RegisterFeature(mSkinningFeature);

		// Depth prepass
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		// Forward opaque
		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		// Forward transparent
		mTransparentFeature = new ForwardTransparentFeature();
		mRenderSystem.RegisterFeature(mTransparentFeature);

		// Particles
		mParticleFeature = new ParticleFeature();
		mRenderSystem.RegisterFeature(mParticleFeature);

		// Sprites
		mSpriteFeature = new SpriteFeature();
		mRenderSystem.RegisterFeature(mSpriteFeature);

		// Sky (gradient environment map)
		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Ok)
		{
			let topColor = Color(70, 130, 200, 255);
			let horizonColor = Color(180, 210, 240, 255);
			mSkyFeature.CreateGradientSky(topColor, horizonColor, 32);
		}

		// Debug render
		mDebugFeature = new DebugRenderFeature();
		mRenderSystem.RegisterFeature(mDebugFeature);

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
				// Recover cached paths for fox entity creation (in case scene file was deleted)
				RecoverCachedPaths(cacheDir);
			}
			else
				Console.WriteLine("WARNING: Failed to load registry, will re-import");
		}

		if (mRegistry.Count == 0)
		{
			// No cache - import from GLTF and save
			ImportFoxModel(cacheDir, registryPath);
		}

		// Register the registry with the resource system
		mContext.Resources.AddRegistry(mRegistry);
		Console.WriteLine($"Registry registered with ResourceSystem ({mRegistry.Count} entries)");

		// Print registry contents
		PrintRegistryEntries();
		Console.WriteLine();
	}

	private void ImportFoxModel(StringView cacheDir, StringView registryPath)
	{
		String gltfPath = scope .();
		GetAssetPath(GLTF_REL_PATH, gltfPath);

		String basePath = scope .();
		GetAssetPath(GLTF_BASE_REL_PATH, basePath);

		Console.WriteLine($"Importing Fox model from: {gltfPath}");

		// Load GLTF
		let model = new Model();
		let loader = scope GltfLoader();
		if (loader.Load(gltfPath, model) != .Ok)
		{
			Console.WriteLine("ERROR: Failed to load Fox GLTF");
			delete model;
			return;
		}
		defer delete model;

		// Import all resource types (order: Skeletons→Textures→Materials→SkinnedMeshes→Animations)
		let importOptions = new ModelImportOptions();
		importOptions.BasePath.Set(basePath);
		importOptions.Flags = .Skeletons | .Meshes | .SkinnedMeshes | .Animations | .Materials | .Textures;

		let imageLoader = scope SDLImageLoader();
		let importer = scope ModelImporter(importOptions, imageLoader);
		let result = importer.Import(model);
		defer delete result;

		Console.WriteLine($"  Imported: {result.TotalResourceCount} resources");
		Console.WriteLine($"    Skeletons: {result.Skeletons.Count}");
		Console.WriteLine($"    Textures: {result.Textures.Count}");
		Console.WriteLine($"    NewMaterials: {result.NewMaterials.Count}");
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

		// Save all resources to cache directory
		Console.WriteLine($"\nSaving resources to: {cacheDir}");
		if (ResourceSerializer.SaveImportResult(result, cacheDir) case .Ok)
			Console.WriteLine("  Resources saved successfully");
		else
		{
			Console.WriteLine("  ERROR: Failed to save resources");
			return;
		}

		// Build registry from import result
		BuildRegistryFromResult(result, cacheDir);

		// Save registry
		if (mRegistry.SaveToFile(registryPath) case .Ok)
			Console.WriteLine($"  Registry saved: {mRegistry.Count} entries");
		else
			Console.WriteLine("  WARNING: Failed to save registry file");
	}

	private void BuildRegistryFromResult(ModelImportResult result, StringView cacheDir)
	{
		for (let skeleton in result.Skeletons)
		{
			RegisterResource(skeleton, cacheDir, "skeleton");
			// Capture first skeleton for fox entity creation
			if (mCachedSkeletonPath == null)
			{
				mCachedSkeletonPath = new String();
				mCachedSkeletonPath.AppendF("{}/{}.skeleton", cacheDir, skeleton.Name);
				mCachedSkeletonId = skeleton.Id;
			}
		}

		for (let texture in result.Textures)
			RegisterResource(texture, cacheDir, "texture");

		for (let material in result.NewMaterials)
		{
			RegisterResource(material, cacheDir, "mat");
			// Capture first material for fox entity creation
			if (mCachedMaterialPath == null)
			{
				mCachedMaterialPath = new String();
				mCachedMaterialPath.AppendF("{}/{}.mat", cacheDir, material.Name);
				mCachedMaterialId = material.Id;
			}
		}

		for (let mesh in result.SkinnedMeshes)
		{
			RegisterResource(mesh, cacheDir, "skinnedmesh");
			// Capture first skinned mesh for fox entity creation
			if (mCachedSkinnedMeshPath == null)
			{
				mCachedSkinnedMeshPath = new String();
				mCachedSkinnedMeshPath.AppendF("{}/{}.skinnedmesh", cacheDir, mesh.Name);
				mCachedSkinnedMeshId = mesh.Id;
			}
		}

		for (let mesh in result.StaticMeshes)
		{
			RegisterResource(mesh, cacheDir, "mesh");
			// Capture first static mesh for fox entity creation
			if (mCachedStaticMeshPath == null)
			{
				mCachedStaticMeshPath = new String();
				mCachedStaticMeshPath.AppendF("{}/{}.mesh", cacheDir, mesh.Name);
				mCachedStaticMeshId = mesh.Id;
			}
		}

		for (let animation in result.Animations)
		{
			RegisterResource(animation, cacheDir, "animation");
			// Capture first animation for fox entity creation
			if (mCachedAnimationPath == null)
			{
				mCachedAnimationPath = new String();
				mCachedAnimationPath.AppendF("{}/{}.animation", cacheDir, animation.Name);
				mCachedAnimationId = animation.Id;
			}
		}
	}

	private void RegisterResource(IResource resource, StringView cacheDir, StringView @extension)
	{
		let path = scope String();
		path.AppendF("{}/{}.{}", cacheDir, resource.Name, @extension);
		mRegistry.Register(resource.Id, path);
	}

	/// Recovers cached resource paths by scanning the cache directory.
	/// Used when the registry was loaded from file (so we didn't import).
	private void RecoverCachedPaths(StringView cacheDir)
	{
		if (mCachedSkinnedMeshPath != null)
			return; // Already populated

		if (!Directory.Exists(cacheDir))
			return;

		// Scan for first .skinnedmesh, .mesh, .mat, .skeleton, and .animation files
		for (let entry in Directory.EnumerateFiles(cacheDir))
		{
			let filePath = scope String();
			entry.GetFilePath(filePath);
			// Normalize separators to match registry format
			filePath.Replace('\\', '/');

			if (filePath.EndsWith(".skinnedmesh") && mCachedSkinnedMeshPath == null)
			{
				mCachedSkinnedMeshPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out mCachedSkinnedMeshId);
			}
			else if (filePath.EndsWith(".mesh") && mCachedStaticMeshPath == null)
			{
				mCachedStaticMeshPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out mCachedStaticMeshId);
			}
			else if (filePath.EndsWith(".mat") && mCachedMaterialPath == null)
			{
				mCachedMaterialPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out mCachedMaterialId);
			}
			else if (filePath.EndsWith(".skeleton") && mCachedSkeletonPath == null)
			{
				mCachedSkeletonPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out mCachedSkeletonId);
			}
			else if (filePath.EndsWith(".animation") && mCachedAnimationPath == null)
			{
				mCachedAnimationPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out mCachedAnimationId);
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
		String scenePath = scope .();
		GetScenePath(scenePath);

		if (File.Exists(scenePath))
		{
			// Load existing scene resource from file with component types registered
			mSceneResource = new SceneResource();
			RegisterSceneComponentTypes(mSceneResource);
			switch (mSceneResource.Load(scenePath))
			{
			case .Ok:
				Console.WriteLine($"Loaded scene from file: {mSceneResource.Scene.Name} ({mSceneResource.Scene.EntityCount} entities)");
				PrintComponentData(mSceneResource.Scene);

				// Transfer ownership to SceneManager and activate
				mMainScene = mSceneSubsystem.AddScene(mSceneResource.TakeScene());
				mSceneSubsystem.SetActiveScene(mMainScene);

			case .Err:
				Console.WriteLine("ERROR: Failed to load scene from file, creating new one");
				delete mSceneResource;
				mSceneResource = null;
				CreateAndSaveScene();
			}
		}
		else
		{
			CreateAndSaveScene();
		}
	}

	private void GetScenePath(String outPath)
	{
		GetAssetPath(CACHE_REL_PATH, outPath);
		outPath.Append("/scene.oddl");
	}

	private void RegisterSceneComponentTypes(SceneResource resource)
	{
		resource.RegisterComponentType<TestComponent>();
		resource.RegisterComponentType<LightComponent>();
		resource.RegisterComponentType<CameraComponent>();
		resource.RegisterComponentType<SkinnedMeshRendererComponent>();
		resource.RegisterComponentType<MeshRendererComponent>();
		resource.RegisterComponentType<SkeletalAnimationComponent>();
	}

	private void CreateAndSaveScene()
	{
		// Create scene resource with test entities and components
		mSceneResource = SceneResource.CreateEmpty("SerializationTest");
		RegisterSceneComponentTypes(mSceneResource);
		let scene = mSceneResource.Scene;

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

		// Directional light
		let dirLight = scene.CreateEntity();
		scene.SetName(dirLight, "DirectionalLight");
		scene.SetTransform(dirLight, .(.(0, 10, 0), Quaternion.CreateFromAxisAngle(.(1, 0, 0), -0.8f)));
		scene.SetComponent<LightComponent>(dirLight, .() {
			Type = .Directional, Color = .(1.0f, 0.95f, 0.8f), Intensity = 2.0f,
			Enabled = true, ShadowBias = 0.005f, ShadowNormalBias = 0.02f, LayerMask = 0xFFFFFFFF
		});

		// Point light
		let pointLight = scene.CreateEntity();
		scene.SetName(pointLight, "PointLight");
		scene.SetTransform(pointLight, .(.(3, 2, -1)));
		scene.SetComponent<LightComponent>(pointLight, .() {
			Type = .Point, Color = .(1.0f, 0.8f, 0.6f), Intensity = 5.0f, Range = 15.0f,
			Enabled = true, ShadowBias = 0.005f, ShadowNormalBias = 0.02f, LayerMask = 0xFFFFFFFF
		});

		// Fox entities with resource references (serializable)
		CreateFoxEntity(scene);
		CreateStaticFoxEntity(scene);

		// Save to file and register in registry
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

		// Transfer ownership to SceneManager and activate
		mMainScene = mSceneSubsystem.AddScene(mSceneResource.TakeScene());
		mSceneSubsystem.SetActiveScene(mMainScene);
	}

	private void CreateFoxEntity(Scene scene)
	{
		if (mCachedSkinnedMeshPath == null)
		{
			Console.WriteLine("  WARNING: No cached skinned mesh available, skipping fox entity");
			return;
		}

		// Create fox entity with ResourceRef-based component
		// Fox model vertices are in a large coordinate space (~78 units tall), scale down to match scene
		let foxEntity = scene.CreateEntity();
		scene.SetName(foxEntity, "Fox");
		scene.SetTransform(foxEntity, .(.Zero, .Identity, .(0.02f, 0.02f, 0.02f)));

		var foxComp = SkinnedMeshRendererComponent.Default;
		foxComp.MeshRef = ResourceRef(mCachedSkinnedMeshId, mCachedSkinnedMeshPath);
		if (mCachedMaterialPath != null)
			foxComp.MaterialRef = ResourceRef(mCachedMaterialId, mCachedMaterialPath);
		foxComp.Enabled = true;
		scene.SetComponent<SkinnedMeshRendererComponent>(foxEntity, foxComp);

		// Add skeletal animation component with resource refs
		if (mCachedSkeletonPath != null && mCachedAnimationPath != null)
		{
			var animComp = SkeletalAnimationComponent.Default;
			animComp.SkeletonRef = ResourceRef(mCachedSkeletonId, mCachedSkeletonPath);
			animComp.AnimationClipRef = ResourceRef(mCachedAnimationId, mCachedAnimationPath);
			animComp.Playing = true;
			animComp.Loop = true;
			scene.SetComponent<SkeletalAnimationComponent>(foxEntity, animComp);

			Console.WriteLine($"    SkeletonRef: id={mCachedSkeletonId}, path={mCachedSkeletonPath}");
			Console.WriteLine($"    AnimClipRef: id={mCachedAnimationId}, path={mCachedAnimationPath}");
		}

		Console.WriteLine("  Created Fox (skinned) entity with ResourceRefs:");
		Console.WriteLine($"    MeshRef: id={mCachedSkinnedMeshId}, path={mCachedSkinnedMeshPath}");
		if (mCachedMaterialPath != null)
			Console.WriteLine($"    MaterialRef: id={mCachedMaterialId}, path={mCachedMaterialPath}");
	}

	private void CreateStaticFoxEntity(Scene scene)
	{
		if (mCachedStaticMeshPath == null)
		{
			Console.WriteLine("  WARNING: No cached static mesh available, skipping static fox entity");
			return;
		}

		// Create a second fox entity using static mesh (offset to the side)
		let foxEntity = scene.CreateEntity();
		scene.SetName(foxEntity, "FoxStatic");
		scene.SetTransform(foxEntity, .(.(3, 0, 0), .Identity, .(0.02f, 0.02f, 0.02f)));

		var meshComp = MeshRendererComponent.Default;
		meshComp.MeshRef = ResourceRef(mCachedStaticMeshId, mCachedStaticMeshPath);
		if (mCachedMaterialPath != null)
			meshComp.MaterialRef = ResourceRef(mCachedMaterialId, mCachedMaterialPath);
		meshComp.Enabled = true;
		scene.SetComponent<MeshRendererComponent>(foxEntity, meshComp);

		Console.WriteLine("  Created FoxStatic entity with ResourceRefs:");
		Console.WriteLine($"    MeshRef: id={mCachedStaticMeshId}, path={mCachedStaticMeshPath}");
		if (mCachedMaterialPath != null)
			Console.WriteLine($"    MaterialRef: id={mCachedMaterialId}, path={mCachedMaterialPath}");
	}

	// ==================== Printing ====================

	private void PrintComponentData(Scene scene)
	{
		for (let (entity, comp) in scene.Query<TestComponent>())
		{
			let name = scene.GetName(entity);
			Console.WriteLine($"  {name}: Speed={comp.Speed}, Health={comp.Health}, Active={comp.Active}");
		}
		for (let (entity, comp) in scene.Query<LightComponent>())
		{
			let name = scene.GetName(entity);
			Console.WriteLine($"  {name}: Light(Type={comp.Type}, Color=({comp.Color.X:.2},{comp.Color.Y:.2},{comp.Color.Z:.2}), Intensity={comp.Intensity}, Range={comp.Range}, Enabled={comp.Enabled})");
		}
		for (let (entity, comp) in scene.Query<CameraComponent>())
		{
			let name = scene.GetName(entity);
			Console.WriteLine($"  {name}: Camera(Projection={comp.Projection}, FOV={comp.FieldOfView:.2}, Near={comp.NearPlane}, Far={comp.FarPlane}, Active={comp.Active}, IsMain={comp.IsMainCamera})");
		}
		for (let (entity, comp) in scene.Query<SkinnedMeshRendererComponent>())
		{
			let name = scene.GetName(entity);
			let meshValid = comp.MeshRef.IsValid;
			let matValid = comp.MaterialRef.IsValid;
			Console.WriteLine($"  {name}: SkinnedMesh(MeshRef.valid={meshValid}, MaterialRef.valid={matValid}, Enabled={comp.Enabled})");
		}
		for (let (entity, comp) in scene.Query<MeshRendererComponent>())
		{
			let name = scene.GetName(entity);
			let meshValid = comp.MeshRef.IsValid;
			let matValid = comp.MaterialRef.IsValid;
			Console.WriteLine($"  {name}: Mesh(MeshRef.valid={meshValid}, MaterialRef.valid={matValid}, Enabled={comp.Enabled})");
		}
		for (let (entity, comp) in scene.Query<SkeletalAnimationComponent>())
		{
			let name = scene.GetName(entity);
			let skelValid = comp.SkeletonRef.IsValid;
			let clipValid = comp.AnimationClipRef.IsValid;
			Console.WriteLine($"  {name}: Animation(SkeletonRef.valid={skelValid}, AnimClipRef.valid={clipValid}, Playing={comp.Playing}, Loop={comp.Loop})");
		}
	}

	// ==================== Input & Render ====================

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

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
		mRenderView.UpdateMatrices(mDevice.FlipProjectionRequired);

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

	protected override void OnShutdown()
	{
		Profiler.Shutdown();

		// Remove registry before resource system shuts down
		mContext.Resources.RemoveRegistry(mRegistry);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();
	}
}
