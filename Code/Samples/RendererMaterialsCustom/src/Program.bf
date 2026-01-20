namespace RendererMaterialsCustom;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Imaging;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Renderer;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Debug;
using SampleFramework;
using Sedulous.Renderer.Resources;
using Sedulous.Geometry.Resources;

/// Demonstrates creating a custom Toon/Cel-Shading material.
/// Shows how to define material parameters that map to custom shaders.
class RendererMaterialsCustomSample : RHISampleApp
{
	// Framework.Core components
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;

	// Renderer components
	private RendererService mRendererService;
	private RenderSceneComponent mRenderSceneComponent;

	// Custom toon material (static meshes)
	private MaterialHandle mToonMaterial = .Invalid;
	private List<MaterialInstanceHandle> mMaterialInstances = new .() ~ delete _;
	private MaterialInstanceHandle mGroundMaterial = .Invalid;

	// Fox material instance (uses same toon material, renderer picks skinned variant)
	private MaterialInstanceHandle mFoxMaterialInstance = .Invalid;

	// Fox (skinned mesh) resources
	private Model mFoxModel ~ delete _;
	private SkinnedMeshResource mFoxResource ~ delete _;
	private Entity mFoxEntity;
	private GPUTextureHandle mFoxTexture = .Invalid;

	// Camera entity and control
	private Entity mCameraEntity;
	private float mCameraYaw = Math.PI_f;
	private float mCameraPitch = -0.2f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 10.0f;
	private float mCameraLookSpeed = 0.003f;

	// Light direction control
	private Entity mSunLightEntity;
	private float mLightYaw = 0.5f;
	private float mLightPitch = -0.7f;

	// Current frame index
	private int32 mCurrentFrameIndex = 0;

	public this() : base(.()
	{
		Title = "Custom Material Demo - Toon Shading",
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

		// Start context before creating scenes (enables automatic component creation)
		mContext.Startup();

		// Create scene - RenderSceneComponent is added automatically by RendererService
		mScene = mContext.SceneManager.CreateScene("ToonScene");
		mRenderSceneComponent = mScene.GetSceneComponent<RenderSceneComponent>();
		mContext.SceneManager.SetActiveScene(mScene);

		// Load Fox model
		if (!LoadFox())
		{
			Console.WriteLine("Warning: Failed to load Fox model, continuing without it");
		}

		// Create materials and entities
		CreateToonMaterial();
		CreateEntities();

		Console.WriteLine("Custom Material Demo - Toon Shading initialized");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Tab=Toggle mouse capture, Shift=Fast");
		Console.WriteLine("          Arrow keys=Adjust light direction");

		return true;
	}

	/// Creates a custom toon shading material.
	/// This demonstrates how to define a new material type with custom parameters.
	private Material CreateToonMaterialDefinition(StringView name)
	{
		// Create material with "toon" shader name - will load toon.vert.hlsl and toon.frag.hlsl
		let mat = new Material(name, "toon");
		mat.RenderQueue = 0;

		// Toon material parameters (must match the HLSL cbuffer MaterialUniforms in toon.frag.hlsl)
		// Each parameter specifies: name, binding (1 = material uniform buffer), byte offset

		mat.AddFloat4Param("baseColor", 1, 0);       // float4 at offset 0  - Base diffuse color
		mat.AddFloat4Param("shadowColor", 1, 16);    // float4 at offset 16 - Color in shadow areas
		mat.AddFloat4Param("rimColor", 1, 32);       // float4 at offset 32 - Rim highlight color
		mat.AddFloatParam("bands", 1, 48);           // float at offset 48  - Number of shading bands
		mat.AddFloatParam("rimPower", 1, 52);        // float at offset 52  - Rim falloff exponent
		mat.AddFloatParam("rimIntensity", 1, 56);    // float at offset 56  - Rim light strength
		mat.AddFloatParam("shadowThreshold", 1, 60); // float at offset 60  - Shadow band threshold

		mat.UniformBufferSize = 64;

		// Texture binding (optional albedo texture)
		mat.AddTextureParam("albedoMap", 0);

		// Sampler
		mat.AddSamplerParam("materialSampler", 0);

		return mat;
	}

	private bool LoadFox()
	{
		mFoxModel = new Model();
		let loader = scope GltfLoader();

		let gltfPath = GetAssetPath("samples/models/Fox/glTF/Fox.gltf", .. scope .());
		let result = loader.Load(gltfPath, mFoxModel);
		if (result != .Ok)
		{
			Console.WriteLine(scope $"Failed to load Fox model: {result}");
			delete mFoxModel;
			mFoxModel = null;
			return false;
		}

		Console.WriteLine(scope $"Fox model loaded: {mFoxModel.Meshes.Count} meshes, {mFoxModel.Bones.Count} bones, {mFoxModel.Animations.Count} animations");

		// Use ModelImporter to convert all resources
		let importOptions = new ModelImportOptions();
		importOptions.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Textures | .Materials;
		let gltfBasePath = GetAssetPath("samples/models/Fox/glTF", .. scope .());
		importOptions.BasePath.Set(gltfBasePath);

		let imageLoader = scope SDLImageLoader();
		let importer = scope ModelImporter(importOptions, imageLoader);
		let importResult = importer.Import(mFoxModel);
		defer delete importResult;

		if (!importResult.Success)
		{
			Console.WriteLine("Fox import errors:");
			for (let err in importResult.Errors)
				Console.WriteLine(scope $"  - {err}");
			return false;
		}

		Console.WriteLine(scope $"Fox import result: {importResult.SkinnedMeshes.Count} skinned meshes, {importResult.Skeletons.Count} skeletons");

		// Take ownership of the first skinned mesh
		if (importResult.SkinnedMeshes.Count > 0)
		{
			mFoxResource = importResult.TakeSkinnedMesh(0);
			Console.WriteLine(scope $"Fox resource: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.AnimationCount} animations");
		}
		else
		{
			Console.WriteLine("No skinned meshes in Fox import result");
			return false;
		}

		// Load Fox texture
		let texPath = GetAssetPath("samples/models/Fox/glTF/Texture.png", .. scope .());
		let texImageLoader = scope SDLImageLoader();
		if (texImageLoader.LoadFromFile(texPath) case .Ok(var loadInfo))
		{
			defer loadInfo.Dispose();
			Console.WriteLine(scope $"Fox texture: {loadInfo.Width}x{loadInfo.Height}");

			// Create GPU texture via ResourceManager
			mFoxTexture = mRendererService.ResourceManager.CreateTextureFromData(
				loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .(loadInfo.Data.Ptr, loadInfo.Data.Count));

			if (mFoxTexture.IsValid)
				Console.WriteLine("Fox texture uploaded to GPU");
		}
		else
		{
			Console.WriteLine("Warning: Failed to load Fox texture");
		}

		return true;
	}

	private void CreateToonMaterial()
	{
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null)
		{
			Console.WriteLine("MaterialSystem not available!");
			return;
		}

		// Create and register the toon material definition
		let toonMaterial = CreateToonMaterialDefinition("ToonMaterial");
		mToonMaterial = materialSystem.RegisterMaterial(toonMaterial);

		if (!mToonMaterial.IsValid)
		{
			Console.WriteLine("Failed to register Toon material");
			return;
		}

		Console.WriteLine($"Created Toon material with {toonMaterial.Parameters.Count} parameters");

		// Create different toon style instances

		// Style 1: Classic cel-shaded red (3 bands)
		{
			let handle = materialSystem.CreateInstance(mToonMaterial);
			if (handle.IsValid)
			{
				let instance = materialSystem.GetInstance(handle);
				instance.SetFloat4("baseColor", .(0.9f, 0.2f, 0.2f, 1.0f));      // Red
				instance.SetFloat4("shadowColor", .(0.3f, 0.05f, 0.05f, 1.0f));  // Dark red shadow
				instance.SetFloat4("rimColor", .(1.0f, 0.8f, 0.8f, 1.0f));       // Pink rim
				instance.SetFloat("bands", 3.0f);
				instance.SetFloat("rimPower", 3.0f);
				instance.SetFloat("rimIntensity", 0.5f);
				instance.SetFloat("shadowThreshold", 0.3f);
				materialSystem.UploadInstance(handle);
				mMaterialInstances.Add(handle);
			}
		}

		// Style 2: Anime-style blue (2 bands - harsh)
		{
			let handle = materialSystem.CreateInstance(mToonMaterial);
			if (handle.IsValid)
			{
				let instance = materialSystem.GetInstance(handle);
				instance.SetFloat4("baseColor", .(0.2f, 0.4f, 0.9f, 1.0f));      // Blue
				instance.SetFloat4("shadowColor", .(0.05f, 0.1f, 0.3f, 1.0f));   // Dark blue shadow
				instance.SetFloat4("rimColor", .(0.6f, 0.8f, 1.0f, 1.0f));       // Light blue rim
				instance.SetFloat("bands", 2.0f);
				instance.SetFloat("rimPower", 2.0f);
				instance.SetFloat("rimIntensity", 0.7f);
				instance.SetFloat("shadowThreshold", 0.5f);
				materialSystem.UploadInstance(handle);
				mMaterialInstances.Add(handle);
			}
		}

		// Style 3: Soft green (5 bands - smooth)
		{
			let handle = materialSystem.CreateInstance(mToonMaterial);
			if (handle.IsValid)
			{
				let instance = materialSystem.GetInstance(handle);
				instance.SetFloat4("baseColor", .(0.3f, 0.8f, 0.3f, 1.0f));      // Green
				instance.SetFloat4("shadowColor", .(0.1f, 0.25f, 0.1f, 1.0f));   // Dark green shadow
				instance.SetFloat4("rimColor", .(0.7f, 1.0f, 0.7f, 1.0f));       // Light green rim
				instance.SetFloat("bands", 5.0f);
				instance.SetFloat("rimPower", 4.0f);
				instance.SetFloat("rimIntensity", 0.3f);
				instance.SetFloat("shadowThreshold", 0.2f);
				materialSystem.UploadInstance(handle);
				mMaterialInstances.Add(handle);
			}
		}

		// Style 4: Golden/yellow (4 bands)
		{
			let handle = materialSystem.CreateInstance(mToonMaterial);
			if (handle.IsValid)
			{
				let instance = materialSystem.GetInstance(handle);
				instance.SetFloat4("baseColor", .(1.0f, 0.8f, 0.2f, 1.0f));      // Gold
				instance.SetFloat4("shadowColor", .(0.4f, 0.25f, 0.05f, 1.0f));  // Dark gold shadow
				instance.SetFloat4("rimColor", .(1.0f, 1.0f, 0.6f, 1.0f));       // Bright yellow rim
				instance.SetFloat("bands", 4.0f);
				instance.SetFloat("rimPower", 2.5f);
				instance.SetFloat("rimIntensity", 0.6f);
				instance.SetFloat("shadowThreshold", 0.25f);
				materialSystem.UploadInstance(handle);
				mMaterialInstances.Add(handle);
			}
		}

		// Style 5: Purple/violet (3 bands)
		{
			let handle = materialSystem.CreateInstance(mToonMaterial);
			if (handle.IsValid)
			{
				let instance = materialSystem.GetInstance(handle);
				instance.SetFloat4("baseColor", .(0.6f, 0.2f, 0.8f, 1.0f));      // Purple
				instance.SetFloat4("shadowColor", .(0.2f, 0.05f, 0.3f, 1.0f));   // Dark purple shadow
				instance.SetFloat4("rimColor", .(0.9f, 0.6f, 1.0f, 1.0f));       // Light purple rim
				instance.SetFloat("bands", 3.0f);
				instance.SetFloat("rimPower", 3.0f);
				instance.SetFloat("rimIntensity", 0.5f);
				instance.SetFloat("shadowThreshold", 0.35f);
				materialSystem.UploadInstance(handle);
				mMaterialInstances.Add(handle);
			}
		}

		Console.WriteLine($"Created {mMaterialInstances.Count} toon material instances");

		// Create ground material (gray toon)
		mGroundMaterial = materialSystem.CreateInstance(mToonMaterial);
		if (mGroundMaterial.IsValid)
		{
			let groundInstance = materialSystem.GetInstance(mGroundMaterial);
			groundInstance.SetFloat4("baseColor", .(0.5f, 0.5f, 0.55f, 1.0f));    // Gray
			groundInstance.SetFloat4("shadowColor", .(0.15f, 0.15f, 0.2f, 1.0f)); // Dark gray
			groundInstance.SetFloat4("rimColor", .(0.7f, 0.7f, 0.75f, 1.0f));     // Light gray rim
			groundInstance.SetFloat("bands", 3.0f);
			groundInstance.SetFloat("rimPower", 5.0f);
			groundInstance.SetFloat("rimIntensity", 0.2f);
			groundInstance.SetFloat("shadowThreshold", 0.3f);
			materialSystem.UploadInstance(mGroundMaterial);
		}

		// Create Fox material instance using same toon material
		// SkinnedMeshRenderer will automatically load the "skinned_toon" shader variant
		if (mFoxResource != null)
		{
			mFoxMaterialInstance = materialSystem.CreateInstance(mToonMaterial);
			if (mFoxMaterialInstance.IsValid)
			{
				let foxInstance = materialSystem.GetInstance(mFoxMaterialInstance);
				foxInstance.SetFloat4("baseColor", .(1.0f, 1.0f, 1.0f, 1.0f));      // White base (texture provides color)
				foxInstance.SetFloat4("shadowColor", .(0.3f, 0.15f, 0.1f, 1.0f));   // Dark orange shadow
				foxInstance.SetFloat4("rimColor", .(1.0f, 0.9f, 0.7f, 1.0f));       // Warm cream rim
				foxInstance.SetFloat("bands", 3.0f);
				foxInstance.SetFloat("rimPower", 2.5f);
				foxInstance.SetFloat("rimIntensity", 0.4f);
				foxInstance.SetFloat("shadowThreshold", 0.3f);

				// Set the albedo texture
				if (mFoxTexture.IsValid)
				{
					foxInstance.SetTexture("albedoMap", mFoxTexture);
					Console.WriteLine("Set Fox albedo texture on toon material");
				}

				materialSystem.UploadInstance(mFoxMaterialInstance);
				Console.WriteLine("Created Fox toon material instance");
			}
		}
	}

	private void CreateEntities()
	{
		// Create sphere mesh for main objects
		let sphereMesh = StaticMesh.CreateSphere(0.8f, 32, 16);
		defer delete sphereMesh;

		// Create cube mesh for variety
		let cubeMesh = StaticMesh.CreateCube(1.2f);
		defer delete cubeMesh;

		// Create ground plane
		let groundMesh = StaticMesh.CreateCube(1.0f);
		defer delete groundMesh;

		// Ground
		{
			let groundEntity = mScene.CreateEntity("Ground");
			groundEntity.Transform.SetPosition(.(0, -1.5f, 0));
			groundEntity.Transform.SetScale(.(25.0f, 0.2f, 25.0f));

			let meshComponent = new StaticMeshComponent();
			meshComponent.SetMaterialInstance(0, mGroundMaterial);
			meshComponent.MaterialCount = 1;
			groundEntity.AddComponent(meshComponent);
			meshComponent.SetMesh(groundMesh);
		}

		// Create objects with different toon materials
		float spacing = 3.0f;
		float startX = -((mMaterialInstances.Count - 1) * spacing) / 2.0f;

		for (int32 i = 0; i < mMaterialInstances.Count; i++)
		{
			float posX = startX + i * spacing;

			// Main sphere
			{
				let entity = mScene.CreateEntity(scope $"ToonSphere_{i}");
				entity.Transform.SetPosition(.(posX, 0.5f, 0));

				let meshComponent = new StaticMeshComponent();
				meshComponent.SetMaterialInstance(0, mMaterialInstances[i]);
				meshComponent.MaterialCount = 1;
				entity.AddComponent(meshComponent);
				meshComponent.SetMesh(sphereMesh);
			}

			// Small cube behind
			{
				let entity = mScene.CreateEntity(scope $"ToonCube_{i}");
				entity.Transform.SetPosition(.(posX, 0.3f, -2.5f));
				entity.Transform.SetScale(.(0.6f, 0.6f, 0.6f));

				let meshComponent = new StaticMeshComponent();
				meshComponent.SetMaterialInstance(0, mMaterialInstances[i]);
				meshComponent.MaterialCount = 1;
				entity.AddComponent(meshComponent);
				meshComponent.SetMesh(cubeMesh);
			}
		}

		// Create directional light (important for toon shading!)
		{
			mSunLightEntity = mScene.CreateEntity("SunLight");
			mSunLightEntity.Transform.LookAt(GetLightDirection());

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.98f, 0.95f), 2.5f, true);
			mSunLightEntity.AddComponent(lightComp);
		}

		// Create fill light (softer, from opposite direction)
		{
			let fillLight = mScene.CreateEntity("FillLight");
			fillLight.Transform.SetPosition(.(-5, 3, 5));
			fillLight.AddComponent(LightComponent.CreatePoint(.(0.4f, 0.5f, 0.6f), 3.0f, 20.0f));
		}

		// Create Fox skinned mesh with toon shading
		if (mFoxResource != null)
		{
			mFoxEntity = mScene.CreateEntity("ToonFox");
			// Position the fox to the right of the toon objects, scale it down (it's big in native units)
			mFoxEntity.Transform.SetPosition(.(8.0f, -1.4f, 0.0f));
			mFoxEntity.Transform.SetScale(.(0.03f, 0.03f, 0.03f));  // Scale down from ~100 units to ~3 units

			let skinnedMeshComp = new SkinnedMeshComponent();
			mFoxEntity.AddComponent(skinnedMeshComp);

			// Set skeleton first (required before SetMesh)
			skinnedMeshComp.SetSkeleton(mFoxResource.Skeleton, false);  // Don't take ownership

			// Add animation clips
			for (let clip in mFoxResource.Animations)
				skinnedMeshComp.AddAnimationClip(clip);

			// Set the mesh (uploads to GPU)
			skinnedMeshComp.SetMesh(mFoxResource.Mesh);

			// Set toon material
			if (mFoxMaterialInstance.IsValid)
				skinnedMeshComp.SetMaterial(mFoxMaterialInstance);

			// Start playing the run animation (if any)
			if (mFoxResource.AnimationCount > 0)
				skinnedMeshComp.PlayAnimation(0, true);

			Console.WriteLine("Fox entity created with Toon material");
		}

		// Create camera
		{
			mCameraEntity = mScene.CreateEntity("MainCamera");
			mCameraEntity.Transform.SetPosition(.(0, 3, 10));
			UpdateCameraDirection();

			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 500.0f, true);
			cameraComp.UseReverseZ = false;
			cameraComp.SetViewport(SwapChain.Width, SwapChain.Height);
			mCameraEntity.AddComponent(cameraComp);
		}

		if (mFoxResource != null)
			Console.WriteLine($"Created {mMaterialInstances.Count} toon-shaded objects + Fox with toon shading");
		else
			Console.WriteLine($"Created {mMaterialInstances.Count} toon-shaded objects");
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

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mContext.Update(deltaTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		mCurrentFrameIndex = frameIndex;

		// Begin render graph frame - adds shadow cascades and Scene3D passes
		mRendererService.BeginFrame(
			(uint32)frameIndex, DeltaTime, TotalTime,
			SwapChain.CurrentTexture, SwapChain.CurrentTextureView,
			mDepthTexture, DepthTextureView);
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Execute all render graph passes (shadow cascades, Scene3D)
		mRendererService.ExecuteFrame(encoder);
		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - OnRenderFrame handles rendering
	}

	protected override void OnCleanup()
	{
		Device.WaitIdle();

		// Release material instances
		if (mRendererService?.MaterialSystem != null)
		{
			for (let handle in mMaterialInstances)
				mRendererService.MaterialSystem.ReleaseInstance(handle);

			if (mGroundMaterial.IsValid)
				mRendererService.MaterialSystem.ReleaseInstance(mGroundMaterial);

			if (mFoxMaterialInstance.IsValid)
				mRendererService.MaterialSystem.ReleaseInstance(mFoxMaterialInstance);

			if (mToonMaterial.IsValid)
				mRendererService.MaterialSystem.ReleaseMaterial(mToonMaterial);
		}

		// Release Fox texture
		if (mFoxTexture.IsValid && mRendererService?.ResourceManager != null)
			mRendererService.ResourceManager.ReleaseTexture(mFoxTexture);

		mContext?.Shutdown();
		delete mRendererService;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let sample = scope RendererMaterialsCustomSample();
		return sample.Run();
	}
}
