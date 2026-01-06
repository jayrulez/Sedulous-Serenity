namespace RendererIntegrated;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Framework.Core;
using Sedulous.Framework.Renderer;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Console;
using Sedulous.Models;
using Sedulous.Imaging;
using SampleFramework;
using Sedulous.Logging.Debug;
using Sedulous.Geometry.Tooling;

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
		if (mRendererService.Initialize(Device, "../../Sedulous/Sedulous.Framework.Renderer/shaders") case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}
		mContext.RegisterService<RendererService>(mRendererService);

		// Create scene with RenderSceneComponent
		mScene = mContext.SceneManager.CreateScene("MainScene");
		mRenderSceneComponent = mScene.AddSceneComponent(new RenderSceneComponent(mRendererService));

		// Initialize rendering with output formats
		if (mRenderSceneComponent.InitializeRendering(SwapChain.Format, .Depth24PlusStencil8, Device.FlipProjectionRequired) case .Err)
		{
			Console.WriteLine("Failed to initialize scene rendering");
			return false;
		}

		// Create materials
		CreateMaterials();

		// Create all entities (cubes, lights, camera)
		CreateEntities();

		// Set active scene and start context
		mContext.SceneManager.SetActiveScene(mScene);
		mContext.Startup();

		Console.WriteLine("Framework.Core + Renderer integration sample initialized");
		Console.WriteLine($"Created {GRID_SIZE * GRID_SIZE} cube entities with MeshRendererComponent");
		Console.WriteLine($"Created 4 particle emitters and 10 sprite entities");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Tab=Toggle mouse capture, Shift=Fast");
		Console.WriteLine("          Left/Right or ,/. = Cycle Fox animations");

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
		let cubeMesh = Mesh.CreateCube(1.0f);
		defer delete cubeMesh;

		// Create ground plane (large flat cube)
		{
			let groundEntity = mScene.CreateEntity("Ground");
			groundEntity.Transform.SetPosition(.(0, -0.5f, 0));
			groundEntity.Transform.SetScale(.(50.0f, 1.0f, 50.0f));

			let meshRenderer = new MeshRendererComponent();
			groundEntity.AddComponent(meshRenderer);
			meshRenderer.SetMesh(cubeMesh);
			meshRenderer.SetMaterialInstance(0, mGroundMaterial);
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
				let meshRenderer = new MeshRendererComponent();
				entity.AddComponent(meshRenderer);

				// Now set the mesh - GPU upload happens automatically
				meshRenderer.SetMesh(cubeMesh);
				meshRenderer.SetMaterialInstance(0, mCubeMaterials[(x + z) % 8]);
			}
		}

		// Create directional light entity with shadows
		{
			let lightEntity = mScene.CreateEntity("SunLight");
			lightEntity.Transform.LookAt(.(-0.5f, -1.0f, -0.3f));

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.95f, 0.8f), 1.0f, true);  // Enable shadows
			lightEntity.AddComponent(lightComp);
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

		// Create 4 particle emitters at corners of ground
		{
			// Corner positions (ground is 50x50, so corners at ±20)
			Vector3[4] corners = .(
				.(-20, 0.5f, -20),
				.(20, 0.5f, -20),
				.(-20, 0.5f, 20),
				.(20, 0.5f, 20)
			);

			// Different color schemes for each corner
			Color[4] startColors = .(
				.(255, 100, 100, 255),  // Red
				.(100, 255, 100, 255),  // Green
				.(100, 100, 255, 255),  // Blue
				.(255, 255, 100, 255)   // Yellow
			);
			Color[4] endColors = .(
				.(255, 200, 50, 0),     // Red -> Orange
				.(50, 255, 200, 0),     // Green -> Cyan
				.(200, 50, 255, 0),     // Blue -> Purple
				.(255, 100, 200, 0)     // Yellow -> Pink
			);

			for (int i = 0; i < 4; i++)
			{
				let particleEntity = mScene.CreateEntity(scope $"ParticleFountain_{i}");
				particleEntity.Transform.SetPosition(corners[i]);

				var config = ParticleEmitterConfig.Default;
				config.EmissionRate = 100;
				config.MinVelocity = .(-1.5f, 6, -1.5f);
				config.MaxVelocity = .(1.5f, 10, 1.5f);
				config.MinLife = 1.5f;
				config.MaxLife = 2.5f;
				config.MinSize = 0.1f;
				config.MaxSize = 0.2f;
				config.StartColor = startColors[i];
				config.EndColor = endColors[i];
				config.Gravity = .(0, -12.0f, 0);

				let emitter = new ParticleEmitterComponent(config);
				particleEntity.AddComponent(emitter);
			}
		}

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
	}

	private void CreateFoxEntity()
	{
		// Load fox from cached resource
		let cachedPath = "models/Fox/Fox.skinnedmesh";

		if (File.Exists(cachedPath))
		{
			Console.WriteLine("Loading Fox from cached resource...");
			if (ResourceSerializer.LoadSkinnedMeshBundle(cachedPath) case .Ok(let resource))
			{
				mFoxResource = resource;
				Console.WriteLine($"Fox loaded: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.AnimationCount} animations");
			}
			else
			{
				Console.WriteLine("Failed to load Fox resource");
				return;
			}
		}
		else
		{
			Console.WriteLine($"Fox model not found: {cachedPath}");
			Console.WriteLine("Run RendererSkinned sample first to create the cached Fox model.");
			return;
		}

		// Create fox entity - position outside the cube grid
		mFoxEntity = mScene.CreateEntity("Fox");
		mFoxEntity.Transform.SetPosition(.(15, 0, 0));  // Outside cube grid (cubes span -12 to +9)
		mFoxEntity.Transform.SetScale(Vector3(0.05f));

		// Create skinned mesh renderer component
		let skinnedRenderer = new SkinnedMeshRendererComponent();
		mFoxEntity.AddComponent(skinnedRenderer);

		// Use the resource's skeleton directly (shared, not owned)
		if (mFoxResource.Skeleton != null)
			skinnedRenderer.SetSkeleton(mFoxResource.Skeleton);

		// Add animation clips from resource (shared references)
		for (let clip in mFoxResource.Animations)
			skinnedRenderer.AddAnimationClip(clip);

		// Set the mesh (triggers GPU upload)
		skinnedRenderer.SetMesh(mFoxResource.Mesh);

		// Load fox texture and set on material
		let texPath = "models/Fox/glTF/Texture.png";
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
			skinnedRenderer.SetMaterial(mFoxMaterial);

		// Start playing first animation
		if (skinnedRenderer.AnimationClips.Count > 0)
		{
			skinnedRenderer.PlayAnimation(0, true);
			Console.WriteLine($"Fox animation playing: {skinnedRenderer.AnimationClips[0].Name}");
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

		// Cycle through Fox animations
		if (mFoxEntity != null)
		{
			if (let skinnedRenderer = mFoxEntity.GetComponent<SkinnedMeshRendererComponent>())
			{
				let animCount = (int32)skinnedRenderer.AnimationClips.Count;
				if (animCount > 0)
				{
					if (keyboard.IsKeyPressed(.Right) || keyboard.IsKeyPressed(.Period))
					{
						mCurrentAnimIndex = (mCurrentAnimIndex + 1) % animCount;
						skinnedRenderer.PlayAnimation(mCurrentAnimIndex, true);
						Console.WriteLine($"Playing animation: {skinnedRenderer.AnimationClips[mCurrentAnimIndex].Name}");
					}
					if (keyboard.IsKeyPressed(.Left) || keyboard.IsKeyPressed(.Comma))
					{
						mCurrentAnimIndex = (mCurrentAnimIndex - 1 + animCount) % animCount;
						skinnedRenderer.PlayAnimation(mCurrentAnimIndex, true);
						Console.WriteLine($"Playing animation: {skinnedRenderer.AnimationClips[mCurrentAnimIndex].Name}");
					}
				}
			}
		}
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

		// Upload GPU data - this is called after fence wait, safe to write buffers
		mCurrentFrameIndex = frameIndex;
		mRenderSceneComponent.PrepareGPU(frameIndex);
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Render shadow passes first (before main render pass)
		mRenderSceneComponent.RenderShadows(encoder, frameIndex);

		// Create main render pass
		let textureView = SwapChain.CurrentTextureView;
		if (textureView == null) return true;

		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = textureView,
			ResolveTarget = null,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = .(0.1f, 0.1f, 0.15f, 1.0f)
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

		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// Render the scene - all GPU details handled by RenderSceneComponent
		mRenderSceneComponent.Render(renderPass, SwapChain.Width, SwapChain.Height);

		renderPass.End();
		return true;  // We handled rendering
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
