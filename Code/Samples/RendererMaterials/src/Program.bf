namespace RendererMaterials;

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
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Renderer;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Debug;
using SampleFramework;
using Sedulous.Geometry.Resources;

/// Demonstrates the Material System integration.
/// Shows how to create PBR materials, material instances, and assign them to meshes.
class RendererMaterialsSample : RHISampleApp
{
	// Grid size for PBR spheres
	private const int32 GRID_SIZE = 5;

	// Framework.Core components
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;

	// Renderer components
	private RendererService mRendererService;
	private RenderSceneComponent mRenderSceneComponent;

	// Material handles
	private MaterialHandle mPBRMaterial = .Invalid;
	private List<MaterialInstanceHandle> mMaterialInstances = new .() ~ delete _;
	private MaterialInstanceHandle mGroundMaterial = .Invalid;

	// Fox (skinned mesh) resources
	private Model mFoxModel ~ delete _;
	private SkinnedMeshResource mFoxResource ~ delete _;
	private Entity mFoxEntity;
	private MaterialInstanceHandle mFoxMaterialInstance = .Invalid;
	private GPUTextureHandle mFoxTexture = .Invalid;

	// Camera entity and control
	private Entity mCameraEntity;
	private float mCameraYaw = Math.PI_f;
	private float mCameraPitch = -0.2f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 10.0f;
	private float mCameraLookSpeed = 0.003f;

	// Light direction control (spherical coordinates)
	private Entity mSunLightEntity;
	private float mLightYaw = 0.5f;
	private float mLightPitch = -0.7f;

	// Debug drawing
	private DebugDrawService mDebugDrawService;

	// Current frame index
	private int32 mCurrentFrameIndex = 0;

	public this() : base(.()
	{
		Title = "Material System Demo - PBR Materials",
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
		// Set formats to match swap chain BEFORE initializing
		mRendererService.SetFormats(SwapChain.Format, .Depth24PlusStencil8);
		let shaderPath = GetAssetPath("framework/shaders", .. scope .());
		if (mRendererService.Initialize(Device, scope StringView[](shaderPath)) case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}
		mContext.RegisterService<RendererService>(mRendererService);

		// Create and register DebugDrawService
		mDebugDrawService = new DebugDrawService();
		mContext.RegisterService<DebugDrawService>(mDebugDrawService);

		// Start context before creating scenes (enables automatic component creation)
		mContext.Startup();

		// Create scene - RenderSceneComponent is added automatically by RendererService
		mScene = mContext.SceneManager.CreateScene("MaterialScene");
		mRenderSceneComponent = mScene.GetSceneComponent<RenderSceneComponent>();
		mContext.SceneManager.SetActiveScene(mScene);

		// Load Fox model
		if (!LoadFox())
		{
			Console.WriteLine("Warning: Failed to load Fox model, continuing without it");
		}

		// Create materials and entities
		CreateMaterials();
		CreateEntities();

		Console.WriteLine("Material System Demo initialized");
		Console.WriteLine($"Created {GRID_SIZE * GRID_SIZE} spheres with varying metallic/roughness");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Tab=Toggle mouse capture, Shift=Fast");
		Console.WriteLine("          Arrow keys=Adjust light direction");

		return true;
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

		// Load Fox texture via ResourceManager
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

	private void CreateMaterials()
	{
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null)
		{
			Console.WriteLine("MaterialSystem not available!");
			return;
		}

		// Create a PBR material using the pbr_material shader
		let pbrMaterial = Material.CreatePBR("PBRMaterial");
		mPBRMaterial = materialSystem.RegisterMaterial(pbrMaterial);

		if (!mPBRMaterial.IsValid)
		{
			Console.WriteLine("Failed to register PBR material");
			return;
		}

		Console.WriteLine($"Created PBR material with {pbrMaterial.Parameters.Count} parameters");

		// Create material instances with varying metallic and roughness values
		for (int32 row = 0; row < GRID_SIZE; row++)
		{
			for (int32 col = 0; col < GRID_SIZE; col++)
			{
				let instanceHandle = materialSystem.CreateInstance(mPBRMaterial);
				if (!instanceHandle.IsValid)
				{
					Console.WriteLine("Failed to create material instance");
					continue;
				}

				let instance = materialSystem.GetInstance(instanceHandle);
				if (instance == null)
					continue;

				// Metallic varies along X axis (0.0 to 1.0)
				float metallic = (float)col / (float)(GRID_SIZE - 1);
				// Roughness varies along Z axis (0.1 to 1.0)
				float roughness = 0.1f + (float)row / (float)(GRID_SIZE - 1) * 0.9f;

				// Set material parameters
				instance.SetFloat4("baseColor", .(0.9f, 0.2f, 0.2f, 1.0f));  // Red base color
				instance.SetFloat("metallic", metallic);
				instance.SetFloat("roughness", roughness);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0, 0, 0, 1));

				// Upload to GPU
				materialSystem.UploadInstance(instanceHandle);

				mMaterialInstances.Add(instanceHandle);
			}
		}

		Console.WriteLine($"Created {mMaterialInstances.Count} material instances");

		// Create material instance for the Fox with texture
		if (mFoxResource != null)
		{
			mFoxMaterialInstance = materialSystem.CreateInstance(mPBRMaterial);
			if (mFoxMaterialInstance.IsValid)
			{
				let foxInstance = materialSystem.GetInstance(mFoxMaterialInstance);
				if (foxInstance != null)
				{
					// White base color to show texture correctly
					foxInstance.SetFloat4("baseColor", .(1.0f, 1.0f, 1.0f, 1.0f));
					foxInstance.SetFloat("metallic", 0.0f);   // Non-metallic (fur)
					foxInstance.SetFloat("roughness", 0.7f);  // Rough (fur-like)
					foxInstance.SetFloat("ao", 1.0f);
					foxInstance.SetFloat4("emissive", .(0, 0, 0, 1));

					// Set the albedo texture
					if (mFoxTexture.IsValid)
					{
						foxInstance.SetTexture("albedoMap", mFoxTexture);
						Console.WriteLine("Set Fox albedo texture on material");
					}

					materialSystem.UploadInstance(mFoxMaterialInstance);
					Console.WriteLine("Created Fox PBR material instance");
				}
			}
		}

		// Create material instance for the ground plane
		mGroundMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mGroundMaterial.IsValid)
		{
			let groundInstance = materialSystem.GetInstance(mGroundMaterial);
			if (groundInstance != null)
			{
				// Gray concrete-like ground
				groundInstance.SetFloat4("baseColor", .(0.4f, 0.4f, 0.4f, 1.0f));
				groundInstance.SetFloat("metallic", 0.0f);
				groundInstance.SetFloat("roughness", 0.9f);  // Very rough
				groundInstance.SetFloat("ao", 1.0f);
				groundInstance.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(mGroundMaterial);
				Console.WriteLine("Created ground PBR material instance");
			}
		}
	}

	private void CreateEntities()
	{
		// Create sphere mesh
		let sphereMesh = StaticMesh.CreateSphere(0.45f, 32, 16);
		defer delete sphereMesh;

		// Create ground plane
		let groundMesh = StaticMesh.CreateCube(1.0f);
		defer delete groundMesh;

		{
			let groundEntity = mScene.CreateEntity("Ground");
			groundEntity.Transform.SetPosition(.(0, -1.0f, 0));
			groundEntity.Transform.SetScale(.(30.0f, 0.2f, 30.0f));

			let meshComponent = new StaticMeshComponent();
			meshComponent.SetMaterialInstance(0, mGroundMaterial);
			meshComponent.MaterialCount = 1;
			groundEntity.AddComponent(meshComponent);
			meshComponent.SetMesh(groundMesh);
		}

		// Create grid of PBR spheres
		float spacing = 1.5f;
		float startX = -((GRID_SIZE - 1) * spacing) / 2.0f;
		float startZ = -((GRID_SIZE - 1) * spacing) / 2.0f;

		int32 instanceIndex = 0;
		for (int32 row = 0; row < GRID_SIZE; row++)
		{
			for (int32 col = 0; col < GRID_SIZE; col++)
			{
				if (instanceIndex >= mMaterialInstances.Count)
					break;

				float posX = startX + col * spacing;
				float posZ = startZ + row * spacing;

				let entity = mScene.CreateEntity(scope $"Sphere_{row}_{col}");
				entity.Transform.SetPosition(.(posX, 0.5f, posZ));

				let meshComponent = new StaticMeshComponent();
				// Set the material instance
				meshComponent.SetMaterialInstance(0, mMaterialInstances[instanceIndex]);
				meshComponent.MaterialCount = 1;
				entity.AddComponent(meshComponent);
				meshComponent.SetMesh(sphereMesh);

				instanceIndex++;
			}
		}

		// Create directional light
		{
			mSunLightEntity = mScene.CreateEntity("SunLight");
			mSunLightEntity.Transform.LookAt(GetLightDirection());

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.98f, 0.9f), 3.0f, true);
			mSunLightEntity.AddComponent(lightComp);
		}

		// Create point lights
		{
			let light1 = mScene.CreateEntity("PointLight1");
			light1.Transform.SetPosition(.(3, 3, 3));
			light1.AddComponent(LightComponent.CreatePoint(.(1.0f, 0.8f, 0.6f), 8.0f, 15.0f));

			let light2 = mScene.CreateEntity("PointLight2");
			light2.Transform.SetPosition(.(-3, 3, -3));
			light2.AddComponent(LightComponent.CreatePoint(.(0.6f, 0.8f, 1.0f), 8.0f, 15.0f));
		}

		// Create Fox skinned mesh with PBR material
		if (mFoxResource != null)
		{
			mFoxEntity = mScene.CreateEntity("Fox");
			// Position the fox to the right of the sphere grid, scale it down (it's big in native units)
			mFoxEntity.Transform.SetPosition(.(6.0f, -0.9f, 0.0f));
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

			// Set PBR material
			if (mFoxMaterialInstance.IsValid)
				skinnedMeshComp.SetMaterial(mFoxMaterialInstance);

			// Start playing the first animation (if any)
			if (mFoxResource.AnimationCount > 0)
				skinnedMeshComp.PlayAnimation(0, true);

			Console.WriteLine("Fox entity created with PBR material");
		}

		// Create camera
		{
			mCameraEntity = mScene.CreateEntity("MainCamera");
			mCameraEntity.Transform.SetPosition(.(0, 5, 12));
			UpdateCameraDirection();

			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 500.0f, true);
			cameraComp.UseReverseZ = false;
			cameraComp.SetViewport(SwapChain.Width, SwapChain.Height);
			mCameraEntity.AddComponent(cameraComp);
		}

		if (mFoxResource != null)
			Console.WriteLine($"Created {GRID_SIZE * GRID_SIZE} PBR spheres + ground + Fox");
		else
			Console.WriteLine($"Created {GRID_SIZE * GRID_SIZE} PBR spheres + ground");
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

		// Clamp pitch to avoid light pointing up
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

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mContext.Update(deltaTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		mCurrentFrameIndex = frameIndex;

		// Update debug drawing
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
		// Not used - OnRenderFrame handles rendering
	}

	private void UpdateDebugDrawing()
	{
		let lightDir = GetLightDirection();
		let lightStart = Vector3(0, 5, 0);
		let lightEnd = lightStart + lightDir * 5.0f;

		// Draw XYZ axes at light position
		mDebugDrawService.DrawAxes(lightStart, 1.5f);

		// Draw light direction line
		mDebugDrawService.DrawLine(lightStart, lightEnd, .(255, 255, 0, 255));

		// Draw arrow head
		let right = Vector3.Normalize(Vector3.Cross(lightDir, Vector3.Up));
		let up = Vector3.Normalize(Vector3.Cross(right, lightDir));
		let arrowSize = 0.3f;
		let arrowColor = Color(255, 128, 0, 255);

		mDebugDrawService.DrawLine(lightEnd, lightEnd - lightDir * arrowSize + right * arrowSize * 0.5f, arrowColor);
		mDebugDrawService.DrawLine(lightEnd, lightEnd - lightDir * arrowSize - right * arrowSize * 0.5f, arrowColor);
		mDebugDrawService.DrawLine(lightEnd, lightEnd - lightDir * arrowSize + up * arrowSize * 0.5f, arrowColor);
		mDebugDrawService.DrawLine(lightEnd, lightEnd - lightDir * arrowSize - up * arrowSize * 0.5f, arrowColor);
	}

	protected override void OnCleanup()
	{
		// Wait for GPU to finish before cleanup
		Device.WaitIdle();

		// Release material instances
		if (mRendererService?.MaterialSystem != null)
		{
			for (let handle in mMaterialInstances)
				mRendererService.MaterialSystem.ReleaseInstance(handle);

			if (mFoxMaterialInstance.IsValid)
				mRendererService.MaterialSystem.ReleaseInstance(mFoxMaterialInstance);

			if (mGroundMaterial.IsValid)
				mRendererService.MaterialSystem.ReleaseInstance(mGroundMaterial);

			if (mPBRMaterial.IsValid)
				mRendererService.MaterialSystem.ReleaseMaterial(mPBRMaterial);
		}

		// Release Fox texture
		if (mFoxTexture.IsValid && mRendererService?.ResourceManager != null)
			mRendererService.ResourceManager.ReleaseTexture(mFoxTexture);

		mContext?.Shutdown();

		// Services deleted in reverse order of creation
		delete mDebugDrawService;
		delete mRendererService;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let sample = scope RendererMaterialsSample();
		return sample.Run();
	}
}
