namespace FrameworkAnimation;

using System;
using System.IO;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Animation;
using Sedulous.Framework.Input;
using Sedulous.Framework.UI;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Geometry.Tooling;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Resources;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Textures.Resources;
using Sedulous.Imaging;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Profiler;
using Sedulous.Drawing.Fonts;
using Sedulous.Fonts;
using Sedulous.GUI;

class FrameworkAnimationApp : Application
{
	private const StringView MODEL_PATH = "samples/models/kenney_platformer-kit/Models/GLB format/character-oobi.glb";
	private const StringView CACHE_REL_PATH = "cache/anim_sample";

	// Framework
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private UISubsystem mUISubsystem;
	private AnimationSubsystem mAnimSubsystem;
	private Scene mMainScene;

	private FontService mFontService;

	// Render system
	private RenderSystem mRenderSystem;
	private RenderView mRenderView;

	// Render features
	private GPUSkinningFeature mSkinningFeature;
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private OverlayRenderFeature mOverlayFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Camera
	private OrbitFlyCamera mCamera;
	private float mDeltaTime = 0.016f;

	// Asset registry
	private ResourceRegistry mRegistry = new .();

	// Imported asset info
	private String mSkinnedMeshPath;
	private String mSkeletonPath;
	private Guid mSkinnedMeshId;
	private Guid mSkeletonId;
	private List<ResourceRef> mMaterialRefs = new .();
	private List<ResourceRef> mAnimationRefs = new .();

	// Ground
	private StaticMeshResource mPlaneResource;
	private MaterialInstance mFloorMaterial;

	// Entities
	private EntityId mCameraEntity;
	private EntityId mSunEntity;

	// Entity 1: State machine demo (center)
	private EntityId mStateMachineEntity;
	private AnimationGraph mStateMachineGraph;
	private AnimationGraphPlayer mStateMachinePlayer;

	// Entity 2: Blend tree demo (left)
	private EntityId mBlendTreeEntity;
	private AnimationGraph mBlendTreeGraph;
	private AnimationGraphPlayer mBlendTreePlayer;

	// Entity 3: Multi-layer demo (right)
	private EntityId mMultiLayerEntity;
	private AnimationGraph mMultiLayerGraph;
	private AnimationGraphPlayer mMultiLayerPlayer;

	// Loaded animation clips (by name)
	private Dictionary<String, AnimationClip> mClipsByName = new .();
	private List<ResourceHandle<AnimationClipResource>> mClipHandles = new .();

	// Skeleton loaded from resource
	private ResourceHandle<SkeletonResource> mSkeletonHandle;
	private Skeleton mSkeleton;

	// UI elements
	private Canvas mUIRoot;
	private TextBlock mStateMachineLabel;
	private TextBlock mBlendTreeLabel;
	private TextBlock mMultiLayerLabel;

	// Property animation demo
	private PropertyAnimationClipResource mSunAnimResource;
	private PropertyAnimationClip mSunAnimClip;

	// Cube property animation demo
	private EntityId mCubeEntity;
	private StaticMeshResource mCubeResource;
	private MaterialInstance mCubeMaterial;
	private PropertyAnimationClipResource mCubeAnimResource;
	private PropertyAnimationClip mCubeAnimClip;

	// UI-driven parameter values
	private float mStateMachineSpeed = 0.0f;
	private bool mStateMachineGrounded = true;
	private float mBlendTreeSpeed = 0.0f;
	private float mMultiLayerSpeed = 0.0f;
	private float mMultiLayerUpperWeight = 0.8f;

	public this(IShell shell, IDevice device, IBackend backend) : base(shell, device, backend)
	{
		mCamera = new .();
		mCamera.CurrentMode = .Flythrough;
		mCamera.OrbitalYaw = 0.0f;
		mCamera.OrbitalPitch = 0.4f;
		mCamera.OrbitalDistance = 8.0f;
		mCamera.OrbitalTarget = .(0, 0.5f, 0);
		mCamera.FlyPosition = .(0, 2.0f, 6.0f);
		mCamera.FlyPitch = -0.2f;
		mCamera.Update();
	}

	protected override void OnInitialize(Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		Console.WriteLine("=== Animation Graph Demo ===\n");

		InitializeRenderSystem();
		RegisterSubsystems(context);
	}

	protected override void OnContextStarted()
	{
		SProfiler.Initialize();

		ImportAndCacheAssets();
		LoadAnimationClips();
		CreateMainScene();
		CreateSceneObjects();
		BuildAnimationGraphs();
		SetupPropertyAnimationDemo();
		CreateUI();

		Console.WriteLine("\n=== Animation Graph Demo Ready ===");
		Console.WriteLine("Three characters demonstrating different animation graph features:");
		Console.WriteLine("  Left:   1D Blend Tree — smooth blend between Idle and Walk via slider");
		Console.WriteLine("  Center: State Machine — 6 states with conditional transitions and triggers");
		Console.WriteLine("  Right:  Multi-Layer — base locomotion + upper body overlay with bone mask");
		Console.WriteLine("");
		Console.WriteLine("UI panel at the bottom controls each character.");
		Console.WriteLine("  State Machine: Speed slider, Grounded checkbox, Die/Emote Yes/Melee Right buttons");
		Console.WriteLine("  Blend Tree:    Speed slider (0=Idle, 1=Walk)");
		Console.WriteLine("  Multi-Layer:   Speed slider, Emote Yes/Emote No buttons, upper body weight slider");
		Console.WriteLine("");
		Console.WriteLine("Camera: Tab/` to toggle Orbit/Fly mode | ESC to exit");
	}

	// ==================== Render System ====================

	private void InitializeRenderSystem()
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
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

	// ==================== Subsystems ====================

	private void RegisterSubsystems(Context context)
	{
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);

		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);

		mAnimSubsystem = new AnimationSubsystem();
		context.RegisterSubsystem(mAnimSubsystem);

		let inputSubsystem = new InputSubsystem();
		inputSubsystem.SetInputManager(mShell.InputManager);
		context.RegisterSubsystem(inputSubsystem);

		mFontService = new FontService();
		let fontPath = scope String();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);
		int32[4] fontSizes = .(12, 14, 16, 18);
		for (let size in fontSizes)
		{
			FontLoadOptions options = .ExtendedLatin;
			options.PixelHeight = size;
			mFontService.LoadFont("Roboto", fontPath, options);
		}

		mUISubsystem = new UISubsystem(mFontService);
		context.RegisterSubsystem(mUISubsystem);
		if (mUISubsystem.InitializeRendering(mDevice, .BGRA8UnormSrgb, 2, mShell, mWindow, mRenderSystem) not case .Ok)
		{
			Console.WriteLine("  - UISubsystem (render init failed)");
		}
	}

	// ==================== Asset Import ====================

	private void ImportAndCacheAssets()
	{
		let cacheDir = scope String();
		GetAssetPath(CACHE_REL_PATH, cacheDir);

		let registryPath = scope String();
		registryPath.AppendF("{}/registry.txt", cacheDir);

		if (File.Exists(registryPath))
		{
			if (mRegistry.LoadFromFile(registryPath) case .Ok)
			{
				Console.WriteLine($"Loaded registry from cache: {mRegistry.Count} entries");
				RecoverCachedPaths(cacheDir);
				mContext.Resources.AddRegistry(mRegistry);
				return;
			}
		}

		Console.WriteLine("Importing character-oobi...");
		GltfModels.Initialize();

		let modelPath = scope String();
		GetAssetPath(MODEL_PATH, modelPath);

		let modelBaseDir = scope String();
		modelBaseDir.Set(modelPath);
		let lastSlash = modelBaseDir.LastIndexOf('/');
		if (lastSlash >= 0)
			modelBaseDir.RemoveToEnd(lastSlash);

		let model = new Model();
		if (ModelLoaderFactory.LoadModel(modelPath, model) != .Ok)
		{
			Console.WriteLine("ERROR: Failed to load model");
			delete model;
			return;
		}
		defer delete model;

		let options = new ModelImportOptions();
		options.BasePath.Set(modelBaseDir);
		options.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Materials | .Textures;
		options.RecenterMeshes = false;

		let importer = scope ModelImporter(options);
		let result = importer.Import(model);
		defer delete result;

		let modelCacheDir = scope String();
		modelCacheDir.AppendF("{}/character_oobi", cacheDir);
		Directory.CreateDirectory(cacheDir);
		Directory.CreateDirectory(modelCacheDir);

		if (ResourceSerializer.SaveImportResult(result, modelCacheDir) case .Err)
		{
			Console.WriteLine("ERROR: Failed to cache import");
			return;
		}

		// Register resources
		for (let texture in result.Textures)
			RegisterResource(texture, modelCacheDir, "texture");

		for (let material in result.Materials)
		{
			RegisterResource(material, modelCacheDir, "material");
			let matPath = scope String();
			matPath.AppendF("{}/{}.material", modelCacheDir, material.Name);
			ResourceSerializer.SanitizePath(matPath);
			mMaterialRefs.Add(ResourceRef(material.Id, matPath));
		}

		for (let skeleton in result.Skeletons)
		{
			RegisterResource(skeleton, modelCacheDir, "skeleton");
			if (mSkeletonPath == null)
			{
				mSkeletonPath = new String();
				mSkeletonPath.AppendF("{}/{}.skeleton", modelCacheDir, skeleton.Name);
				ResourceSerializer.SanitizePath(mSkeletonPath);
				mSkeletonId = skeleton.Id;
			}
		}

		for (let animation in result.Animations)
		{
			RegisterResource(animation, modelCacheDir, "animation");
			let animPath = scope String();
			animPath.AppendF("{}/{}.animation", modelCacheDir, animation.Name);
			ResourceSerializer.SanitizePath(animPath);
			mAnimationRefs.Add(ResourceRef(animation.Id, animPath));
		}

		for (let mesh in result.SkinnedMeshes)
		{
			RegisterResource(mesh, modelCacheDir, "skinnedmesh");
			if (mSkinnedMeshPath == null)
			{
				mSkinnedMeshPath = new String();
				mSkinnedMeshPath.AppendF("{}/{}.skinnedmesh", modelCacheDir, mesh.Name);
				ResourceSerializer.SanitizePath(mSkinnedMeshPath);
				mSkinnedMeshId = mesh.Id;
			}
		}

		// Save registry
		if (mRegistry.SaveToFile(registryPath) case .Ok)
			Console.WriteLine($"Registry saved: {mRegistry.Count} entries");

		mContext.Resources.AddRegistry(mRegistry);
		Console.WriteLine($"Import complete: {mAnimationRefs.Count} animations");
	}

	private void RegisterResource(Resource resource, StringView cacheDir, StringView ext)
	{
		let path = scope String();
		path.AppendF("{}/{}.{}", cacheDir, resource.Name, ext);
		ResourceSerializer.SanitizePath(path);
		mRegistry.Register(resource.Id, path);
	}

	private void RecoverCachedPaths(StringView cacheDir)
	{
		let modelDir = scope String();
		modelDir.AppendF("{}/character_oobi", cacheDir);

		if (!Directory.Exists(modelDir))
			return;

		for (let file in Directory.EnumerateFiles(modelDir))
		{
			let filePath = scope String();
			file.GetFilePath(filePath);
			ResourceSerializer.SanitizePath(filePath);

			if (filePath.EndsWith(".skinnedmesh") && mSkinnedMeshPath == null)
			{
				mSkinnedMeshPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out mSkinnedMeshId);
			}
			else if (filePath.EndsWith(".skeleton") && mSkeletonPath == null)
			{
				mSkeletonPath = new String(filePath);
				mRegistry.TryResolveId(filePath, out mSkeletonId);
			}
			else if (filePath.EndsWith(".material"))
			{
				Guid matId = .();
				if (mRegistry.TryResolveId(filePath, out matId))
					mMaterialRefs.Add(ResourceRef(matId, filePath));
			}
			else if (filePath.EndsWith(".animation"))
			{
				Guid animId = .();
				if (mRegistry.TryResolveId(filePath, out animId))
					mAnimationRefs.Add(ResourceRef(animId, filePath));
			}
		}
	}

	// ==================== Load Animation Clips ====================

	private void LoadAnimationClips()
	{
		// Load skeleton
		if (mSkeletonPath != null)
		{
			var skelRef = ResourceRef(mSkeletonId, mSkeletonPath);
			defer skelRef.Dispose();
			if (mContext.Resources.LoadByRef<SkeletonResource>(skelRef) case .Ok(let handle))
			{
				mSkeletonHandle = handle;
				mSkeleton = handle.Resource?.Skeleton;
			}
		}

		// Load all animation clips
		for (let animRef in mAnimationRefs)
		{
			if (mContext.Resources.LoadByRef<AnimationClipResource>(animRef) case .Ok(let handle))
			{
				mClipHandles.Add(handle);
				let clip = handle.Resource?.Clip;
				if (clip != null && clip.Name != null)
				{
					let nameKey = new String(clip.Name);
					mClipsByName[nameKey] = clip;
					Console.WriteLine($"  Loaded animation: {clip.Name} ({clip.Duration}s)");
				}
			}
		}

		Console.WriteLine($"Loaded {mClipsByName.Count} animation clips, skeleton: {mSkeleton?.BoneCount ?? 0} bones");
	}

	/// Gets a clip by name, returns null if not found.
	private AnimationClip GetClip(StringView name)
	{
		let key = scope String(name);
		if (mClipsByName.TryGetValue(key, let clip))
			return clip;
		return null;
	}

	// ==================== Scene ====================

	private void CreateMainScene()
	{
		mMainScene = mSceneSubsystem.CreateScene("AnimScene");
		mSceneSubsystem.SetActiveScene(mMainScene);
	}

	private void CreateSceneObjects()
	{
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		if (renderModule == null) return;

		let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMaterial != null)
		{
			mFloorMaterial = new MaterialInstance(baseMaterial);
			mFloorMaterial.SetColor("BaseColor", .(0.3f, 0.3f, 0.28f, 1.0f));
			mFloorMaterial.SetFloat("Roughness", 0.9f);
		}

		// Floor
		mPlaneResource = StaticMeshResource.CreatePlane(20.0f, 20.0f, 1, 1);
		mPlaneResource.AddRef();
		let floorEntity = mMainScene.CreateEntity();
		{
			mMainScene.SetComponent<MeshRendererComponent>(floorEntity, .Default);
			var comp = mMainScene.GetComponent<MeshRendererComponent>(floorEntity);
			comp.Mesh = ResourceHandle<StaticMeshResource>(mPlaneResource);
			let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
			comp.MaterialInstances[0] = mFloorMaterial ?? defaultMat;
			comp.MaterialInstances[0]?.AddRef();
			comp.MaterialRefs.Count = 1;
		}

		// Animated cube
		mCubeResource = StaticMeshResource.CreateCube(1.0f);
		mCubeResource.AddRef();
		if (baseMaterial != null)
		{
			mCubeMaterial = new MaterialInstance(baseMaterial);
			mCubeMaterial.SetColor("BaseColor", .(0.2f, 0.5f, 0.9f, 1.0f));
			mCubeMaterial.SetFloat("Roughness", 0.4f);
			mCubeMaterial.SetFloat("Metallic", 0.6f);
		}
		mCubeEntity = mMainScene.CreateEntity();
		{
			mMainScene.SetComponent<MeshRendererComponent>(mCubeEntity, .Default);
			var comp = mMainScene.GetComponent<MeshRendererComponent>(mCubeEntity);
			comp.Mesh = ResourceHandle<StaticMeshResource>(mCubeResource);
			let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
			comp.MaterialInstances[0] = mCubeMaterial ?? defaultMat;
			comp.MaterialInstances[0]?.AddRef();
			comp.MaterialRefs.Count = 1;

			var transform = mMainScene.GetTransform(mCubeEntity);
			transform.Position = .(5, 1, 0);
			mMainScene.SetTransform(mCubeEntity, transform);
		}

		// Camera
		mCameraEntity = mMainScene.CreateEntity();
		renderModule.CreatePerspectiveCamera(mCameraEntity, Math.PI_f / 4.0f, (float)mSwapChain.Width / mSwapChain.Height, 0.1f, 100.0f);
		renderModule.SetMainCamera(mCameraEntity);

		// Sun
		mSunEntity = mMainScene.CreateEntity();
		{
			renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.98f, 0.95f), 2.0f);
			var transform = mMainScene.GetTransform(mSunEntity);
			transform.Rotation = Quaternion.CreateFromYawPitchRoll(0.8f, 0.6f, 0);
			mMainScene.SetTransform(mSunEntity, transform);

			// Enable shadow casting on the sun
			if (let comp = mMainScene.GetComponent<LightComponent>(mSunEntity))
				comp.CastsShadows = true;
		}

		// Enable shadow rendering
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;

		// Create 3 skinned mesh entities
		if (mSkinnedMeshPath != null)
		{
			mStateMachineEntity = CreateSkinnedEntity("StateMachine", .(0, 0, 0));
			mBlendTreeEntity = CreateSkinnedEntity("BlendTree", .(-3, 0, 0));
			mMultiLayerEntity = CreateSkinnedEntity("MultiLayer", .(3, 0, 0));
		}
	}

	private EntityId CreateSkinnedEntity(StringView name, Vector3 position)
	{
		let entity = mMainScene.CreateEntity();
		mMainScene.SetName(entity, name);
		var transform = mMainScene.GetTransform(entity);
		transform.Position = position;
		mMainScene.SetTransform(entity, transform);

		// Add skinned mesh component
		var meshComp = SkinnedMeshRendererComponent.Default;
		meshComp.MeshRef = ResourceRef(mSkinnedMeshId, mSkinnedMeshPath);
		meshComp.MaterialRefs.Count = (int32)Math.Min(mMaterialRefs.Count, 8);
		for (int32 i = 0; i < meshComp.MaterialRefs.Count; i++)
			meshComp.MaterialRefs[i] = ResourceRef(mMaterialRefs[i].Id, mMaterialRefs[i].Path);
		mMainScene.SetComponent<SkinnedMeshRendererComponent>(entity, meshComp);

		// Add skeletal animation component (needed for skinning resolution)
		if (mSkeletonPath != null && mAnimationRefs.Count > 0)
		{
			var animComp = SkeletalAnimationComponent.Default;
			animComp.SkeletonRef = ResourceRef(mSkeletonId, mSkeletonPath);
			animComp.AnimationClipRef = ResourceRef(mAnimationRefs[0].Id, mAnimationRefs[0].Path);
			animComp.Playing = false; // We'll drive animation via graph
			animComp.Loop = true;
			mMainScene.SetComponent<SkeletalAnimationComponent>(entity, animComp);
		}

		return entity;
	}

	// ==================== Animation Graphs ====================

	private void BuildAnimationGraphs()
	{
		if (mSkeleton == null)
		{
			Console.WriteLine("WARNING: No skeleton loaded, cannot build animation graphs");
			return;
		}

		let animModule = mMainScene.GetModule<AnimationSceneModule>();
		if (animModule == null) return;

		// Ensure animation players exist for all entities (wait for resource resolution)
		// We set up the skeleton manually
		animModule.SetupAnimation(mStateMachineEntity, mSkeleton);
		animModule.SetupAnimation(mBlendTreeEntity, mSkeleton);
		animModule.SetupAnimation(mMultiLayerEntity, mSkeleton);

		Console.WriteLine("\n--- Building Animation Graphs ---");
		BuildStateMachineGraph();
		BuildBlendTreeGraph();
		BuildMultiLayerGraph();
		Console.WriteLine("--- Animation Graphs Ready ---");
	}

	private void BuildStateMachineGraph()
	{
		let idleClip = GetClip("idle");
		let walkClip = GetClip("walk");
		let jumpClip = GetClip("jump");
		let dieClip = GetClip("die");
		let danceClip = GetClip("emote-yes");
		let biteClip = GetClip("attack-melee-right");

		mStateMachineGraph = new AnimationGraph();
		Console.WriteLine("\n[Center] State Machine Character:");
		Console.WriteLine("  6 states: Idle, Walk, Jump, Die, Emote Yes, Melee Right");
		Console.WriteLine("  Params: Speed(float), IsGrounded(bool), Die/EmoteYes/MeleeRight(trigger)");
		Console.WriteLine("  Transitions: Idle<->Walk (speed), Any->Jump (!grounded),");
		Console.WriteLine("    Any->Die/EmoteYes/MeleeRight (triggers), exit-time returns to Idle");

		// Parameters
		let speedIdx = mStateMachineGraph.AddParameter("Speed", .Float);
		let groundedIdx = mStateMachineGraph.AddParameter("IsGrounded", .Bool);
		mStateMachineGraph.GetParameter(groundedIdx).BoolValue = true;
		let dieIdx = mStateMachineGraph.AddParameter("Die", .Trigger);
		let emoteYesIdx = mStateMachineGraph.AddParameter("EmoteYes", .Trigger);
		let meleeRightIdx = mStateMachineGraph.AddParameter("MeleeRight", .Trigger);

		// Base layer
		let baseLayer = new AnimationLayer("Base");

		let idleState = baseLayer.AddState(new AnimationGraphState("Idle", new ClipStateNode(idleClip), ownsNode: true));
		let walkState = baseLayer.AddState(new AnimationGraphState("Walk", new ClipStateNode(walkClip), ownsNode: true));
		let jumpState = baseLayer.AddState(new AnimationGraphState("Jump", new ClipStateNode(jumpClip), ownsNode: true));

		let dieState = baseLayer.AddState(new AnimationGraphState("Die", new ClipStateNode(dieClip), ownsNode: true));
		baseLayer.States[dieState].Loop = false;

		let emoteYesState = baseLayer.AddState(new AnimationGraphState("Emote Yes", new ClipStateNode(danceClip), ownsNode: true));
		let meleeRightState = baseLayer.AddState(new AnimationGraphState("Melee Right", new ClipStateNode(biteClip), ownsNode: true));
		baseLayer.States[meleeRightState].Loop = false;

		baseLayer.DefaultStateIndex = idleState;

		// Transitions
		// Idle → Walk (Speed > 0.1)
		let t1 = new AnimationGraphTransition();
		t1.SourceStateIndex = idleState;
		t1.DestStateIndex = walkState;
		t1.Duration = 0.2f;
		t1.AddFloatCondition(speedIdx, .Greater, 0.1f);
		baseLayer.AddTransition(t1);

		// Walk → Idle (Speed <= 0.1)
		let t2 = new AnimationGraphTransition();
		t2.SourceStateIndex = walkState;
		t2.DestStateIndex = idleState;
		t2.Duration = 0.2f;
		t2.AddFloatCondition(speedIdx, .LessEqual, 0.1f);
		baseLayer.AddTransition(t2);

		// Any → Jump (!IsGrounded)
		let t3 = new AnimationGraphTransition();
		t3.SourceStateIndex = -1; // Any state
		t3.DestStateIndex = jumpState;
		t3.Duration = 0.1f;
		t3.Priority = 5;
		t3.AddBoolCondition(groundedIdx, false);
		baseLayer.AddTransition(t3);

		// Jump → Idle (IsGrounded + exit time)
		let t4 = new AnimationGraphTransition();
		t4.SourceStateIndex = jumpState;
		t4.DestStateIndex = idleState;
		t4.Duration = 0.15f;
		t4.HasExitTime = true;
		t4.ExitTime = 0.8f;
		t4.AddBoolCondition(groundedIdx, true);
		baseLayer.AddTransition(t4);

		// Any → Die (trigger)
		let t5 = new AnimationGraphTransition();
		t5.SourceStateIndex = -1;
		t5.DestStateIndex = dieState;
		t5.Duration = 0.15f;
		t5.Priority = 1; // High priority
		t5.AddBoolCondition(dieIdx, true);
		baseLayer.AddTransition(t5);

		// Any → Emote Yes (trigger)
		let t6 = new AnimationGraphTransition();
		t6.SourceStateIndex = -1;
		t6.DestStateIndex = emoteYesState;
		t6.Duration = 0.2f;
		t6.Priority = 3;
		t6.AddBoolCondition(emoteYesIdx, true);
		baseLayer.AddTransition(t6);

		// Emote Yes → Idle (exit time)
		let t7 = new AnimationGraphTransition();
		t7.SourceStateIndex = emoteYesState;
		t7.DestStateIndex = idleState;
		t7.Duration = 0.2f;
		t7.HasExitTime = true;
		t7.ExitTime = 0.95f;
		baseLayer.AddTransition(t7);

		// Any → Melee Right (trigger)
		let t8 = new AnimationGraphTransition();
		t8.SourceStateIndex = -1;
		t8.DestStateIndex = meleeRightState;
		t8.Duration = 0.15f;
		t8.Priority = 2;
		t8.AddBoolCondition(meleeRightIdx, true);
		baseLayer.AddTransition(t8);

		// Melee Right → Idle (exit time)
		let t9 = new AnimationGraphTransition();
		t9.SourceStateIndex = meleeRightState;
		t9.DestStateIndex = idleState;
		t9.Duration = 0.2f;
		t9.HasExitTime = true;
		t9.ExitTime = 0.9f;
		baseLayer.AddTransition(t9);

		mStateMachineGraph.AddLayer(baseLayer);

		// Create player
		let animModule = mMainScene.GetModule<AnimationSceneModule>();
		mStateMachinePlayer = animModule.SetupGraphAnimation(mStateMachineEntity, mStateMachineGraph, mSkeleton);
	}

	private void BuildBlendTreeGraph()
	{
		let idleClip = GetClip("idle");
		let walkClip = GetClip("walk");

		mBlendTreeGraph = new AnimationGraph();
		Console.WriteLine("\n[Left] 1D Blend Tree Character:");
		Console.WriteLine("  BlendTree1D: Idle(0.0) <-> Walk(1.0)");
		Console.WriteLine("  Param: MoveSpeed(float) — slider blends smoothly between clips");

		let speedIdx = mBlendTreeGraph.AddParameter("MoveSpeed", .Float);

		let baseLayer = new AnimationLayer("Base");

		// 1D blend tree: Idle(0) → Walk(1)
		let blendTree = new BlendTree1D();
		blendTree.AddEntry(0.0f, idleClip);
		blendTree.AddEntry(1.0f, walkClip);

		let blendState = baseLayer.AddState(new AnimationGraphState("IdleWalkBlend", blendTree, ownsNode: true));
		baseLayer.DefaultStateIndex = blendState;

		mBlendTreeGraph.AddLayer(baseLayer);

		let animModule = mMainScene.GetModule<AnimationSceneModule>();
		mBlendTreePlayer = animModule.SetupGraphAnimation(mBlendTreeEntity, mBlendTreeGraph, mSkeleton);

		// Link blend tree to parameter
		if (mBlendTreePlayer != null)
			mBlendTreePlayer.LinkBlendTree1D(blendTree, speedIdx);
	}

	private void BuildMultiLayerGraph()
	{
		let idleClip = GetClip("idle");
		let walkClip = GetClip("walk");
		let emoteYesClip = GetClip("emote-yes");
		let emoteNoClip = GetClip("emote-no");

		mMultiLayerGraph = new AnimationGraph();
		Console.WriteLine("\n[Right] Multi-Layer Character:");
		Console.WriteLine("  Base layer: Idle/Walk state machine (Speed param)");
		Console.WriteLine("  Upper body layer: Override blend with bone mask (torso+arms)");
		Console.WriteLine("  Upper states: None, Emote Yes, Emote No");
		Console.WriteLine("  Params: Speed(float), EmoteYes/EmoteNo(trigger), layer weight slider");

		let speedIdx = mMultiLayerGraph.AddParameter("Speed", .Float);
		let emoteYesIdx = mMultiLayerGraph.AddParameter("EmoteYes", .Trigger);
		let emoteNoIdx = mMultiLayerGraph.AddParameter("EmoteNo", .Trigger);

		// Base layer: Idle/Walk state machine
		let baseLayer = new AnimationLayer("Base");
		let idleState = baseLayer.AddState(new AnimationGraphState("Idle", new ClipStateNode(idleClip), ownsNode: true));
		let walkState = baseLayer.AddState(new AnimationGraphState("Walk", new ClipStateNode(walkClip), ownsNode: true));
		baseLayer.DefaultStateIndex = idleState;

		let t1 = new AnimationGraphTransition();
		t1.SourceStateIndex = idleState;
		t1.DestStateIndex = walkState;
		t1.Duration = 0.2f;
		t1.AddFloatCondition(speedIdx, .Greater, 0.1f);
		baseLayer.AddTransition(t1);

		let t2 = new AnimationGraphTransition();
		t2.SourceStateIndex = walkState;
		t2.DestStateIndex = idleState;
		t2.Duration = 0.2f;
		t2.AddFloatCondition(speedIdx, .LessEqual, 0.1f);
		baseLayer.AddTransition(t2);

		mMultiLayerGraph.AddLayer(baseLayer);

		// Upper body overlay layer
		let upperLayer = new AnimationLayer("UpperBody");
		upperLayer.BlendMode = .Override;
		upperLayer.Weight = mMultiLayerUpperWeight;

		// Create bone mask: spine (torso), arms, but not legs or root
		let mask = new BoneMask(mSkeleton.BoneCount, 0.0f);
		let torsoIdx = mSkeleton.FindBone("torso");
		if (torsoIdx >= 0)
			mask.SetBoneChainWeight(mSkeleton, torsoIdx, 1.0f);
		let armLeftIdx = mSkeleton.FindBone("arm-left");
		if (armLeftIdx >= 0)
			mask.SetBoneChainWeight(mSkeleton, armLeftIdx, 1.0f);
		let armRightIdx = mSkeleton.FindBone("arm-right");
		if (armRightIdx >= 0)
			mask.SetBoneChainWeight(mSkeleton, armRightIdx, 1.0f);
		upperLayer.Mask = mask;
		upperLayer.OwnsMask = true;

		// States: None (idle used as placeholder), Emote Yes, Emote No
		let noneState = upperLayer.AddState(new AnimationGraphState("None", new ClipStateNode(idleClip), ownsNode: true));
		let emoteYesState = upperLayer.AddState(new AnimationGraphState("Emote Yes", new ClipStateNode(emoteYesClip), ownsNode: true));
		upperLayer.States[emoteYesState].Loop = false;
		let emoteNoState = upperLayer.AddState(new AnimationGraphState("Emote No", new ClipStateNode(emoteNoClip), ownsNode: true));
		upperLayer.States[emoteNoState].Loop = false;
		upperLayer.DefaultStateIndex = noneState;

		// Any → Emote Yes (trigger)
		let tw = new AnimationGraphTransition();
		tw.SourceStateIndex = -1;
		tw.DestStateIndex = emoteYesState;
		tw.Duration = 0.15f;
		tw.AddBoolCondition(emoteYesIdx, true);
		upperLayer.AddTransition(tw);

		// Emote Yes → None (exit time)
		let tw2 = new AnimationGraphTransition();
		tw2.SourceStateIndex = emoteYesState;
		tw2.DestStateIndex = noneState;
		tw2.Duration = 0.2f;
		tw2.HasExitTime = true;
		tw2.ExitTime = 0.9f;
		upperLayer.AddTransition(tw2);

		// Any → Emote No (trigger)
		let tn = new AnimationGraphTransition();
		tn.SourceStateIndex = -1;
		tn.DestStateIndex = emoteNoState;
		tn.Duration = 0.15f;
		tn.AddBoolCondition(emoteNoIdx, true);
		upperLayer.AddTransition(tn);

		// Emote No → None (exit time)
		let tn2 = new AnimationGraphTransition();
		tn2.SourceStateIndex = emoteNoState;
		tn2.DestStateIndex = noneState;
		tn2.Duration = 0.2f;
		tn2.HasExitTime = true;
		tn2.ExitTime = 0.9f;
		upperLayer.AddTransition(tn2);

		mMultiLayerGraph.AddLayer(upperLayer);

		let animModule = mMainScene.GetModule<AnimationSceneModule>();
		mMultiLayerPlayer = animModule.SetupGraphAnimation(mMultiLayerEntity, mMultiLayerGraph, mSkeleton);
	}

	// ==================== Property Animation Demo ====================

	private void SetupPropertyAnimationDemo()
	{
		let animModule = mMainScene.GetModule<AnimationSceneModule>();
		if (animModule == null) return;

		let cacheDir = scope String();
		GetAssetPath(CACHE_REL_PATH, cacheDir);
		Directory.CreateDirectory(cacheDir);

		let clipPath = scope String();
		clipPath.AppendF("{}/sun_cycle.propanimation", cacheDir);

		if (File.Exists(clipPath))
		{
			// Load from file
			if (PropertyAnimationClipResource.LoadFromFile(clipPath) case .Ok(let resource))
			{
				mSunAnimResource = resource;
				mSunAnimResource.AddRef();
				mSunAnimClip = resource.Clip;
				Console.WriteLine($"Loaded property animation from: {clipPath}");
			}
			else
			{
				Console.WriteLine("WARNING: Failed to load property animation, recreating...");
				mSunAnimClip = CreateSunAnimationClip();
				SaveAnimationClip(mSunAnimClip, clipPath);
			}
		}
		else
		{
			// Create and save
			mSunAnimClip = CreateSunAnimationClip();
			SaveAnimationClip(mSunAnimClip, clipPath);
		}

		if (mSunAnimClip != null)
		{
			animModule.PlayPropertyAnimation(mSunEntity, mSunAnimClip, true);
			Console.WriteLine("Property animation playing: sun rotation cycle (10s loop)");
		}

		// Cube animation: load or create + save
		let cubeClipPath = scope String();
		cubeClipPath.AppendF("{}/cube_orbit.propanimation", cacheDir);

		if (File.Exists(cubeClipPath))
		{
			if (PropertyAnimationClipResource.LoadFromFile(cubeClipPath) case .Ok(let resource))
			{
				mCubeAnimResource = resource;
				mCubeAnimResource.AddRef();
				mCubeAnimClip = resource.Clip;
				Console.WriteLine($"Loaded cube animation from: {cubeClipPath}");
			}
			else
			{
				Console.WriteLine("WARNING: Failed to load cube animation, recreating...");
				mCubeAnimClip = CreateCubeAnimationClip();
				SaveAnimationClip(mCubeAnimClip, cubeClipPath);
			}
		}
		else
		{
			mCubeAnimClip = CreateCubeAnimationClip();
			SaveAnimationClip(mCubeAnimClip, cubeClipPath);
		}

		if (mCubeAnimClip != null)
		{
			animModule.PlayPropertyAnimation(mCubeEntity, mCubeAnimClip, true);
			Console.WriteLine("Property animation playing: cube orbit (8s loop)");
		}
	}

	private PropertyAnimationClip CreateSunAnimationClip()
	{
		let clip = new PropertyAnimationClip("SunCycle", 10.0f, true);

		// Animate sun rotation: sweeping yaw over 10 seconds
		let rotTrack = clip.AddQuaternionTrack("Transform.Rotation");
		rotTrack.Easing = .Linear;

		// Keyframes: rotate from one angle through a sweep and back
		rotTrack.AddKeyframe(0.0f, Quaternion.CreateFromYawPitchRoll(0.8f, 0.6f, 0));
		rotTrack.AddKeyframe(2.5f, Quaternion.CreateFromYawPitchRoll(1.6f, 0.8f, 0));
		rotTrack.AddKeyframe(5.0f, Quaternion.CreateFromYawPitchRoll(2.4f, 0.6f, 0));
		rotTrack.AddKeyframe(7.5f, Quaternion.CreateFromYawPitchRoll(1.6f, 0.4f, 0));
		rotTrack.AddKeyframe(10.0f, Quaternion.CreateFromYawPitchRoll(0.8f, 0.6f, 0));

		Console.WriteLine("Created property animation clip: SunCycle (5 keyframes, 10s)");
		return clip;
	}

	private PropertyAnimationClip CreateCubeAnimationClip()
	{
		let clip = new PropertyAnimationClip("CubeOrbit", 8.0f, true);

		// Animate position: orbit around center at y=1.5
		let posTrack = clip.AddVector3Track("Transform.Position");
		posTrack.Easing = .Linear;
		float radius = 5.0f;
		float height = 1.5f;
		int32 steps = 8;
		for (int32 i = 0; i <= steps; i++)
		{
			float t = (float)i / steps * 8.0f;
			float angle = (float)i / steps * Math.PI_f * 2.0f;
			posTrack.AddKeyframe(t, Vector3(Math.Cos(angle) * radius, height, Math.Sin(angle) * radius));
		}

		// Animate rotation: continuous spin
		let rotTrack = clip.AddQuaternionTrack("Transform.Rotation");
		rotTrack.Easing = .Linear;
		for (int32 i = 0; i <= steps; i++)
		{
			float t = (float)i / steps * 8.0f;
			float angle = (float)i / steps * Math.PI_f * 2.0f;
			rotTrack.AddKeyframe(t, Quaternion.CreateFromYawPitchRoll(angle, angle * 0.5f, 0));
		}

		// Animate scale: pulsing
		let scaleTrack = clip.AddVector3Track("Transform.Scale");
		scaleTrack.Easing = .EaseInOutCubic;
		scaleTrack.AddKeyframe(0.0f, Vector3(1.0f, 1.0f, 1.0f));
		scaleTrack.AddKeyframe(2.0f, Vector3(1.5f, 0.7f, 1.5f));
		scaleTrack.AddKeyframe(4.0f, Vector3(0.7f, 1.5f, 0.7f));
		scaleTrack.AddKeyframe(6.0f, Vector3(1.5f, 0.7f, 1.5f));
		scaleTrack.AddKeyframe(8.0f, Vector3(1.0f, 1.0f, 1.0f));

		Console.WriteLine("Created property animation clip: CubeOrbit (position + rotation + scale, 8s)");
		return clip;
	}

	private void SaveAnimationClip(PropertyAnimationClip clip, StringView path)
	{
		let resource = new PropertyAnimationClipResource(clip);
		defer delete resource;

		if (resource.SaveToFile(path) case .Ok)
			Console.WriteLine($"Saved property animation to: {path}");
		else
			Console.WriteLine("WARNING: Failed to save property animation");
	}

	// ==================== UI ====================

	private void CreateUI()
	{
		if (mUISubsystem == null || !mUISubsystem.IsInitialized)
			return;

		mUIRoot = new Canvas();

		// Bottom panel
		let panel = new StackPanel();
		panel.Orientation = .Horizontal;
		panel.Background = Color(20, 20, 30, 200);
		panel.Padding = Thickness(10);
		panel.Spacing = 20;
		panel.VerticalAlignment = .Bottom;
		panel.HorizontalAlignment = .Stretch;

		// Section 1: State Machine
		let smPanel = CreateStateMachineUI();
		panel.AddChild(smPanel);

		// Section 2: Blend Tree
		let btPanel = CreateBlendTreeUI();
		panel.AddChild(btPanel);

		// Section 3: Multi-Layer
		let mlPanel = CreateMultiLayerUI();
		panel.AddChild(mlPanel);

		mUIRoot.AddChild(panel);
		mUISubsystem.GUIContext.RootElement = mUIRoot;
	}

	private StackPanel CreateStateMachineUI()
	{
		let panel = new StackPanel();
		panel.Spacing = 4;
		panel.Padding = Thickness(6);

		let title = new TextBlock();
		title.Text = "State Machine";
		title.Foreground = Color(200, 220, 255);
		title.FontSize = 14;
		panel.AddChild(title);

		// Speed slider
		let speedRow = new StackPanel();
		speedRow.Orientation = .Horizontal;
		speedRow.Spacing = 6;
		let speedLabel = new TextBlock();
		speedLabel.Text = "Speed:";
		speedLabel.Foreground = Color.White;
		speedRow.AddChild(speedLabel);

		let speedSlider = new Slider();
		speedSlider.Width = .Fixed(120);
		speedSlider.Minimum = 0;
		speedSlider.Maximum = 100;
		speedSlider.Value = 0;
		speedSlider.ValueChanged.Subscribe(new (slider, value) => { mStateMachineSpeed = value / 100.0f; });
		speedRow.AddChild(speedSlider);
		panel.AddChild(speedRow);

		// Grounded checkbox
		let groundedRow = new StackPanel();
		groundedRow.Orientation = .Horizontal;
		groundedRow.Spacing = 6;
		let groundedCheck = new CheckBox();
		groundedCheck.IsChecked = true;
		groundedCheck.Checked.Subscribe(new (cb, isChecked) => { mStateMachineGrounded = true; });
		groundedCheck.Unchecked.Subscribe(new (cb) => { mStateMachineGrounded = false; });
		groundedRow.AddChild(groundedCheck);
		let groundedLabel = new TextBlock();
		groundedLabel.Text = "Grounded";
		groundedLabel.Foreground = Color.White;
		groundedRow.AddChild(groundedLabel);
		panel.AddChild(groundedRow);

		// Action buttons
		let btnRow = new StackPanel();
		btnRow.Orientation = .Horizontal;
		btnRow.Spacing = 4;

		let dieBtn = new Button("Die");
		dieBtn.Width = .Fixed(50);
		dieBtn.Click.Subscribe(new (btn) => { mStateMachinePlayer?.SetTrigger("Die"); });
		btnRow.AddChild(dieBtn);

		let emoteYesBtn = new Button("Emote Yes");
		emoteYesBtn.Width = .Fixed(80);
		emoteYesBtn.Click.Subscribe(new (btn) => { mStateMachinePlayer?.SetTrigger("EmoteYes"); });
		btnRow.AddChild(emoteYesBtn);

		let meleeRightBtn = new Button("Melee Right");
		meleeRightBtn.Width = .Fixed(90);
		meleeRightBtn.Click.Subscribe(new (btn) => { mStateMachinePlayer?.SetTrigger("MeleeRight"); });
		btnRow.AddChild(meleeRightBtn);

		panel.AddChild(btnRow);

		// State label
		mStateMachineLabel = new TextBlock();
		mStateMachineLabel.Text = "State: Idle";
		mStateMachineLabel.Foreground = Color(180, 255, 180);
		panel.AddChild(mStateMachineLabel);

		return panel;
	}

	private StackPanel CreateBlendTreeUI()
	{
		let panel = new StackPanel();
		panel.Spacing = 4;
		panel.Padding = Thickness(6);

		let title = new TextBlock();
		title.Text = "1D Blend Tree";
		title.Foreground = Color(200, 220, 255);
		title.FontSize = 14;
		panel.AddChild(title);

		// MoveSpeed slider
		let speedRow = new StackPanel();
		speedRow.Orientation = .Horizontal;
		speedRow.Spacing = 6;
		let speedLabel = new TextBlock();
		speedLabel.Text = "Speed:";
		speedLabel.Foreground = Color.White;
		speedRow.AddChild(speedLabel);

		let speedSlider = new Slider();
		speedSlider.Width = .Fixed(120);
		speedSlider.Minimum = 0;
		speedSlider.Maximum = 100;
		speedSlider.Value = 0;
		speedSlider.ValueChanged.Subscribe(new (slider, value) => { mBlendTreeSpeed = value / 100.0f; });
		speedRow.AddChild(speedSlider);
		panel.AddChild(speedRow);

		// Label
		mBlendTreeLabel = new TextBlock();
		mBlendTreeLabel.Text = "Blend: 0.0";
		mBlendTreeLabel.Foreground = Color(180, 255, 180);
		panel.AddChild(mBlendTreeLabel);

		return panel;
	}

	private StackPanel CreateMultiLayerUI()
	{
		let panel = new StackPanel();
		panel.Spacing = 4;
		panel.Padding = Thickness(6);

		let title = new TextBlock();
		title.Text = "Multi-Layer";
		title.Foreground = Color(200, 220, 255);
		title.FontSize = 14;
		panel.AddChild(title);

		// Speed slider
		let speedRow = new StackPanel();
		speedRow.Orientation = .Horizontal;
		speedRow.Spacing = 6;
		let speedLabel = new TextBlock();
		speedLabel.Text = "Speed:";
		speedLabel.Foreground = Color.White;
		speedRow.AddChild(speedLabel);

		let speedSlider = new Slider();
		speedSlider.Width = .Fixed(120);
		speedSlider.Minimum = 0;
		speedSlider.Maximum = 100;
		speedSlider.Value = 0;
		speedSlider.ValueChanged.Subscribe(new (slider, value) => { mMultiLayerSpeed = value / 100.0f; });
		speedRow.AddChild(speedSlider);
		panel.AddChild(speedRow);

		// Upper body buttons
		let btnRow = new StackPanel();
		btnRow.Orientation = .Horizontal;
		btnRow.Spacing = 4;

		let emoteYesBtn = new Button("Emote Yes");
		emoteYesBtn.Width = .Fixed(80);
		emoteYesBtn.Click.Subscribe(new (btn) => { mMultiLayerPlayer?.SetTrigger("EmoteYes"); });
		btnRow.AddChild(emoteYesBtn);

		let emoteNoBtn = new Button("Emote No");
		emoteNoBtn.Width = .Fixed(80);
		emoteNoBtn.Click.Subscribe(new (btn) => { mMultiLayerPlayer?.SetTrigger("EmoteNo"); });
		btnRow.AddChild(emoteNoBtn);
		panel.AddChild(btnRow);

		// Layer weight slider
		let weightRow = new StackPanel();
		weightRow.Orientation = .Horizontal;
		weightRow.Spacing = 6;
		let weightLabel = new TextBlock();
		weightLabel.Text = "Upper:";
		weightLabel.Foreground = Color.White;
		weightRow.AddChild(weightLabel);

		let weightSlider = new Slider();
		weightSlider.Width = .Fixed(120);
		weightSlider.Minimum = 0;
		weightSlider.Maximum = 100;
		weightSlider.Value = (int32)(mMultiLayerUpperWeight * 100);
		weightSlider.ValueChanged.Subscribe(new (slider, value) => { mMultiLayerUpperWeight = value / 100.0f; });
		weightRow.AddChild(weightSlider);
		panel.AddChild(weightRow);

		// State label
		mMultiLayerLabel = new TextBlock();
		mMultiLayerLabel.Text = "Base: Idle | Upper: None";
		mMultiLayerLabel.Foreground = Color(180, 255, 180);
		panel.AddChild(mMultiLayerLabel);

		return panel;
	}

	// ==================== Update ====================

	protected override void OnInput()
	{
		let input = mShell.InputManager;
		if (input == null) return;

		let keyboard = input.Keyboard;
		let mouse = input.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		if (keyboard.IsKeyPressed(.Tab) || keyboard.IsKeyPressed(.Grave))
			mCamera.CurrentMode = (mCamera.CurrentMode == .Orbital) ? .Flythrough : .Orbital;

		mCamera.HandleInput(keyboard, mouse, mDeltaTime);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;

		// Sync parameters from UI to graph players
		if (mStateMachinePlayer != null)
		{
			mStateMachinePlayer.SetFloat("Speed", mStateMachineSpeed);
			mStateMachinePlayer.SetBool("IsGrounded", mStateMachineGrounded);
		}

		if (mBlendTreePlayer != null)
		{
			mBlendTreePlayer.SetFloat("MoveSpeed", mBlendTreeSpeed);
		}

		if (mMultiLayerPlayer != null)
		{
			mMultiLayerPlayer.SetFloat("Speed", mMultiLayerSpeed);
			// Update upper body layer weight
			if (mMultiLayerGraph != null && mMultiLayerGraph.Layers.Count > 1)
				mMultiLayerGraph.Layers[1].Weight = mMultiLayerUpperWeight;
		}

		// Graph players are updated automatically by AnimationSceneModule
		// Skinning matrices are synced to standard players by AnimationSceneModule

		// Update UI labels
		UpdateLabels();
	}

	private void UpdateLabels()
	{
		if (mStateMachineLabel != null && mStateMachinePlayer != null)
		{
			let stateName = mStateMachinePlayer.GetCurrentStateName();
			let transitioning = mStateMachinePlayer.IsTransitioning() ? " (blending)" : "";
			let text = scope String();
			text.AppendF("State: {}{}", stateName, transitioning);
			mStateMachineLabel.Text = text;
		}

		if (mBlendTreeLabel != null)
		{
			let text = scope String();
			text.AppendF("Blend: {}", mBlendTreeSpeed);
			mBlendTreeLabel.Text = text;
		}

		if (mMultiLayerLabel != null && mMultiLayerPlayer != null)
		{
			let baseName = mMultiLayerPlayer.GetCurrentStateName(0);
			let upperName = mMultiLayerPlayer.GetCurrentStateName(1);
			let text = scope String();
			text.AppendF("Base: {} | Upper: {}", baseName, upperName);
			mMultiLayerLabel.Text = text;
		}
	}

	// ==================== Render ====================

	protected override bool OnRenderFrame(RenderContext render)
	{
		SProfiler.BeginFrame();

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

		// Render screen-space UI overlay
		if (mUISubsystem != null && mUISubsystem.IsInitialized)
			mUISubsystem.RenderUI(render.Encoder, render.CurrentTextureView, mSwapChain.Width, mSwapChain.Height, render.Frame.FrameIndex);

		// End frame
		mRenderSystem.EndFrame();

		SProfiler.EndFrame();
		return true;
	}

	// ==================== Shutdown ====================

	protected override void OnShutdown()
	{
		SProfiler.Shutdown();

		// Remove registry before resource system shuts down
		mContext.Resources.RemoveRegistry(mRegistry);

		// Release resource handles while resource system is still alive
		for (var h in mClipHandles)
			h.Release();
		mSkeletonHandle.Release();

		// Release material instances before render system shutdown
		mFloorMaterial?.ReleaseRef();
		mCubeMaterial?.ReleaseRef();

		// Delete animation graphs (reference clips by pointer, don't own them)
		delete mStateMachineGraph;
		delete mBlendTreeGraph;
		delete mMultiLayerGraph;

		// Release property animations: resource owns clip when loaded from file,
		// otherwise we own the clip directly
		if (mSunAnimResource != null)
			mSunAnimResource.ReleaseRef();
		else
			delete mSunAnimClip;

		if (mCubeAnimResource != null)
			mCubeAnimResource.ReleaseRef();
		else
			delete mCubeAnimClip;

		// Shutdown render system (GPU idle, release features/GPU resources)
		mRenderSystem?.Shutdown();

		// Delete render objects
		delete mRenderView;
		delete mRenderSystem;

		// Delete camera
		delete mCamera;

		// Delete mesh resources (CPU-side, after render system done with it)
		mPlaneResource?.ReleaseRef();
		mCubeResource?.ReleaseRef();

		// Clean up clip data
		for (let kv in mClipsByName)
			delete kv.key;
		delete mClipsByName;
		delete mClipHandles;

		// Dispose resource refs
		for (var r in mMaterialRefs)
			r.Dispose();
		delete mMaterialRefs;

		for (var r in mAnimationRefs)
			r.Dispose();
		delete mAnimationRefs;

		// Delete UI
		delete mUIRoot;

		// Delete font service
		delete mFontService;

		// Delete owned strings and registry
		delete mSkinnedMeshPath;
		delete mSkeletonPath;
		delete mRegistry;
	}
}
