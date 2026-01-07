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
		let shaderPath = GetAssetPath("framework/shaders", .. scope .());
		if (mRendererService.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}
		mContext.RegisterService<RendererService>(mRendererService);

		// Create scene with RenderSceneComponent
		mScene = mContext.SceneManager.CreateScene("MaterialScene");
		mRenderSceneComponent = mScene.AddSceneComponent(new RenderSceneComponent(mRendererService));

		// Initialize rendering
		if (mRenderSceneComponent.InitializeRendering(SwapChain.Format, .Depth24PlusStencil8, Device.FlipProjectionRequired) case .Err)
		{
			Console.WriteLine("Failed to initialize scene rendering");
			return false;
		}

		// Load Fox model
		if (!LoadFox())
		{
			Console.WriteLine("Warning: Failed to load Fox model, continuing without it");
		}

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

		mContext?.Shutdown();
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
