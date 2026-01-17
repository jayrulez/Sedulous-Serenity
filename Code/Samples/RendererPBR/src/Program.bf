namespace RendererPBR;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Imaging;
using Sedulous.Engine.Renderer;
using Sedulous.Renderer;
using Sedulous.Shaders;
using Sedulous.Shell.Input;
using SampleFramework;

/// PBR sphere sample using the Material System.
/// Demonstrates:
/// - ShaderLibrary for shader management
/// - Material/MaterialInstance for PBR rendering
/// - GPUResourceManager for mesh upload
class RendererPBRSample : RHISampleApp
{
	// Renderer components
	private ShaderLibrary mShaderLibrary;
	private GPUResourceManager mResourceManager;

	// GPU resources
	private GPUStaticMeshHandle mSphereMesh;
	private GPUTextureHandle mAlbedoTexture;
	private GPUTextureHandle mNormalTexture;
	private GPUTextureHandle mMetallicRoughnessTexture;
	private GPUTextureHandle mAOTexture;

	private IBuffer mCameraUniformBuffer;
	private IBuffer mObjectUniformBuffer;
	private IBuffer mMaterialUniformBuffer;
	private ISampler mSampler;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	// Shaders
	private ShaderModule mVertShader;
	private ShaderModule mFragShader;

	// Camera
	private Camera mCamera;

	// Camera control
	private float mCameraYaw = 0.0f;
	private float mCameraPitch = 0.0f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 5.0f;
	private float mCameraLookSpeed = 0.003f;

	// Animation state
	private float mRotationY = 0.0f;

	public this() : base(.(){ Title = "Renderer PBR Sample", Width = 1024, Height = 768, ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f), EnableDepth = true })
	{
	}

	protected override bool OnInitialize()
	{
		// Initialize renderer components
		mShaderLibrary = new ShaderLibrary();
		if(mShaderLibrary.Initialize(Device, "shaders") case .Err)
		{
			return false;
		}
		mResourceManager = new GPUResourceManager(Device);

		// Setup camera - use standard depth (not reverse-Z) since sample framework clears to 1.0
		mCamera = .();
		mCamera.Position = .(0, 0, 4);
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		// Initialize yaw/pitch from a forward direction looking at origin
		mCameraYaw = Math.PI_f;  // Looking toward -Z
		mCameraPitch = 0.0f;
		UpdateCameraDirection();

		if (!CreateMesh())
			return false;

		if (!CreateTextures())
			return false;

		if (!CreateBuffers())
			return false;

		if (!CreatePipeline())
			return false;

		Console.WriteLine("RendererPBR sample initialized");
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

	private bool CreateMesh()
	{
		// Create a sphere mesh
		let cpuMesh = StaticMesh.CreateSphere(0.8f, 48, 24);
		defer delete cpuMesh;

		mSphereMesh = mResourceManager.CreateStaticMesh(cpuMesh);
		if (!mSphereMesh.IsValid)
		{
			Console.WriteLine("Failed to create sphere mesh");
			return false;
		}

		Console.WriteLine("Sphere mesh created");
		return true;
	}

	private bool CreateTextures()
	{
		// Create simple procedural textures for PBR

		// Albedo - light gray/white
		let albedoImage = Image.CreateSolidColor(64, 64, .(220, 220, 225, 255));
		defer delete albedoImage;
		mAlbedoTexture = mResourceManager.CreateTexture(albedoImage);

		// Normal - flat normal map (pointing up)
		let normalImage = Image.CreateFlatNormalMap(64, 64);
		defer delete normalImage;
		mNormalTexture = mResourceManager.CreateTexture(normalImage);

		// Metallic/Roughness - packed as (unused, roughness, metallic, unused)
		// Roughness = 0.4, Metallic = 0.0 for a plastic-like material
		let mrImage = Image.CreateSolidColor(64, 64, .(0, 102, 0, 255)); // G=0.4*255, B=0
		defer delete mrImage;
		mMetallicRoughnessTexture = mResourceManager.CreateTexture(mrImage);

		// AO - white (no occlusion)
		let aoImage = Image.CreateSolidColor(64, 64, .White);
		defer delete aoImage;
		mAOTexture = mResourceManager.CreateTexture(aoImage);

		if (!mAlbedoTexture.IsValid || !mNormalTexture.IsValid ||
			!mMetallicRoughnessTexture.IsValid || !mAOTexture.IsValid)
		{
			Console.WriteLine("Failed to create textures");
			return false;
		}

		Console.WriteLine("Textures created");
		return true;
	}

	private bool CreateBuffers()
	{
		// Camera uniform buffer
		BufferDescriptor cameraDesc = .(256, .Uniform, .Upload); // Enough for camera data
		if (Device.CreateBuffer(&cameraDesc) case .Ok(let camBuf))
			mCameraUniformBuffer = camBuf;
		else
			return false;

		// Object uniform buffer (model matrix)
		BufferDescriptor objectDesc = .(256, .Uniform, .Upload);
		if (Device.CreateBuffer(&objectDesc) case .Ok(let objBuf))
			mObjectUniformBuffer = objBuf;
		else
			return false;

		// Material uniform buffer
		BufferDescriptor materialDesc = .(64, .Uniform, .Upload);
		if (Device.CreateBuffer(&materialDesc) case .Ok(let matBuf))
			mMaterialUniformBuffer = matBuf;
		else
			return false;

		// Create sampler
		SamplerDescriptor samplerDesc = .();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;
		samplerDesc.AddressModeU = .Repeat;
		samplerDesc.AddressModeV = .Repeat;
		if (Device.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mSampler = sampler;
		else
			return false;

		Console.WriteLine("Buffers and sampler created");
		return true;
	}

	private bool CreatePipeline()
	{
		// Load shaders - use simple shaders for now since PBR is complex
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/pbr_simple");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		Console.WriteLine("Shaders loaded");

		// Create bind group layout
		// Use HLSL register numbers directly - RHI applies internal shifts:
		// Buffers (bN): binding N
		// Textures (tN): binding N (RHI adds +1000 internally)
		// Samplers (sN): binding N (RHI adds +3000 internally)
		BindGroupLayoutEntry[5] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment), // b0
			BindGroupLayoutEntry.UniformBuffer(1, .Fragment),           // b1
			BindGroupLayoutEntry.UniformBuffer(2, .Vertex),             // b2
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),          // t0
			BindGroupLayoutEntry.Sampler(0, .Fragment)                  // s0
		);

		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		// Create bind group - use HLSL register numbers
		let albedoTex = mResourceManager.GetTexture(mAlbedoTexture);
		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),   // b0
			BindGroupEntry.Buffer(1, mMaterialUniformBuffer), // b1
			BindGroupEntry.Buffer(2, mObjectUniformBuffer),   // b2
			BindGroupEntry.Texture(0, albedoTex.View),        // t0
			BindGroupEntry.Sampler(0, mSampler)               // s0
		);

		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mBindGroup = group;

		// Vertex layout matching Geometry.Mesh common format:
		// Position (vec3): 12 bytes, Normal (vec3): 12, UV (vec2): 8, Color (uint32): 4, Tangent (vec3): 12
		// Total stride = 48 bytes
		Sedulous.RHI.VertexAttribute[3] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position at offset 0
			.(VertexFormat.Float3, 12, 1),  // Normal at offset 12
			.(VertexFormat.Float2, 24, 2)   // UV at offset 24
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.(48, vertexAttrs) // Stride = 48 bytes (common format)
		);

		// Color target with no blending (opaque)
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		// Depth state - must match RHISampleApp's DepthFormat (Depth24PlusStencil8)
		// Note: Sample framework clears depth to 1.0, so use standard .Less (not reverse-Z)
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		// Pipeline descriptor
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
				Mask = uint32.MaxValue,
				AlphaToCoverageEnabled = false
			}
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create pipeline");
			return false;
		}
		mPipeline = pipeline;

		// Clean up shader modules
		delete vertShader;
		delete fragShader;

		Console.WriteLine("Pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Rotate the sphere
		mRotationY += deltaTime * 0.5f;

		// Get camera matrices
		var projection = mCamera.ProjectionMatrix;
		let view = mCamera.ViewMatrix;

		// Flip Y for Vulkan's coordinate system
		if (Device.FlipProjectionRequired)
			projection.M22 = -projection.M22;

		// Update camera uniforms
		CameraUniforms cameraData = .();
		cameraData.ViewProjection = view * projection;
		cameraData.View = view;
		cameraData.Projection = projection;
		cameraData.CameraPosition = mCamera.Position;

		Span<uint8> camData = .((uint8*)&cameraData, sizeof(CameraUniforms));
		Device.Queue.WriteBuffer(mCameraUniformBuffer, 0, camData);

		// Update object uniforms
		let model = Matrix.CreateRotationY(mRotationY);
		ObjectUniforms objectData = .();
		objectData.Model = model;
		objectData.NormalMatrix = model; // Simplified, should be inverse transpose

		Span<uint8> objData = .((uint8*)&objectData, sizeof(ObjectUniforms));
		Device.Queue.WriteBuffer(mObjectUniformBuffer, 0, objData);

		// Update material uniforms
		MaterialUniforms materialData = .();
		materialData.BaseColor = .(0.9f, 0.9f, 0.95f, 1.0f);
		materialData.Metallic = 0.0f;
		materialData.Roughness = 0.4f;
		materialData.AO = 1.0f;
		materialData.Emissive = .Zero;

		Span<uint8> matData = .((uint8*)&materialData, sizeof(MaterialUniforms));
		Device.Queue.WriteBuffer(mMaterialUniformBuffer, 0, matData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		let mesh = mResourceManager.GetStaticMesh(mSphereMesh);
		if (mesh == null)
			return;

		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);
		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroup);
		renderPass.SetVertexBuffer(0, mesh.VertexBuffer, 0);

		if (mesh.IndexBuffer != null)
		{
			renderPass.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);
			renderPass.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
		}
		else
		{
			renderPass.Draw(mesh.VertexCount, 1, 0, 0);
		}
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroup != null) delete mBindGroup;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mSampler != null) delete mSampler;
		if (mMaterialUniformBuffer != null) delete mMaterialUniformBuffer;
		if (mObjectUniformBuffer != null) delete mObjectUniformBuffer;
		if (mCameraUniformBuffer != null) delete mCameraUniformBuffer;

		if (mResourceManager != null)
		{
			mResourceManager.ReleaseStaticMesh(mSphereMesh);
			mResourceManager.ReleaseTexture(mAlbedoTexture);
			mResourceManager.ReleaseTexture(mNormalTexture);
			mResourceManager.ReleaseTexture(mMetallicRoughnessTexture);
			mResourceManager.ReleaseTexture(mAOTexture);
			delete mResourceManager;
		}

		if (mShaderLibrary != null) delete mShaderLibrary;
	}
}

// Uniform buffer structures
[CRepr]
struct CameraUniforms
{
	public Matrix ViewProjection;
	public Matrix View;
	public Matrix Projection;
	public Vector3 CameraPosition;
	public float _pad0;
}

[CRepr]
struct ObjectUniforms
{
	public Matrix Model;
	public Matrix NormalMatrix;
}

[CRepr]
struct MaterialUniforms
{
	public Vector4 BaseColor;
	public float Metallic;
	public float Roughness;
	public float AO;
	public float _pad0;
	public Vector4 Emissive;
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RendererPBRSample();
		return app.Run();
	}
}
