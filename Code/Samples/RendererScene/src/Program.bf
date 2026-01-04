namespace RendererScene;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Framework.Renderer;
using RHI.SampleFramework;

/// Scene sample demonstrating:
/// - RenderWorld with proxy system
/// - Frustum culling with 1000+ objects
/// - GPU instancing for efficient rendering
class RendererSceneSample : RHISampleApp
{
	// Object counts
	private const int32 CUBE_GRID_SIZE = 20; // 20x20x3 = 1200 cubes
	private const int32 CUBE_LAYERS = 3;
	private const int32 MAX_INSTANCES = CUBE_GRID_SIZE * CUBE_GRID_SIZE * CUBE_LAYERS;

	// Renderer components
	private GPUResourceManager mResourceManager;
	private RenderWorld mRenderWorld;
	private VisibilityResolver mVisibilityResolver;

	// GPU Resources
	private GPUMeshHandle mCubeMesh;
	private IBuffer mCameraUniformBuffer;
	private IBuffer mInstanceBuffer;
	private ISampler mSampler;

	// Instance data (CPU side)
	private SceneInstanceData[] mInstanceData ~ delete _;
	private int32 mVisibleInstanceCount = 0;

	// Pipeline
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	// Mesh proxies
	private List<ProxyHandle> mCubeProxies = new .() ~ delete _;

	// Camera
	private Camera mCamera;
	private ProxyHandle mCameraHandle;

	// Lights
	private ProxyHandle mSunLight;
	private List<ProxyHandle> mPointLights = new .() ~ delete _;

	// Camera control
	private float mCameraYaw = Math.PI_f;  // Look toward -Z (toward the cubes)
	private float mCameraPitch = -0.3f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 20.0f;
	private float mCameraLookSpeed = 0.003f;

	// Animation
	private float mTime = 0.0f;

	// Stats display
	private float mStatTimer = 0.0f;
	private int32 mLastVisibleCount = 0;
	private int32 mLastCulledCount = 0;

	public this() : base(.(){ Title = "Renderer Scene Sample - 1000+ Objects", Width = 1280, Height = 720, ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f), EnableDepth = true })
	{
	}

	protected override bool OnInitialize()
	{
		// Initialize renderer components
		mResourceManager = new GPUResourceManager(Device);
		mRenderWorld = new RenderWorld();
		mVisibilityResolver = new VisibilityResolver();

		// Allocate instance data array
		mInstanceData = new SceneInstanceData[MAX_INSTANCES];

		// Setup camera
		mCamera = .();
		mCamera.Position = .(0, 15, 40);
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);
		UpdateCameraDirection();

		// Create camera proxy
		mCameraHandle = mRenderWorld.CreateCamera(mCamera, SwapChain.Width, SwapChain.Height, true);

		if (!CreateBuffers())
			return false;

		if (!CreateMesh())
			return false;

		if (!CreatePipeline())
			return false;

		if (!CreateScene())
			return false;

		Console.WriteLine($"Created {mCubeProxies.Count} cube proxies");
		Console.WriteLine($"Created {mPointLights.Count} point lights + 1 directional light");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Tab=Toggle mouse capture, Shift=Fast");

		return true;
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		mCamera.SetAspectRatio(width, height);
		if (let camera = mRenderWorld.GetCameraProxy(mCameraHandle))
		{
			camera.AspectRatio = mCamera.AspectRatio;
			camera.ViewportWidth = width;
			camera.ViewportHeight = height;
		}
	}

	private bool CreateBuffers()
	{
		// Camera uniform buffer (viewProjection + cameraPosition + padding = 80 bytes)
		BufferDescriptor cameraDesc = .(128, .Uniform, .Upload);
		if (Device.CreateBuffer(&cameraDesc) case .Ok(let buf))
			mCameraUniformBuffer = buf;
		else
			return false;

		// Instance buffer - per-instance transform (4x float4) + color (float4) = 80 bytes per instance
		uint64 instanceBufferSize = (uint64)(sizeof(SceneInstanceData) * MAX_INSTANCES);
		BufferDescriptor instanceDesc = .(instanceBufferSize, .Vertex, .Upload);
		if (Device.CreateBuffer(&instanceDesc) case .Ok(let instBuf))
			mInstanceBuffer = instBuf;
		else
			return false;

		// Sampler
		SamplerDescriptor samplerDesc = .();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		samplerDesc.AddressModeW = .ClampToEdge;
		if (Device.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mSampler = sampler;
		else
			return false;

		return true;
	}

	private bool CreateMesh()
	{
		// Create a cube mesh using factory method
		let cubeMesh = Mesh.CreateCube(1.0f);
		defer delete cubeMesh;

		mCubeMesh = mResourceManager.CreateMesh(cubeMesh);
		if (!mCubeMesh.IsValid)
		{
			Console.WriteLine("Failed to create cube mesh");
			return false;
		}

		Console.WriteLine("Cube mesh created");
		return true;
	}

	private bool CreateScene()
	{
		// Create sun light (directional)
		mSunLight = mRenderWorld.CreateDirectionalLight(
			.(-0.5f, -1.0f, -0.3f),  // Direction
			.(1.0f, 0.95f, 0.8f),    // Warm white color
			1.0f                      // Intensity
		);

		// Create a grid of cubes
		float spacing = 3.0f;
		float startOffset = -(CUBE_GRID_SIZE * spacing) / 2.0f;
		let cubeBounds = BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f));

		for (int32 layer = 0; layer < CUBE_LAYERS; layer++)
		{
			for (int32 x = 0; x < CUBE_GRID_SIZE; x++)
			{
				for (int32 z = 0; z < CUBE_GRID_SIZE; z++)
				{
					float posX = startOffset + x * spacing;
					float posY = layer * spacing;
					float posZ = startOffset + z * spacing;

					let transform = Matrix4x4.CreateTranslation(.(posX, posY, posZ));

					let handle = mRenderWorld.CreateMeshProxy(mCubeMesh, transform, cubeBounds);
					mCubeProxies.Add(handle);

					// Set material ID based on position for visual variety
					if (let proxy = mRenderWorld.GetMeshProxy(handle))
					{
						let materialId = (uint32)((x + z + layer) % 5);
						proxy.SetMaterial(0, materialId);
					}
				}
			}
		}

		// Add some point lights scattered around
		Random rng = scope .();
		for (int i = 0; i < 16; i++)
		{
			float px = ((float)rng.NextDouble() - 0.5f) * 50.0f;
			float py = (float)rng.NextDouble() * 10.0f + 2.0f;
			float pz = ((float)rng.NextDouble() - 0.5f) * 50.0f;

			Vector3 color = .(
				(float)rng.NextDouble() * 0.5f + 0.5f,
				(float)rng.NextDouble() * 0.5f + 0.5f,
				(float)rng.NextDouble() * 0.5f + 0.5f
			);

			let light = mRenderWorld.CreatePointLight(.(px, py, pz), color, 5.0f, 15.0f);
			mPointLights.Add(light);
		}

		return true;
	}

	private bool CreatePipeline()
	{
		// Load shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/scene");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load scene shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera only (instances come from vertex buffer)
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		// Bind group
		BindGroupEntry[1] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mBindGroup = group;

		// Vertex buffer 0: mesh data (48 bytes stride)
		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position -> location 0
			.(VertexFormat.Float3, 12, 1),  // Normal -> location 1
			.(VertexFormat.Float2, 24, 2)   // UV -> location 2
		);

		// Vertex buffer 1: instance data (80 bytes stride)
		Sedulous.RHI.VertexAttribute[5] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),   // Row0 -> location 3
			.(VertexFormat.Float4, 16, 4),  // Row1 -> location 4
			.(VertexFormat.Float4, 32, 5),  // Row2 -> location 5
			.(VertexFormat.Float4, 48, 6),  // Row3 -> location 6
			.(VertexFormat.Float4, 64, 7)   // Color -> location 7
		);

		VertexBufferLayout[2] vertexBuffers = .(
			.(48, meshAttrs, .Vertex),
			.(80, instanceAttrs, .Instance)
		);

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create scene pipeline");
			return false;
		}
		mPipeline = pipeline;

		Console.WriteLine("Scene pipeline created");
		return true;
	}

	protected override void OnInput()
	{
		let keyboard = Shell.InputManager.Keyboard;
		let mouse = Shell.InputManager.Mouse;

		// Toggle mouse capture with Tab
		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		// Mouse look (when captured or right-click held)
		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mCameraYaw -= mouse.DeltaX * mCameraLookSpeed;
			mCameraPitch -= mouse.DeltaY * mCameraLookSpeed;
			mCameraPitch = Math.Clamp(mCameraPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
			UpdateCameraDirection();
		}

		// WASD movement
		let forward = mCamera.Forward;
		let right = mCamera.Right;
		let up = Vector3(0, 1, 0);
		float speed = mCameraMoveSpeed * DeltaTime;

		// Shift for faster movement
		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
			speed *= 2.0f;

		if (keyboard.IsKeyDown(.W))
			mCamera.Position = mCamera.Position + forward * speed;
		if (keyboard.IsKeyDown(.S))
			mCamera.Position = mCamera.Position - forward * speed;
		if (keyboard.IsKeyDown(.A))
			mCamera.Position = mCamera.Position - right * speed;
		if (keyboard.IsKeyDown(.D))
			mCamera.Position = mCamera.Position + right * speed;
		if (keyboard.IsKeyDown(.Q))
			mCamera.Position = mCamera.Position - up * speed;
		if (keyboard.IsKeyDown(.E))
			mCamera.Position = mCamera.Position + up * speed;
	}

	private void UpdateCameraDirection()
	{
		float cosP = Math.Cos(mCameraPitch);
		mCamera.Forward = Vector3.Normalize(.(
			Math.Sin(mCameraYaw) * cosP,
			Math.Sin(mCameraPitch),
			Math.Cos(mCameraYaw) * cosP
		));
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mTime = totalTime;
		mStatTimer += deltaTime;

		// Update camera proxy
		if (let camera = mRenderWorld.GetCameraProxy(mCameraHandle))
		{
			camera.Position = mCamera.Position;
			camera.Forward = mCamera.Forward;
			camera.Up = mCamera.Up;
		}

		// Begin frame
		mRenderWorld.BeginFrame();

		// Skip animation for now - just use initial transforms

		// Resolve visibility (frustum culling)
		mVisibilityResolver.Resolve(mRenderWorld, mRenderWorld.MainCamera);

		// Build instance data from visible meshes
		mVisibleInstanceCount = 0;
		for (let proxy in mVisibilityResolver.OpaqueMeshes)
		{
			if (mVisibleInstanceCount >= MAX_INSTANCES)
				break;

			mInstanceData[mVisibleInstanceCount] = .(proxy.Transform, GetColorForMaterial(proxy.GetMaterial(0)));
			mVisibleInstanceCount++;
		}

		// Upload instance data to GPU
		if (mVisibleInstanceCount > 0)
		{
			uint64 dataSize = (uint64)(sizeof(SceneInstanceData) * mVisibleInstanceCount);
			Span<uint8> data = .((uint8*)mInstanceData.Ptr, (int)dataSize);
			Device.Queue.WriteBuffer(mInstanceBuffer, 0, data);
		}

		// Update stats periodically
		if (mStatTimer >= 1.0f)
		{
			mStatTimer = 0.0f;
			mLastVisibleCount = mVisibilityResolver.VisibleMeshCount;
			mLastCulledCount = mVisibilityResolver.CulledMeshCount;

			Console.WriteLine(scope $"Visible: {mLastVisibleCount} | Culled: {mLastCulledCount} | Instances: {mVisibleInstanceCount}");
		}

		// Update camera uniforms
		CameraUniforms cameraData = .();
		cameraData.ViewProjection = mCamera.ViewProjectionMatrix;
		cameraData.CameraPosition = mCamera.Position;

		Span<uint8> camData = .((uint8*)&cameraData, sizeof(CameraUniforms));
		Device.Queue.WriteBuffer(mCameraUniformBuffer, 0, camData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		if (mVisibleInstanceCount == 0)
			return;

		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// Get the GPU mesh
		let gpuMesh = mResourceManager.GetMesh(mCubeMesh);
		if (gpuMesh == null)
			return;

		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroup);
		renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
		renderPass.SetVertexBuffer(1, mInstanceBuffer, 0);

		if (gpuMesh.IndexBuffer != null)
		{
			renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
			renderPass.DrawIndexed(gpuMesh.IndexCount, (uint32)mVisibleInstanceCount, 0, 0, 0);
		}
		else
		{
			renderPass.Draw(gpuMesh.VertexCount, (uint32)mVisibleInstanceCount, 0, 0);
		}

		// End frame
		mRenderWorld.EndFrame();
	}

	private Vector4 GetColorForMaterial(uint32 materialId)
	{
		switch (materialId % 5)
		{
		case 0: return .(0.9f, 0.3f, 0.3f, 1.0f); // Red
		case 1: return .(0.3f, 0.9f, 0.3f, 1.0f); // Green
		case 2: return .(0.3f, 0.3f, 0.9f, 1.0f); // Blue
		case 3: return .(0.9f, 0.9f, 0.3f, 1.0f); // Yellow
		case 4: return .(0.9f, 0.3f, 0.9f, 1.0f); // Magenta
		default: return .(1.0f, 1.0f, 1.0f, 1.0f);
		}
	}

	protected override void OnCleanup()
	{
		mRenderWorld?.Clear();

		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroup != null) delete mBindGroup;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mSampler != null) delete mSampler;
		if (mInstanceBuffer != null) delete mInstanceBuffer;
		if (mCameraUniformBuffer != null) delete mCameraUniformBuffer;

		if (mResourceManager != null)
		{
			mResourceManager.ReleaseMesh(mCubeMesh);
			delete mResourceManager;
		}

		delete mRenderWorld;
		delete mVisibilityResolver;
	}
}

// Per-instance data uploaded to GPU (80 bytes)
[CRepr]
struct SceneInstanceData
{
	public Vector4 Col0;  // Transform matrix column 0
	public Vector4 Col1;  // Transform matrix column 1
	public Vector4 Col2;  // Transform matrix column 2
	public Vector4 Col3;  // Transform matrix column 3 (translation in XYZ)
	public Vector4 Color; // Instance color

	public this(Matrix4x4 transform, Vector4 color)
	{
		// Extract columns from column-major matrix
		Col0 = .(transform.M11, transform.M21, transform.M31, transform.M41);
		Col1 = .(transform.M12, transform.M22, transform.M32, transform.M42);
		Col2 = .(transform.M13, transform.M23, transform.M33, transform.M43);
		Col3 = .(transform.M14, transform.M24, transform.M34, transform.M44);
		Color = color;
	}
}

// Camera uniform buffer - must match shader layout exactly
[CRepr]
struct CameraUniforms
{
	public Matrix4x4 ViewProjection;
	public Vector3 CameraPosition;
	public float _pad0;
}

class Program
{
	public static int Main(String[] args)
	{
		let sample = scope RendererSceneSample();
		return sample.Run();
	}
}
