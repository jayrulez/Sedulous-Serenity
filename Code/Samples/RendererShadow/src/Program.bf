namespace RendererShadow;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Framework.Renderer;
using Sedulous.Shell.Input;
using SampleFramework;

/// Per-instance data for GPU (80 bytes) - transform matrix + material
[CRepr]
struct ShadowInstanceData
{
	public Vector4 Row0;
	public Vector4 Row1;
	public Vector4 Row2;
	public Vector4 Row3;
	public Vector4 Material;  // x=metallic, y=roughness

	public this(Matrix transform, float metallic, float roughness)
	{
		Row0 = .(transform.M11, transform.M12, transform.M13, transform.M14);
		Row1 = .(transform.M21, transform.M22, transform.M23, transform.M24);
		Row2 = .(transform.M31, transform.M32, transform.M33, transform.M34);
		Row3 = .(transform.M41, transform.M42, transform.M43, transform.M44);
		Material = .(metallic, roughness, 0, 0);
	}
}

/// Camera uniform data
[CRepr]
struct CameraData
{
	public Matrix ViewProjection;
	public Matrix View;
	public Matrix Projection;
	public Vector3 CameraPosition;
	public float _pad0;
}

/// Shadow pass uniform data
[CRepr]
struct ShadowPassUniforms
{
	public Matrix LightViewProjection;
	public Vector4 DepthBias;
}

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

/// Per-frame GPU resources to avoid GPU/CPU synchronization issues.
/// Each frame in flight gets its own set of resources.
struct FrameResources
{
	public const int32 CASCADE_COUNT = 4;

	// Main pass resources
	public IBuffer CameraBuffer;
	public IBuffer InstanceBuffer;
	public IBindGroup BindGroup;

	// Debug line resources
	public IBuffer LineVertexBuffer;
	public IBindGroup LineBindGroup;

	// Shadow pass resources (one per cascade to avoid buffer overwrite during recording)
	public IBuffer[CASCADE_COUNT] ShadowUniformBuffers;
	public IBindGroup[CASCADE_COUNT] ShadowBindGroups;

	public void Dispose() mut
	{
		delete CameraBuffer;
		delete InstanceBuffer;
		delete BindGroup;
		delete LineVertexBuffer;
		delete LineBindGroup;
		for (int i = 0; i < CASCADE_COUNT; i++)
		{
			delete ShadowUniformBuffers[i];
			delete ShadowBindGroups[i];
		}
		this = default;
	}
}

class RendererShadowSample : RHISampleApp
{
	private const int32 MAX_INSTANCES = 16;
	private const int32 MAX_DEBUG_LINES = 100;
	private const int32 CASCADE_COUNT = FrameResources.CASCADE_COUNT;

	// Rendering resources (shared across frames)
	private IRenderPipeline mPipeline;
	private IBuffer mVertexBuffer;
	private IBuffer mIndexBuffer;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;

	// Per-frame resources
	private FrameResources[MAX_FRAMES_IN_FLIGHT] mFrameResources = .();

	// Debug line rendering (shared)
	private IRenderPipeline mLinePipeline;
	private IBindGroupLayout mLineBindGroupLayout;
	private IPipelineLayout mLinePipelineLayout;
	private List<LineVertex> mDebugLines = new .() ~ delete _;

	// Shadow rendering resources (shared)
	private IRenderPipeline mShadowPipeline;
	private IBindGroupLayout mShadowBindGroupLayout;
	private IPipelineLayout mShadowPipelineLayout;

	// Lighting system
	private LightingSystem mLightingSystem;
	private RenderWorld mRenderWorld;
	private ProxyHandle mDirLightHandle;

	// Light direction (spherical coordinates)
	private float mLightYaw = 0.5f;    // Horizontal angle
	private float mLightPitch = -0.7f; // Vertical angle (negative = pointing down)

	// Camera
	private Camera mCamera;
	private CameraProxy mCameraProxy;
	private List<LightProxy*> mLightProxies = new .() ~ delete _;
	private float mCameraYaw = 0.0f;
	private float mCameraPitch = 0.0f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 8.0f;
	private float mCameraLookSpeed = 0.003f;

	// Scene objects
	private List<Matrix> mObjectTransforms = new .() ~ delete _;
	private List<Vector2> mObjectMaterials = new .() ~ delete _;
	private ShadowInstanceData[] mInstanceData ~ delete _;
	private int32 mInstanceCount = 0;
	private int32 mIndexCount = 0;

	public this() : base(.()
	{
		Title = "Renderer Shadow - Debug Sample",
		Width = 1280,
		Height = 720,
		ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f),
		EnableDepth = true,
		DepthFormat = .Depth32Float
	})
	{
	}

	protected override bool OnInitialize()
	{
		mInstanceData = new ShadowInstanceData[MAX_INSTANCES];

		// Initialize camera - looking at origin from above
		mCamera = .();
		mCamera.Position = .(0, 8, 12);
		mCamera.Up = .(0, 1, 0);
		mCamera.FieldOfView = Math.PI_f / 4.0f;
		mCamera.NearPlane = 0.1f;
		mCamera.FarPlane = 100.0f;
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		mCameraYaw = Math.PI_f;
		mCameraPitch = -0.4f;
		UpdateCameraDirection();

		// Create systems
		mRenderWorld = new RenderWorld();
		mLightingSystem = new LightingSystem(Device);

		if (!CreateGeometry())
			return false;

		CreateScene();
		CreateLight();

		if (!CreateBuffers())
			return false;

		if (!CreatePipeline())
			return false;

		if (!CreateLinePipeline())
			return false;

		Console.WriteLine("Shadow Debug Sample initialized");
		Console.WriteLine("Controls:");
		Console.WriteLine("  WASD/QE = Camera movement");
		Console.WriteLine("  Right-click + Drag = Camera look");
		Console.WriteLine("  Arrow keys = Adjust light direction");
		Console.WriteLine("  Tab = Toggle mouse capture");

		return true;
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

	protected override void OnInput()
	{
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

		// Camera movement
		let forward = mCamera.Forward;
		let right = mCamera.Right;
		let up = Vector3(0, 1, 0);
		float speed = mCameraMoveSpeed * DeltaTime;

		if (keyboard.IsKeyDown(.W)) mCamera.Position = mCamera.Position + forward * speed;
		if (keyboard.IsKeyDown(.S)) mCamera.Position = mCamera.Position - forward * speed;
		if (keyboard.IsKeyDown(.A)) mCamera.Position = mCamera.Position - right * speed;
		if (keyboard.IsKeyDown(.D)) mCamera.Position = mCamera.Position + right * speed;
		if (keyboard.IsKeyDown(.Q)) mCamera.Position = mCamera.Position - up * speed;
		if (keyboard.IsKeyDown(.E)) mCamera.Position = mCamera.Position + up * speed;

		// Light direction control with arrow keys
		float lightSpeed = 1.0f * DeltaTime;
		bool lightChanged = false;

		if (keyboard.IsKeyDown(.Left))  { mLightYaw -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Right)) { mLightYaw += lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Up))    { mLightPitch -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Down))  { mLightPitch += lightSpeed; lightChanged = true; }

		// Clamp pitch to avoid light pointing up
		mLightPitch = Math.Clamp(mLightPitch, -Math.PI_f * 0.45f, -0.1f);

		// Update light direction if changed
		if (lightChanged)
		{
			if (let proxy = mRenderWorld.GetLightProxy(mDirLightHandle))
			{
				proxy.Direction = GetLightDirection();
			}
		}
	}

	private bool CreateGeometry()
	{
		// Simple cube
		float s = 0.5f;

		float[?] vertices = .(
			// Front face
			-s, -s,  s,   0, 0, 1,   0, 1,
			 s, -s,  s,   0, 0, 1,   1, 1,
			 s,  s,  s,   0, 0, 1,   1, 0,
			-s,  s,  s,   0, 0, 1,   0, 0,
			// Back face
			 s, -s, -s,   0, 0,-1,   0, 1,
			-s, -s, -s,   0, 0,-1,   1, 1,
			-s,  s, -s,   0, 0,-1,   1, 0,
			 s,  s, -s,   0, 0,-1,   0, 0,
			// Top face
			-s,  s,  s,   0, 1, 0,   0, 1,
			 s,  s,  s,   0, 1, 0,   1, 1,
			 s,  s, -s,   0, 1, 0,   1, 0,
			-s,  s, -s,   0, 1, 0,   0, 0,
			// Bottom face
			-s, -s, -s,   0,-1, 0,   0, 1,
			 s, -s, -s,   0,-1, 0,   1, 1,
			 s, -s,  s,   0,-1, 0,   1, 0,
			-s, -s,  s,   0,-1, 0,   0, 0,
			// Right face
			 s, -s,  s,   1, 0, 0,   0, 1,
			 s, -s, -s,   1, 0, 0,   1, 1,
			 s,  s, -s,   1, 0, 0,   1, 0,
			 s,  s,  s,   1, 0, 0,   0, 0,
			// Left face
			-s, -s, -s,  -1, 0, 0,   0, 1,
			-s, -s,  s,  -1, 0, 0,   1, 1,
			-s,  s,  s,  -1, 0, 0,   1, 0,
			-s,  s, -s,  -1, 0, 0,   0, 0
		);

		uint16[?] indices = .(
			 0,  1,  2,   2,  3,  0,
			 4,  5,  6,   6,  7,  4,
			 8,  9, 10,  10, 11,  8,
			12, 13, 14,  14, 15, 12,
			16, 17, 18,  18, 19, 16,
			20, 21, 22,  22, 23, 20
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
		else return false;

		// Create index buffer
		BufferDescriptor ibDesc = .((uint64)(indices.Count * sizeof(uint16)), .Index, .Upload);
		if (Device.CreateBuffer(&ibDesc) case .Ok(let ibuf))
		{
			mIndexBuffer = ibuf;
			Span<uint8> idata = .((uint8*)&indices, indices.Count * sizeof(uint16));
			Device.Queue.WriteBuffer(mIndexBuffer, 0, idata);
		}
		else return false;

		return true;
	}

	private void CreateScene()
	{
		// Ground plane (large flat cube)
		var planeScale = Matrix.CreateScale(.(20.0f, 0.2f, 20.0f));
		var planeTranslate = Matrix.CreateTranslation(.(0, -0.1f, 0));
		mObjectTransforms.Add(planeScale * planeTranslate);
		mObjectMaterials.Add(.(0.0f, 0.8f));

		// Cube 1 - left
		var cube1 = Matrix.CreateTranslation(.(-2.0f, 0.5f, 0.0f));
		mObjectTransforms.Add(cube1);
		mObjectMaterials.Add(.(0.0f, 0.3f));

		// Cube 2 - right
		var cube2 = Matrix.CreateTranslation(.(2.0f, 0.5f, 0.0f));
		mObjectTransforms.Add(cube2);
		mObjectMaterials.Add(.(0.0f, 0.3f));

		mInstanceCount = (int32)mObjectTransforms.Count;
	}

	private void CreateLight()
	{
		// Directional light with shadows
		mDirLightHandle = mRenderWorld.CreateDirectionalLight(
			GetLightDirection(),
			.(1.0f, 0.95f, 0.9f),
			1.0f
		);

		if (let proxy = mRenderWorld.GetLightProxy(mDirLightHandle))
		{
			proxy.CastsShadows = true;
			proxy.ShadowBias = 0.001f;
			proxy.ShadowNormalBias = 0.01f;
		}
	}

	private bool CreateBuffers()
	{
		// Create per-frame buffers to avoid GPU/CPU synchronization issues
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			// Camera buffer
			BufferDescriptor camDesc = .((uint64)sizeof(CameraData), .Uniform, .Upload);
			if (Device.CreateBuffer(&camDesc) case .Ok(let camBuf))
				mFrameResources[i].CameraBuffer = camBuf;
			else return false;

			// Instance buffer
			BufferDescriptor instDesc = .((uint64)(sizeof(ShadowInstanceData) * MAX_INSTANCES), .Vertex, .Upload);
			if (Device.CreateBuffer(&instDesc) case .Ok(let instBuf))
				mFrameResources[i].InstanceBuffer = instBuf;
			else return false;

			// Shadow uniform buffers (one per cascade to avoid overwrite during command recording)
			BufferDescriptor shadowDesc = .((uint64)sizeof(ShadowPassUniforms), .Uniform, .Upload);
			for (int32 c = 0; c < CASCADE_COUNT; c++)
			{
				if (Device.CreateBuffer(&shadowDesc) case .Ok(let shadowBuf))
					mFrameResources[i].ShadowUniformBuffers[c] = shadowBuf;
				else return false;
			}

			// Debug line buffer
			BufferDescriptor lineDesc = .((uint64)(sizeof(LineVertex) * MAX_DEBUG_LINES * 2), .Vertex, .Upload);
			if (Device.CreateBuffer(&lineDesc) case .Ok(let lineBuf))
				mFrameResources[i].LineVertexBuffer = lineBuf;
			else return false;
		}

		return true;
	}

	private bool CreatePipeline()
	{
		// Use the same shaders as RendererLighting
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "../RendererLighting/shaders/lighting");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout
		BindGroupLayoutEntry[7] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(2, .Fragment),
			BindGroupLayoutEntry.StorageBuffer(0, .Fragment),
			BindGroupLayoutEntry.UniformBuffer(3, .Fragment),
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2DArray),
			BindGroupLayoutEntry.SampledTexture(2, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);

		BindGroupLayoutDescriptor layoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&layoutDesc) case .Ok(let bindLayout))
			mBindGroupLayout = bindLayout;
		else return false;

		// Vertex attributes
		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),
			.(VertexFormat.Float3, 12, 1),
			.(VertexFormat.Float2, 24, 2)
		);

		Sedulous.RHI.VertexAttribute[5] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),
			.(VertexFormat.Float4, 16, 4),
			.(VertexFormat.Float4, 32, 5),
			.(VertexFormat.Float4, 48, 6),
			.(VertexFormat.Float4, 64, 7)
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
		else return false;

		// Depth state
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth32Float;

		// Render pipeline
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .() { Shader = .(vertShader, "main"), Buffers = vertexBuffers },
			Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .Back },
			DepthStencil = depthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
			mPipeline = pipeline;
		else return false;

		// Create per-frame bind groups using per-frame buffers from LightingSystem
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BindGroupEntry[7] bindGroupEntries = .(
				BindGroupEntry.Buffer(0, mFrameResources[i].CameraBuffer),
				BindGroupEntry.Buffer(2, mLightingSystem.GetLightingUniformBuffer((int32)i)),
				BindGroupEntry.Buffer(0, mLightingSystem.GetLightBuffer((int32)i)),
				BindGroupEntry.Buffer(3, mLightingSystem.GetShadowUniformBuffer((int32)i)),
				BindGroupEntry.Texture(1, mLightingSystem.CascadeShadowMapView),
				BindGroupEntry.Texture(2, mLightingSystem.ShadowAtlasView),
				BindGroupEntry.Sampler(0, mLightingSystem.ShadowSampler)
			);

			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
			if (Device.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
				mFrameResources[i].BindGroup = group;
			else return false;
		}

		// Shadow pipeline
		if (!CreateShadowPipeline())
			return false;

		return true;
	}

	private bool CreateShadowPipeline()
	{
		let shaderPath = "../../Sedulous/Sedulous.Framework.Renderer/shaders/shadow_depth_instanced.vert.hlsl";
		let shaderResult = ShaderUtils.LoadShader(Device, shaderPath, "main", .Vertex);
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load shadow shader");
			return false;
		}

		let shadowVertShader = shaderResult.Get();
		defer delete shadowVertShader;

		BindGroupLayoutEntry[1] shadowLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);

		BindGroupLayoutDescriptor shadowLayoutDesc = .(shadowLayoutEntries);
		if (Device.CreateBindGroupLayout(&shadowLayoutDesc) case .Ok(let bindLayout))
			mShadowBindGroupLayout = bindLayout;
		else return false;

		IBindGroupLayout[1] shadowBindGroupLayouts = .(mShadowBindGroupLayout);
		PipelineLayoutDescriptor shadowPipelineLayoutDesc = .(shadowBindGroupLayouts);
		if (Device.CreatePipelineLayout(&shadowPipelineLayoutDesc) case .Ok(let pipLayout))
			mShadowPipelineLayout = pipLayout;
		else return false;

		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),
			.(VertexFormat.Float3, 12, 1),
			.(VertexFormat.Float2, 24, 2)
		);

		Sedulous.RHI.VertexAttribute[5] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),
			.(VertexFormat.Float4, 16, 4),
			.(VertexFormat.Float4, 32, 5),
			.(VertexFormat.Float4, 48, 6),
			.(VertexFormat.Float4, 64, 7)
		);

		VertexBufferLayout[2] shadowVertexBuffers = .(
			.(32, meshAttrs, .Vertex),
			.(80, instanceAttrs, .Instance)
		);

		DepthStencilState shadowDepthState = .();
		shadowDepthState.DepthTestEnabled = true;
		shadowDepthState.DepthWriteEnabled = true;
		shadowDepthState.DepthCompare = .Less;
		shadowDepthState.Format = .Depth32Float;
		shadowDepthState.DepthBias = 2;
		shadowDepthState.DepthBiasSlopeScale = 2.0f;

		RenderPipelineDescriptor shadowPipelineDesc = .()
		{
			Layout = mShadowPipelineLayout,
			Vertex = .() { Shader = .(shadowVertShader, "main"), Buffers = shadowVertexBuffers },
			Fragment = null,
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .Front },
			DepthStencil = shadowDepthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&shadowPipelineDesc) case .Ok(let pipeline))
			mShadowPipeline = pipeline;
		else return false;

		// Create per-frame, per-cascade shadow bind groups
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			for (int32 c = 0; c < CASCADE_COUNT; c++)
			{
				let buffer = mFrameResources[i].ShadowUniformBuffers[c];
				BindGroupEntry[1] shadowBindGroupEntries = .(
					BindGroupEntry.Buffer(0, buffer)
				);
				BindGroupDescriptor shadowBindGroupDesc = .(mShadowBindGroupLayout, shadowBindGroupEntries);
				if (Device.CreateBindGroup(&shadowBindGroupDesc) case .Ok(let group))
					mFrameResources[i].ShadowBindGroups[c] = group;
				else return false;
			}
		}

		return true;
	}

	private bool CreateLinePipeline()
	{
		// Simple line shader - we'll create inline
		let vertCode = """
			#pragma pack_matrix(row_major)

			cbuffer Camera : register(b0) {
				float4x4 viewProjection;
				float4x4 view;
				float4x4 projection;
				float3 cameraPosition;
				float _pad0;
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
		lineDepthState.Format = .Depth32Float;

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

		// Create per-frame line bind groups
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BindGroupEntry[1] lineBindGroupEntries = .(
				BindGroupEntry.Buffer(0, mFrameResources[i].CameraBuffer)
			);
			BindGroupDescriptor lineBindGroupDesc = .(mLineBindGroupLayout, lineBindGroupEntries);
			if (Device.CreateBindGroup(&lineBindGroupDesc) case .Ok(let group))
				mFrameResources[i].LineBindGroup = group;
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
		let lightEnd = lightStart + lightDir * 5.0f;  // Extend in light direction

		// Yellow line for light direction
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

	/// Game logic update - no GPU buffer writes here (use OnPrepareFrame for that)
	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Update camera proxy
		mCameraProxy = CameraProxy.FromCamera(0, mCamera, SwapChain.Width, SwapChain.Height);
		mCameraProxy.IsMain = true;
		mCameraProxy.Enabled = true;

		// Gather light proxies
		mLightProxies.Clear();
		if (let proxy = mRenderWorld.GetLightProxy(mDirLightHandle))
			mLightProxies.Add(proxy);

		// Update debug visualization (builds line data, no GPU writes)
		UpdateDebugLines();
	}

	/// Called after fence wait - safe to write to per-frame GPU buffers here
	protected override void OnPrepareFrame(int32 frameIndex)
	{
		// Update lighting system with per-frame buffer support
		mLightingSystem.Update(&mCameraProxy, mLightProxies, frameIndex);
		mLightingSystem.PrepareShadows(&mCameraProxy);
		mLightingSystem.UploadShadowUniforms(frameIndex);

		// Update instance data to per-frame buffer
		for (int i = 0; i < mInstanceCount; i++)
			mInstanceData[i] = ShadowInstanceData(mObjectTransforms[i], mObjectMaterials[i].X, mObjectMaterials[i].Y);

		if (mInstanceCount > 0)
		{
			let dataSize = (uint64)(sizeof(ShadowInstanceData) * mInstanceCount);
			Span<uint8> data = .((uint8*)mInstanceData.Ptr, (int)dataSize);
			Device.Queue.WriteBuffer(mFrameResources[frameIndex].InstanceBuffer, 0, data);
		}

		// Update camera buffer (per-frame)
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
		Device.Queue.WriteBuffer(mFrameResources[frameIndex].CameraBuffer, 0, camSpan);

		// Upload debug lines to per-frame buffer
		if (mDebugLines.Count > 0)
		{
			let dataSize = (uint64)(mDebugLines.Count * sizeof(LineVertex));
			Span<uint8> data = .((uint8*)mDebugLines.Ptr, (int)dataSize);
			Device.Queue.WriteBuffer(mFrameResources[frameIndex].LineVertexBuffer, 0, data);
		}
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		if (mInstanceCount == 0 || !mLightingSystem.HasDirectionalShadows)
			return false;

		// Render shadow cascades (each cascade has its own buffer/bind group to avoid overwrite)
		for (int32 cascade = 0; cascade < LightingSystem.CASCADE_COUNT; cascade++)
		{
			let cascadeView = mLightingSystem.GetCascadeRenderView(cascade);
			if (cascadeView == null) continue;

			let cascadeData = mLightingSystem.GetCascadeData(cascade);

			var shadowUniforms = ShadowPassUniforms();
			shadowUniforms.LightViewProjection = cascadeData.ViewProjection;
			shadowUniforms.DepthBias = .(0.001f, 0.002f, 0, 0);
			Span<uint8> shadowSpan = .((uint8*)&shadowUniforms, sizeof(ShadowPassUniforms));

			let shadowBuffer = mFrameResources[frameIndex].ShadowUniformBuffers[cascade];
			if (shadowBuffer != null && Device.Queue != null)
				Device.Queue.WriteBuffer(shadowBuffer, 0, shadowSpan);

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
			if (shadowPass == null) continue;

			shadowPass.SetViewport(0, 0, LightingSystem.SHADOW_MAP_SIZE, LightingSystem.SHADOW_MAP_SIZE, 0, 1);
			shadowPass.SetScissorRect(0, 0, LightingSystem.SHADOW_MAP_SIZE, LightingSystem.SHADOW_MAP_SIZE);
			shadowPass.SetPipeline(mShadowPipeline);
			shadowPass.SetBindGroup(0, mFrameResources[frameIndex].ShadowBindGroups[cascade]);
			shadowPass.SetVertexBuffer(0, mVertexBuffer, 0);
			shadowPass.SetVertexBuffer(1, mFrameResources[frameIndex].InstanceBuffer, 0);
			shadowPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);
			shadowPass.DrawIndexed((uint32)mIndexCount, (uint32)mInstanceCount, 0, 0, 0);
			shadowPass.End();
			defer :: delete shadowPass;
		}

		// Transition shadow map from depth attachment to shader read
		if (let shadowMapTexture = mLightingSystem.CascadeShadowMapTexture)
			encoder.TextureBarrier(shadowMapTexture, .DepthStencilAttachment, .ShaderReadOnly);

		// Main render pass
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
		RenderPassDepthStencilAttachment mainDepthAttachment = .()
		{
			View = DepthTextureView,
			DepthLoadOp = .Clear,
			DepthStoreOp = .Store,
			DepthClearValue = 1.0f,
			StencilLoadOp = .Clear,
			StencilStoreOp = .Discard,
			StencilClearValue = 0
		};
		renderPassDesc.DepthStencilAttachment = mainDepthAttachment;

		let renderPass = encoder.BeginRenderPass(&renderPassDesc);
		if (renderPass == null) return true;

		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// Draw scene
		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mFrameResources[frameIndex].BindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.SetVertexBuffer(1, mFrameResources[frameIndex].InstanceBuffer, 0);
		renderPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);
		renderPass.DrawIndexed((uint32)mIndexCount, (uint32)mInstanceCount, 0, 0, 0);

		// Draw debug lines
		if (mDebugLines.Count > 0)
		{
			renderPass.SetPipeline(mLinePipeline);
			renderPass.SetBindGroup(0, mFrameResources[frameIndex].LineBindGroup);
			renderPass.SetVertexBuffer(0, mFrameResources[frameIndex].LineVertexBuffer, 0);
			renderPass.Draw((uint32)mDebugLines.Count, 1, 0, 0);
		}

		renderPass.End();
		delete renderPass;

		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we use OnRenderCustom
	}

	protected override void OnCleanup()
	{
		Device.WaitIdle();

		// Delete per-frame resources using FrameResources.Dispose()
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
			mFrameResources[i].Dispose();

		delete mLinePipeline;
		delete mLinePipelineLayout;
		delete mLineBindGroupLayout;

		delete mShadowPipeline;
		delete mShadowPipelineLayout;
		delete mShadowBindGroupLayout;

		delete mBindGroupLayout;
		delete mPipelineLayout;
		delete mPipeline;
		delete mIndexBuffer;
		delete mVertexBuffer;
		delete mLightingSystem;
		delete mRenderWorld;
	}
}

class Program
{
	public static void Main()
	{
		var app = scope RendererShadowSample();
		app.Run();
	}
}
