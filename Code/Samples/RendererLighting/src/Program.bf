namespace RendererLighting;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Framework.Renderer;
using Sedulous.Shell.Input;
using RHI.SampleFramework;

/// Per-instance data for GPU (80 bytes) - transform matrix + material
[CRepr]
struct LightingInstanceData
{
	public Vector4 Row0;      // Transform row 0 (M11, M12, M13, M14)
	public Vector4 Row1;      // Transform row 1 (M21, M22, M23, M24)
	public Vector4 Row2;      // Transform row 2 (M31, M32, M33, M34)
	public Vector4 Row3;      // Transform row 3 (M41, M42, M43, M44)
	public Vector4 Material;  // x=metallic, y=roughness, z=unused, w=unused

	public this(Matrix transform, float metallic, float roughness)
	{
		// Pass matrix rows - HLSL float4x4(v0,v1,v2,v3) treats each vector as a row
		Row0 = .(transform.M11, transform.M12, transform.M13, transform.M14);
		Row1 = .(transform.M21, transform.M22, transform.M23, transform.M24);
		Row2 = .(transform.M31, transform.M32, transform.M33, transform.M34);
		Row3 = .(transform.M41, transform.M42, transform.M43, transform.M44);
		Material = .(metallic, roughness, 0, 0);
	}
}

/// Camera uniform data - must match shader layout.
[CRepr]
struct CameraData
{
	public Matrix ViewProjection;
	public Matrix View;
	public Matrix Projection;
	public Vector3 CameraPosition;
	public float _pad0;
}

/// Shadow pass uniform data - light view-projection matrix.
[CRepr]
struct ShadowPassUniforms
{
	public Matrix LightViewProjection;
	public Vector4 DepthBias;  // x=constant bias, y=slope bias
}

class RendererLightingSample : RHISampleApp
{
	private const int32 MAX_INSTANCES = 256;

	// Rendering resources
	private IRenderPipeline mPipeline;
	private IBuffer mVertexBuffer;
	private IBuffer mIndexBuffer;
	private IBuffer mCameraBuffer;
	private IBuffer mInstanceBuffer;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;

	// Shadow rendering resources
	private IRenderPipeline mShadowPipeline;
	private IBindGroupLayout mShadowBindGroupLayout;
	private IPipelineLayout mShadowPipelineLayout;
	private IBuffer mShadowUniformBuffer;  // Per-pass light VP matrix
	private IBindGroup mShadowBindGroup;   // Shadow pass bind group (persistent)

	// Lighting system
	private LightingSystem mLightingSystem;
	private RenderWorld mRenderWorld;
	private List<ProxyHandle> mLightHandles = new .() ~ delete _;

	// Camera
	private Camera mCamera;
	private CameraProxy mCameraProxy;
	private float mCameraYaw = 0.0f;
	private float mCameraPitch = 0.0f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 8.0f;
	private float mCameraLookSpeed = 0.003f;

	// Scene objects - CPU side
	private List<Matrix> mObjectTransforms = new .() ~ delete _;
	private List<Vector2> mObjectMaterials = new .() ~ delete _;  // x=metallic, y=roughness
	private LightingInstanceData[] mInstanceData ~ delete _;
	private int32 mInstanceCount = 0;
	private int32 mIndexCount = 0;

	// Animation
	private float mTime = 0.0f;

	public this() : base(.()
	{
		Title = "Renderer Lighting - Clustered Forward",
		Width = 1280,
		Height = 720,
		ClearColor = .(0.02f, 0.02f, 0.05f, 1.0f),
		EnableDepth = true,
		DepthFormat = .Depth32Float
	})
	{
	}

	protected override bool OnInitialize()
	{
		// Allocate instance data
		mInstanceData = new LightingInstanceData[MAX_INSTANCES];

		// Initialize camera
		mCamera = .();
		mCamera.Position = .(0, 5, 15);
		mCamera.Up = .(0, 1, 0);
		mCamera.FieldOfView = Math.PI_f / 4.0f;
		mCamera.NearPlane = 0.1f;
		mCamera.FarPlane = 100.0f;
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		// Initialize yaw/pitch from a forward direction looking at center
		mCameraYaw = Math.PI_f;  // Looking toward -Z
		mCameraPitch = -0.2f;    // Slightly looking down
		UpdateCameraDirection();

		// Create render world and lighting system
		mRenderWorld = new RenderWorld();
		mLightingSystem = new LightingSystem(Device);

		if (!CreateGeometry())
			return false;

		CreateScene();
		CreateLights();

		if (!CreateBuffers())
			return false;

		if (!CreatePipeline())
			return false;

		Console.WriteLine($"Lighting sample initialized with {mObjectTransforms.Count} objects and {mLightHandles.Count} lights");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Right-click+Drag=Look, Tab=Toggle mouse capture");

		return true;
	}

	private void UpdateCameraDirection()
	{
		// Calculate forward direction from yaw and pitch
		float cosP = Math.Cos(mCameraPitch);
		mCamera.Forward = Vector3.Normalize(.(
			Math.Sin(mCameraYaw) * cosP,
			Math.Sin(mCameraPitch),
			Math.Cos(mCameraYaw) * cosP
		));
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

			// Clamp pitch to avoid gimbal lock
			mCameraPitch = Math.Clamp(mCameraPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);

			UpdateCameraDirection();
		}

		// Calculate movement vectors
		let forward = mCamera.Forward;
		let right = mCamera.Right;
		let up = Vector3(0, 1, 0);

		float speed = mCameraMoveSpeed * DeltaTime;

		// WASD movement
		if (keyboard.IsKeyDown(.W))
			mCamera.Position = mCamera.Position + forward * speed;
		if (keyboard.IsKeyDown(.S))
			mCamera.Position = mCamera.Position - forward * speed;
		if (keyboard.IsKeyDown(.A))
			mCamera.Position = mCamera.Position - right * speed;
		if (keyboard.IsKeyDown(.D))
			mCamera.Position = mCamera.Position + right * speed;

		// QE for up/down
		if (keyboard.IsKeyDown(.Q))
			mCamera.Position = mCamera.Position - up * speed;
		if (keyboard.IsKeyDown(.E))
			mCamera.Position = mCamera.Position + up * speed;

		// Shift to move faster
		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
		{
			// Already moved at normal speed, add extra
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
	}

	private bool CreateGeometry()
	{
		// Create a cube
		float s = 0.5f;

		float[?] vertices = .(
			// Position          Normal           UV
			// Front face
			-s, -s,  s,     0,  0,  1,     0, 1,
			 s, -s,  s,     0,  0,  1,     1, 1,
			 s,  s,  s,     0,  0,  1,     1, 0,
			-s,  s,  s,     0,  0,  1,     0, 0,
			// Back face
			 s, -s, -s,     0,  0, -1,     0, 1,
			-s, -s, -s,     0,  0, -1,     1, 1,
			-s,  s, -s,     0,  0, -1,     1, 0,
			 s,  s, -s,     0,  0, -1,     0, 0,
			// Top face
			-s,  s,  s,     0,  1,  0,     0, 1,
			 s,  s,  s,     0,  1,  0,     1, 1,
			 s,  s, -s,     0,  1,  0,     1, 0,
			-s,  s, -s,     0,  1,  0,     0, 0,
			// Bottom face
			-s, -s, -s,     0, -1,  0,     0, 1,
			 s, -s, -s,     0, -1,  0,     1, 1,
			 s, -s,  s,     0, -1,  0,     1, 0,
			-s, -s,  s,     0, -1,  0,     0, 0,
			// Right face
			 s, -s,  s,     1,  0,  0,     0, 1,
			 s, -s, -s,     1,  0,  0,     1, 1,
			 s,  s, -s,     1,  0,  0,     1, 0,
			 s,  s,  s,     1,  0,  0,     0, 0,
			// Left face
			-s, -s, -s,    -1,  0,  0,     0, 1,
			-s, -s,  s,    -1,  0,  0,     1, 1,
			-s,  s,  s,    -1,  0,  0,     1, 0,
			-s,  s, -s,    -1,  0,  0,     0, 0
		);

		uint16[?] indices = .(
			 0,  1,  2,   2,  3,  0, // Front
			 4,  5,  6,   6,  7,  4, // Back
			 8,  9, 10,  10, 11,  8, // Top
			12, 13, 14,  14, 15, 12, // Bottom
			16, 17, 18,  18, 19, 16, // Right
			20, 21, 22,  22, 23, 20  // Left
		);

		mIndexCount = indices.Count;

		// Create vertex buffer
		BufferDescriptor vbDesc = .((uint64)(vertices.Count * sizeof(float)), .Vertex, .Upload);
		if (Device.CreateBuffer(&vbDesc) case .Ok(let vbuf))
		{
			mVertexBuffer = vbuf;
			Span<uint8> vdata = .((uint8*)&vertices, vertices.Count * sizeof(float));
			Device.Queue.WriteBuffer(mVertexBuffer, 0, vdata);
		}
		else
			return false;

		// Create index buffer
		BufferDescriptor ibDesc = .((uint64)(indices.Count * sizeof(uint16)), .Index, .Upload);
		if (Device.CreateBuffer(&ibDesc) case .Ok(let ibuf))
		{
			mIndexBuffer = ibuf;
			Span<uint8> idata = .((uint8*)&indices, indices.Count * sizeof(uint16));
			Device.Queue.WriteBuffer(mIndexBuffer, 0, idata);
		}
		else
			return false;

		return true;
	}

	private void CreateScene()
	{
		// Add a large floor plane to receive shadows
		// Scale: 40x0.2x40, positioned so top surface is at y=0
		// Row-vector order: Scale * Translate (first scale, then translate)
		var floorScale = Matrix.CreateScale(.(40.0f, 0.2f, 40.0f));
		var floorTranslate = Matrix.CreateTranslation(.(0, -0.1f, 0));
		var floorTransform = floorScale * floorTranslate;
		mObjectTransforms.Add(floorTransform);
		mObjectMaterials.Add(.(0.0f, 0.8f));  // Non-metallic, rough floor

		// Create a grid of objects on the floor
		int gridSize = 5;
		float spacing = 2.5f;

		for (int z = -gridSize; z <= gridSize; z++)
		{
			for (int x = -gridSize; x <= gridSize; x++)
			{
				float xPos = x * spacing;
				float zPos = z * spacing;

				// Objects sitting on floor (y=0.5 so bottom is at y=0)
				var transform = Matrix.CreateTranslation(.(xPos, 0.5f, zPos));
				mObjectTransforms.Add(transform);

				// Vary materials across the grid
				float u = (float)(x + gridSize) / (gridSize * 2);
				float v = (float)(z + gridSize) / (gridSize * 2);

				mObjectMaterials.Add(.(u, Math.Max(0.1f, v)));  // metallic, roughness
			}
		}

		// Add some taller pillars at corners (good shadow casters)
		float[?] pillarPositions = .(-8, -8, 8, -8, -8, 8, 8, 8);
		for (int i = 0; i < 4; i++)
		{
			float px = pillarPositions[i * 2];
			float pz = pillarPositions[i * 2 + 1];

			// Stack cubes to make taller pillars
			for (int y = 0; y < 4; y++)
			{
				var transform = Matrix.CreateTranslation(.(px, y * 1.0f + 0.5f, pz));
				mObjectTransforms.Add(transform);
				mObjectMaterials.Add(.(0.0f, 0.3f));  // Non-metallic, smoother
			}
		}

		mInstanceCount = (int32)Math.Min(mObjectTransforms.Count, MAX_INSTANCES);
	}

	private void CreateLights()
	{
		// Create directional light (sun) - subtle ambient
		var dirLight = mRenderWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -0.7f, 0.3f)),
			.(1.0f, 0.95f, 0.9f),
			0.3f  // Lower intensity so point lights are more visible
		);
		// Enable shadows on directional light
		if (let proxy = mRenderWorld.GetLightProxy(dirLight))
		{
			proxy.CastsShadows = true;
			proxy.ShadowBias = 0.001f;
			proxy.ShadowNormalBias = 0.01f;
		}
		mLightHandles.Add(dirLight);

		// Create point lights in fixed positions around the scene
		// Positioned in a grid pattern so each light illuminates a section

		// Red light - front left
		var redLight = mRenderWorld.CreatePointLight(
			.(-6.0f, 2.5f, 6.0f),
			.(1.0f, 0.2f, 0.2f),
			4.0f,   // Intensity
			12.0f   // Range
		);
		mLightHandles.Add(redLight);

		// Green light - front right
		var greenLight = mRenderWorld.CreatePointLight(
			.(6.0f, 2.5f, 6.0f),
			.(0.2f, 1.0f, 0.2f),
			4.0f,
			12.0f
		);
		mLightHandles.Add(greenLight);

		// Blue light - back left
		var blueLight = mRenderWorld.CreatePointLight(
			.(-6.0f, 2.5f, -6.0f),
			.(0.2f, 0.2f, 1.0f),
			4.0f,
			12.0f
		);
		mLightHandles.Add(blueLight);

		// Yellow light - back right
		var yellowLight = mRenderWorld.CreatePointLight(
			.(6.0f, 2.5f, -6.0f),
			.(1.0f, 1.0f, 0.2f),
			4.0f,
			12.0f
		);
		mLightHandles.Add(yellowLight);

		// White light - center (brighter)
		var centerLight = mRenderWorld.CreatePointLight(
			.(0.0f, 3.0f, 0.0f),
			.(1.0f, 1.0f, 1.0f),
			5.0f,
			10.0f
		);
		mLightHandles.Add(centerLight);

		// Magenta light - left side
		var magentaLight = mRenderWorld.CreatePointLight(
			.(-8.0f, 2.5f, 0.0f),
			.(1.0f, 0.2f, 1.0f),
			4.0f,
			12.0f
		);
		mLightHandles.Add(magentaLight);

		// Cyan light - right side
		var cyanLight = mRenderWorld.CreatePointLight(
			.(8.0f, 2.5f, 0.0f),
			.(0.2f, 1.0f, 1.0f),
			4.0f,
			12.0f
		);
		mLightHandles.Add(cyanLight);
	}

	private bool CreateBuffers()
	{
		// Camera buffer
		BufferDescriptor camDesc = .((uint64)sizeof(CameraData), .Uniform, .Upload);
		if (Device.CreateBuffer(&camDesc) case .Ok(let camBuf))
			mCameraBuffer = camBuf;
		else
			return false;

		// Instance buffer
		BufferDescriptor instDesc = .((uint64)(sizeof(LightingInstanceData) * MAX_INSTANCES), .Vertex, .Upload);
		if (Device.CreateBuffer(&instDesc) case .Ok(let instBuf))
			mInstanceBuffer = instBuf;
		else
			return false;

		// Shadow pass uniform buffer (per-cascade light VP matrix)
		BufferDescriptor shadowUniformDesc = .((uint64)sizeof(ShadowPassUniforms), .Uniform, .Upload);
		if (Device.CreateBuffer(&shadowUniformDesc) case .Ok(let shadowBuf))
			mShadowUniformBuffer = shadowBuf;
		else
			return false;

		return true;
	}

	private bool CreatePipeline()
	{
		// Load shaders using ShaderUtils
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/lighting");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load lighting shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout:
		// b0 = Camera, b2 = Lighting uniforms, b3 = Shadow uniforms
		// t0 = Lights storage buffer, t1 = Cascade shadow map, t2 = Shadow atlas
		// s0 = Shadow comparison sampler
		BindGroupLayoutEntry[7] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),  // b0: Camera
			BindGroupLayoutEntry.UniformBuffer(2, .Fragment),            // b2: Lighting uniforms
			BindGroupLayoutEntry.StorageBuffer(0, .Fragment),            // t0: g_Lights
			BindGroupLayoutEntry.UniformBuffer(3, .Fragment),            // b3: Shadow uniforms
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2DArray),  // t1: Cascade shadow map
			BindGroupLayoutEntry.SampledTexture(2, .Fragment, .Texture2D),       // t2: Shadow atlas
			BindGroupLayoutEntry.Sampler(0, .Fragment)                   // s0: Shadow comparison sampler
		);

		BindGroupLayoutDescriptor layoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&layoutDesc) case .Ok(let bindLayout))
			mBindGroupLayout = bindLayout;
		else
			return false;

		// Vertex buffer 0: mesh data (32 bytes stride)
		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2)   // UV
		);

		// Vertex buffer 1: instance data (80 bytes stride)
		Sedulous.RHI.VertexAttribute[5] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),   // Col0 -> location 3
			.(VertexFormat.Float4, 16, 4),  // Col1 -> location 4
			.(VertexFormat.Float4, 32, 5),  // Col2 -> location 5
			.(VertexFormat.Float4, 48, 6),  // Col3 -> location 6
			.(VertexFormat.Float4, 64, 7)   // Material -> location 7
		);

		VertexBufferLayout[2] vertexBuffers = .(
			.(32, meshAttrs, .Vertex),
			.(80, instanceAttrs, .Instance)
		);

		// Pipeline layout
		IBindGroupLayout[1] bindGroupLayouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(bindGroupLayouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) case .Ok(let pipLayout))
			mPipelineLayout = pipLayout;
		else
			return false;

		// Color targets
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		// Depth state
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth32Float;

		// Render pipeline
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

		if (Device.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
			mPipeline = pipeline;
		else
			return false;

		// Create bind group with all resources
		BindGroupEntry[7] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mCameraBuffer),                              // b0: Camera
			BindGroupEntry.Buffer(2, mLightingSystem.LightingUniformBuffer),      // b2: Lighting uniforms
			BindGroupEntry.Buffer(0, mLightingSystem.LightBuffer),                // t0: g_Lights (storage buffer)
			BindGroupEntry.Buffer(3, mLightingSystem.ShadowUniformBuffer),        // b3: Shadow uniforms
			BindGroupEntry.Texture(1, mLightingSystem.CascadeShadowMapView),      // t1: Cascade shadow map
			BindGroupEntry.Texture(2, mLightingSystem.ShadowAtlasView),           // t2: Shadow atlas
			BindGroupEntry.Sampler(0, mLightingSystem.ShadowSampler)              // s0: Shadow comparison sampler
		);

		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
			mBindGroup = group;
		else
			return false;

		// Create shadow pipeline
		if (!CreateShadowPipeline())
			return false;

		return true;
	}

	private bool CreateShadowPipeline()
	{
		// Load shadow depth shader (instanced variant since we use instancing)
		// Path relative to renderer module where shadow shaders are defined
		let shaderPath = "../../Sedulous/Sedulous.Framework.Renderer/shaders/shadow_depth_instanced.vert.hlsl";
		let shaderResult = ShaderUtils.LoadShader(Device, shaderPath, "main", .Vertex);
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load shadow depth shader");
			return false;
		}

		let shadowVertShader = shaderResult.Get();
		defer delete shadowVertShader;

		// Shadow bind group layout - just the light VP uniform buffer at b0
		BindGroupLayoutEntry[1] shadowLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)  // b0: ShadowPassUniforms
		);

		BindGroupLayoutDescriptor shadowLayoutDesc = .(shadowLayoutEntries);
		if (Device.CreateBindGroupLayout(&shadowLayoutDesc) case .Ok(let bindLayout))
			mShadowBindGroupLayout = bindLayout;
		else
			return false;

		// Shadow pipeline layout
		IBindGroupLayout[1] shadowBindGroupLayouts = .(mShadowBindGroupLayout);
		PipelineLayoutDescriptor shadowPipelineLayoutDesc = .(shadowBindGroupLayouts);
		if (Device.CreatePipelineLayout(&shadowPipelineLayoutDesc) case .Ok(let pipLayout))
			mShadowPipelineLayout = pipLayout;
		else
			return false;

		// Vertex layout - same as main pipeline (position + normal + uv + instance matrix + material)
		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2)   // UV
		);

		Sedulous.RHI.VertexAttribute[5] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),   // instanceRow0 -> location 3
			.(VertexFormat.Float4, 16, 4),  // instanceRow1 -> location 4
			.(VertexFormat.Float4, 32, 5),  // instanceRow2 -> location 5
			.(VertexFormat.Float4, 48, 6),  // instanceRow3 -> location 6
			.(VertexFormat.Float4, 64, 7)   // Material -> location 7 (unused in shadow shader)
		);

		VertexBufferLayout[2] shadowVertexBuffers = .(
			.(32, meshAttrs, .Vertex),
			.(80, instanceAttrs, .Instance)
		);

		// Depth state for shadow pass
		DepthStencilState shadowDepthState = .();
		shadowDepthState.DepthTestEnabled = true;
		shadowDepthState.DepthWriteEnabled = true;
		shadowDepthState.DepthCompare = .Less;
		shadowDepthState.Format = .Depth32Float;
		// Depth bias to prevent shadow acne
		shadowDepthState.DepthBias = 2;
		shadowDepthState.DepthBiasSlopeScale = 2.0f;
		shadowDepthState.DepthBiasClamp = 0.0f;

		// Shadow render pipeline (depth-only, no fragment shader)
		RenderPipelineDescriptor shadowPipelineDesc = .()
		{
			Layout = mShadowPipelineLayout,
			Vertex = .()
			{
				Shader = .(shadowVertShader, "main"),
				Buffers = shadowVertexBuffers
			},
			Fragment = null,  // Depth-only pass
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Front  // Render back faces to reduce peter-panning
			},
			DepthStencil = shadowDepthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (Device.CreateRenderPipeline(&shadowPipelineDesc) case .Ok(let pipeline))
			mShadowPipeline = pipeline;
		else
			return false;

		// Create persistent shadow bind group
		BindGroupEntry[1] shadowBindGroupEntries = .(
			BindGroupEntry.Buffer(0, mShadowUniformBuffer)
		);
		BindGroupDescriptor shadowBindGroupDesc = .(mShadowBindGroupLayout, shadowBindGroupEntries);
		if (Device.CreateBindGroup(&shadowBindGroupDesc) case .Ok(let group))
			mShadowBindGroup = group;
		else
			return false;

		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mTime = totalTime;

		// Update camera proxy from current camera state
		mCameraProxy = CameraProxy.FromCamera(0, mCamera, SwapChain.Width, SwapChain.Height);
		mCameraProxy.IsMain = true;
		mCameraProxy.Enabled = true;

		// Gather light proxies for the lighting system
		List<LightProxy*> lightProxies = scope .();
		for (let handle in mLightHandles)
		{
			if (let proxy = mRenderWorld.GetLightProxy(handle))
				lightProxies.Add(proxy);
		}

		// Update lighting system
		mLightingSystem.Update(&mCameraProxy, lightProxies);

		// Prepare shadows (compute cascade matrices, allocate shadow tiles)
		mLightingSystem.PrepareShadows(&mCameraProxy);
		mLightingSystem.UploadShadowUniforms();

		// Build instance data
		for (int i = 0; i < mInstanceCount; i++)
		{
			mInstanceData[i] = LightingInstanceData(mObjectTransforms[i], mObjectMaterials[i].X, mObjectMaterials[i].Y);
		}

		// Upload instance data to GPU
		if (mInstanceCount > 0)
		{
			uint64 dataSize = (uint64)(sizeof(LightingInstanceData) * mInstanceCount);
			Span<uint8> data = .((uint8*)mInstanceData.Ptr, (int)dataSize);
			Device.Queue.WriteBuffer(mInstanceBuffer, 0, data);
		}

		// Update camera buffer with Y-flip for Vulkan
		var projection = mCameraProxy.ProjectionMatrix;
		if (Device.FlipProjectionRequired)
			projection.M22 = -projection.M22;

		var camData = CameraData()
		{
			ViewProjection = mCameraProxy.ViewMatrix * projection,
			View = mCameraProxy.ViewMatrix,
			Projection = projection,
			CameraPosition = mCamera.Position,
			_pad0 = 0
		};

		Span<uint8> camSpan = .((uint8*)&camData, sizeof(CameraData));
		Device.Queue.WriteBuffer(mCameraBuffer, 0, camSpan);
	}

	protected override bool OnRenderCustom(ICommandEncoder encoder)
	{
		if (mInstanceCount == 0 || !mLightingSystem.HasDirectionalShadows)
		{
			// No shadows to render, use default render path
			return false;
		}

		// Render shadow cascades
		RenderShadowCascades(encoder);

		// Transition shadow map from depth attachment to shader read for sampling
		if (let shadowMapTexture = mLightingSystem.CascadeShadowMapTexture)
			encoder.TextureBarrier(shadowMapTexture, .DepthStencilAttachment, .ShaderReadOnly);

		// Now render the main scene
		RenderMainPass(encoder);

		return true;  // We handled rendering ourselves
	}

	private void RenderShadowCascades(ICommandEncoder encoder)
	{
		// Render each cascade
		for (int32 cascade = 0; cascade < LightingSystem.CASCADE_COUNT; cascade++)
		{
			let cascadeView = mLightingSystem.GetCascadeRenderView(cascade);
			if (cascadeView == null)
				continue;

			// Get cascade VP matrix
			let cascadeData = mLightingSystem.GetCascadeData(cascade);

			// Upload shadow uniforms for this cascade
			var shadowUniforms = ShadowPassUniforms();
			shadowUniforms.LightViewProjection = cascadeData.ViewProjection;
			shadowUniforms.DepthBias = .(0.001f, 0.002f, 0, 0);
			Span<uint8> shadowUniformSpan = .((uint8*)&shadowUniforms, sizeof(ShadowPassUniforms));
			Device.Queue.WriteBuffer(mShadowUniformBuffer, 0, shadowUniformSpan);

			// Begin shadow render pass (depth-only)
			RenderPassDepthStencilAttachment depthAttachment = .()
			{
				View = cascadeView,
				DepthLoadOp = .Clear,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f,
				StencilLoadOp = .Clear,
				StencilStoreOp = .Discard,
				StencilClearValue = 0
			};

			RenderPassDescriptor passDesc = .();
			passDesc.DepthStencilAttachment = depthAttachment;

			let shadowPass = encoder.BeginRenderPass(&passDesc);
			if (shadowPass == null)
				continue;

			// Set viewport to cascade size
			shadowPass.SetViewport(0, 0, LightingSystem.SHADOW_MAP_SIZE, LightingSystem.SHADOW_MAP_SIZE, 0, 1);
			shadowPass.SetScissorRect(0, 0, LightingSystem.SHADOW_MAP_SIZE, LightingSystem.SHADOW_MAP_SIZE);

			// Set shadow pipeline and bind group
			shadowPass.SetPipeline(mShadowPipeline);
			shadowPass.SetBindGroup(0, mShadowBindGroup);
			shadowPass.SetVertexBuffer(0, mVertexBuffer, 0);
			shadowPass.SetVertexBuffer(1, mInstanceBuffer, 0);
			shadowPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);

			// Draw all instances to shadow map
			shadowPass.DrawIndexed((uint32)mIndexCount, (uint32)mInstanceCount, 0, 0, 0);

			shadowPass.End();
			delete shadowPass;
		}
	}

	private void RenderMainPass(ICommandEncoder encoder)
	{
		// Get swapchain texture
		let textureView = SwapChain.CurrentTextureView;
		if (textureView == null)
			return;

		// Begin main render pass
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = textureView,
			ResolveTarget = null,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = .(0.02f, 0.02f, 0.05f, 1.0f)
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
		if (renderPass == null)
			return;

		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// Set pipeline and bind group
		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.SetVertexBuffer(1, mInstanceBuffer, 0);
		renderPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);

		// Draw all instances
		renderPass.DrawIndexed((uint32)mIndexCount, (uint32)mInstanceCount, 0, 0, 0);

		renderPass.End();
		delete renderPass;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		if (mInstanceCount == 0)
			return;

		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// Set pipeline and bind group
		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.SetVertexBuffer(1, mInstanceBuffer, 0);
		renderPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);

		// Draw all instances
		renderPass.DrawIndexed((uint32)mIndexCount, (uint32)mInstanceCount, 0, 0, 0);
	}

	protected override void OnCleanup()
	{
		Device.WaitIdle();

		// Shadow resources
		if (mShadowBindGroup != null) delete mShadowBindGroup;
		if (mShadowPipeline != null) delete mShadowPipeline;
		if (mShadowPipelineLayout != null) delete mShadowPipelineLayout;
		if (mShadowBindGroupLayout != null) delete mShadowBindGroupLayout;
		if (mShadowUniformBuffer != null) delete mShadowUniformBuffer;

		// Main resources
		if (mBindGroup != null) delete mBindGroup;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mPipeline != null) delete mPipeline;
		if (mInstanceBuffer != null) delete mInstanceBuffer;
		if (mCameraBuffer != null) delete mCameraBuffer;
		if (mIndexBuffer != null) delete mIndexBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;
		if (mLightingSystem != null) delete mLightingSystem;
		if (mRenderWorld != null) delete mRenderWorld;
	}
}

class Program
{
	public static void Main()
	{
		var app = scope RendererLightingSample();
		app.Run();
	}
}
