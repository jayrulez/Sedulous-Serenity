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

	// Debug line rendering
	private const int32 MAX_DEBUG_LINES = 100;
	private IRenderPipeline mLinePipeline;
	private IBindGroupLayout mLineBindGroupLayout;
	private IPipelineLayout mLinePipelineLayout;
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mLineVertexBuffers;
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mLineUniformBuffers;
	private IBindGroup[MAX_FRAMES_IN_FLIGHT] mLineBindGroups;
	private List<LineVertex> mDebugLines = new .() ~ delete _;

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

		// Create debug line pipeline
		if (!CreateLinePipeline())
		{
			Console.WriteLine("Failed to create line pipeline");
			return false;
		}

		Console.WriteLine("Framework.Core + Renderer integration sample initialized");
		Console.WriteLine($"Created {GRID_SIZE * GRID_SIZE} cube entities with MeshRendererComponent");
		Console.WriteLine($"Created 4 particle emitters and 10 sprite entities");
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

		// Cycle through Fox animations with Space
		if (mFoxEntity != null && keyboard.IsKeyPressed(.Space))
		{
			if (let skinnedRenderer = mFoxEntity.GetComponent<SkinnedMeshRendererComponent>())
			{
				let animCount = (int32)skinnedRenderer.AnimationClips.Count;
				if (animCount > 0)
				{
					mCurrentAnimIndex = (mCurrentAnimIndex + 1) % animCount;
					skinnedRenderer.PlayAnimation(mCurrentAnimIndex, true);
					Console.WriteLine($"Playing animation: {skinnedRenderer.AnimationClips[mCurrentAnimIndex].Name}");
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

	private bool CreateLinePipeline()
	{
		// Simple line shader - compile inline
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
		{
			Console.WriteLine("Failed to compile line vertex shader");
			return false;
		}
		let lineVertShader = vertResult.Get();
		defer delete lineVertShader;

		let fragResult = ShaderUtils.CompileShader(Device, fragCode, "main", .Fragment);
		if (fragResult case .Err)
		{
			Console.WriteLine("Failed to compile line fragment shader");
			return false;
		}
		let lineFragShader = fragResult.Get();
		defer delete lineFragShader;

		// Line bind group layout - just camera buffer
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

		// Line vertex format
		Sedulous.RHI.VertexAttribute[2] lineAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float4, 12, 1)   // Color
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

		// Create per-frame line buffers and bind groups
		for (int32 i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			// Uniform buffer for camera VP
			BufferDescriptor uniformDesc = .((uint64)sizeof(Matrix), .Uniform, .Upload);
			if (Device.CreateBuffer(&uniformDesc) case .Ok(let uniformBuf))
				mLineUniformBuffers[i] = uniformBuf;
			else return false;

			// Vertex buffer for line vertices
			BufferDescriptor vertexDesc = .((uint64)(sizeof(LineVertex) * MAX_DEBUG_LINES * 2), .Vertex, .Upload);
			if (Device.CreateBuffer(&vertexDesc) case .Ok(let vertexBuf))
				mLineVertexBuffers[i] = vertexBuf;
			else return false;

			// Bind group
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

		// Draw light direction as a line from above origin
		let lightDir = GetLightDirection();
		let lightStart = Vector3(0, 5, 0);  // Start above ground

		// Draw XYZ axis at the light arrow start for reference
		let axisLength = 1.5f;

		// X axis - Red
		mDebugLines.Add(LineVertex(lightStart, .(1, 0, 0, 1)));
		mDebugLines.Add(LineVertex(lightStart + Vector3(axisLength, 0, 0), .(1, 0, 0, 1)));

		// Y axis - Green
		mDebugLines.Add(LineVertex(lightStart, .(0, 1, 0, 1)));
		mDebugLines.Add(LineVertex(lightStart + Vector3(0, axisLength, 0), .(0, 1, 0, 1)));

		// Z axis - Blue
		mDebugLines.Add(LineVertex(lightStart, .(0, 0, 1, 1)));
		mDebugLines.Add(LineVertex(lightStart + Vector3(0, 0, axisLength), .(0, 0, 1, 1)));

		// Yellow line for light direction
		let lightEnd = lightStart + lightDir * 5.0f;
		mDebugLines.Add(LineVertex(lightStart, .(1, 1, 0, 1)));
		mDebugLines.Add(LineVertex(lightEnd, .(1, 0.5f, 0, 1)));

		// Add arrow head
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

		// Update debug lines
		UpdateDebugLines();

		// Upload debug line vertices
		if (mDebugLines.Count > 0 && mLineVertexBuffers[frameIndex] != null)
		{
			let dataSize = (uint64)(mDebugLines.Count * sizeof(LineVertex));
			Span<uint8> data = .((uint8*)mDebugLines.Ptr, (int)dataSize);
			var buf = mLineVertexBuffers[frameIndex];// beef bug
			Device.Queue.WriteBuffer(buf, 0, data);
		}

		// Upload camera VP for debug lines
		if (mCameraEntity != null && mLineUniformBuffers[frameIndex] != null)
		{
			if (let cameraComp = mCameraEntity.GetComponent<CameraComponent>())
			{
				// Build view matrix from entity transform
				let camPos = mCameraEntity.Transform.WorldPosition;
				let camFwd = mCameraEntity.Transform.Forward;
				let camUp = mCameraEntity.Transform.Up;
				let viewMatrix = Matrix.CreateLookAt(camPos, camPos + camFwd, camUp);

				// Build projection matrix
				float aspectRatio = (float)cameraComp.ViewportWidth / (float)cameraComp.ViewportHeight;
				var projection = Matrix.CreatePerspectiveFieldOfView(cameraComp.FieldOfView, aspectRatio, cameraComp.NearPlane, cameraComp.FarPlane);

				if (Device.FlipProjectionRequired)
					projection.M22 = -projection.M22;

				var vp = viewMatrix * projection;
				Span<uint8> vpSpan = .((uint8*)&vp, sizeof(Matrix));
				var buf = mLineUniformBuffers[frameIndex];// beef bug
				Device.Queue.WriteBuffer(buf, 0, vpSpan);
			}
		}
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

		// Draw debug lines (light direction gizmo)
		if (mDebugLines.Count > 0 && mLinePipeline != null)
		{
			renderPass.SetPipeline(mLinePipeline);
			renderPass.SetBindGroup(0, mLineBindGroups[frameIndex]);
			renderPass.SetVertexBuffer(0, mLineVertexBuffers[frameIndex], 0);
			renderPass.Draw((uint32)mDebugLines.Count, 1, 0, 0);
		}

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

		// Clean up debug line rendering resources (must be before device is destroyed)
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
