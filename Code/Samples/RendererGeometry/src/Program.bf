namespace RendererGeometry;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Framework.Renderer;
using Sedulous.Shell.Input;
using SampleFramework;

/// Basic geometry sample demonstrating:
/// - Static mesh rendering (procedural cubes)
/// - Skybox rendering
/// - First-person camera controls
class RendererGeometrySample : RHISampleApp
{
	// Renderer components
	private GPUResourceManager mResourceManager;
	private SkyboxRenderer mSkyboxRenderer;

	// Mesh resources
	private GPUMeshHandle mCubeMesh;
	private IBuffer mCameraUniformBuffer;
	private IBuffer mObjectUniformBuffer;
	private IBuffer mBlueCubeObjectBuffer;
	private ISampler mSampler;

	// Mesh pipeline
	private IBindGroupLayout mMeshBindGroupLayout;
	private IBindGroup mMeshBindGroup;
	private IBindGroup mBlueCubeBindGroup;
	private IPipelineLayout mMeshPipelineLayout;
	private IRenderPipeline mMeshPipeline;

	// Skybox pipeline
	private IBindGroupLayout mSkyboxBindGroupLayout;
	private IBindGroup mSkyboxBindGroup;
	private IPipelineLayout mSkyboxPipelineLayout;
	private IRenderPipeline mSkyboxPipeline;

	// Camera
	private Camera mCamera;
	private float mCameraYaw = 0.0f;
	private float mCameraPitch = 0.0f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 5.0f;
	private float mCameraLookSpeed = 0.003f;

	// Animation
	private float mCubeRotation = 0.0f;

	public this() : base(.()
	{
		Title = "Renderer Geometry - Basic Meshes",
		Width = 1024,
		Height = 768,
		ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f),
		EnableDepth = true
	})
	{
	}

	protected override bool OnInitialize()
	{
		mResourceManager = new GPUResourceManager(Device);

		// Setup camera
		mCamera = .();
		mCamera.Position = .(0, 2, 8);
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		mCameraYaw = Math.PI_f;
		mCameraPitch = -0.1f;
		UpdateCameraDirection();

		if (!CreateBuffers())
			return false;

		if (!CreateMesh())
			return false;

		if (!CreateSkybox())
			return false;

		if (!CreateMeshPipeline())
			return false;

		if (!CreateSkyboxPipeline())
			return false;

		Console.WriteLine("RendererGeometry sample initialized");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Right-click+Drag=Look, Tab=Toggle mouse capture");
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

	protected override void OnInput()
	{
		let keyboard = Shell.InputManager.Keyboard;
		let mouse = Shell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mCameraYaw -= mouse.DeltaX * mCameraLookSpeed;
			mCameraPitch -= mouse.DeltaY * mCameraLookSpeed;
			mCameraPitch = Math.Clamp(mCameraPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
			UpdateCameraDirection();
		}

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

		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
		{
			if (keyboard.IsKeyDown(.W)) mCamera.Position = mCamera.Position + forward * speed;
			if (keyboard.IsKeyDown(.S)) mCamera.Position = mCamera.Position - forward * speed;
			if (keyboard.IsKeyDown(.A)) mCamera.Position = mCamera.Position - right * speed;
			if (keyboard.IsKeyDown(.D)) mCamera.Position = mCamera.Position + right * speed;
			if (keyboard.IsKeyDown(.Q)) mCamera.Position = mCamera.Position - up * speed;
			if (keyboard.IsKeyDown(.E)) mCamera.Position = mCamera.Position + up * speed;
		}
	}

	private bool CreateBuffers()
	{
		BufferDescriptor cameraDesc = .(256, .Uniform, .Upload);
		if (Device.CreateBuffer(&cameraDesc) case .Ok(let buf))
			mCameraUniformBuffer = buf;
		else
			return false;

		BufferDescriptor objectDesc = .(128, .Uniform, .Upload);
		if (Device.CreateBuffer(&objectDesc) case .Ok(let objBuf))
			mObjectUniformBuffer = objBuf;
		else
			return false;

		BufferDescriptor blueCubeDesc = .(128, .Uniform, .Upload);
		if (Device.CreateBuffer(&blueCubeDesc) case .Ok(let blueBuf))
			mBlueCubeObjectBuffer = blueBuf;
		else
			return false;

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
		let cpuMesh = Mesh.CreateCube(1.0f);
		defer delete cpuMesh;

		mCubeMesh = mResourceManager.CreateMesh(cpuMesh);
		if (!mCubeMesh.IsValid)
		{
			Console.WriteLine("Failed to create cube mesh");
			return false;
		}

		Console.WriteLine("Cube mesh created");
		return true;
	}

	private bool CreateSkybox()
	{
		mSkyboxRenderer = new SkyboxRenderer(Device);

		let topColor = Color(70, 130, 200, 255);
		let bottomColor = Color(180, 210, 240, 255);

		if (!mSkyboxRenderer.CreateGradientSky(topColor, bottomColor, 32))
		{
			Console.WriteLine("Failed to create skybox");
			return false;
		}

		Console.WriteLine("Skybox created");
		return true;
	}

	private bool CreateMeshPipeline()
	{
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/simple_mesh");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load mesh shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		BindGroupLayoutEntry[2] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mMeshBindGroupLayout = layout;

		IBindGroupLayout[1] layouts = .(mMeshBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mMeshPipelineLayout = pipelineLayout;

		BindGroupEntry[2] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Buffer(1, mObjectUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mMeshBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mMeshBindGroup = group;

		BindGroupEntry[2] blueEntries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Buffer(1, mBlueCubeObjectBuffer)
		);
		BindGroupDescriptor blueBindGroupDesc = .(mMeshBindGroupLayout, blueEntries);
		if (Device.CreateBindGroup(&blueBindGroupDesc) not case .Ok(let blueGroup))
			return false;
		mBlueCubeBindGroup = blueGroup;

		Sedulous.RHI.VertexAttribute[3] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),
			.(VertexFormat.Float3, 12, 1),
			.(VertexFormat.Float2, 24, 2)
		);
		VertexBufferLayout[1] vertexBuffers = .(.(48, vertexAttrs));

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mMeshPipelineLayout,
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
			Console.WriteLine("Failed to create mesh pipeline");
			return false;
		}
		mMeshPipeline = pipeline;

		Console.WriteLine("Mesh pipeline created");
		return true;
	}

	private bool CreateSkyboxPipeline()
	{
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "../../Sedulous/Sedulous.Framework.Renderer/shaders/skybox");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load skybox shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .TextureCube),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mSkyboxBindGroupLayout = layout;

		IBindGroupLayout[1] layouts = .(mSkyboxBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mSkyboxPipelineLayout = pipelineLayout;

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Texture(0, mSkyboxRenderer.CubemapView),
			BindGroupEntry.Sampler(0, mSkyboxRenderer.Sampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mSkyboxBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mSkyboxBindGroup = group;

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .LessEqual;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSkyboxPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader, "main"),
				Buffers = .()
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
				CullMode = .None
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
			Console.WriteLine("Failed to create skybox pipeline");
			return false;
		}
		mSkyboxPipeline = pipeline;

		Console.WriteLine("Skybox pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mCubeRotation += deltaTime * 0.5f;

		var projection = mCamera.ProjectionMatrix;
		let view = mCamera.ViewMatrix;

		if (Device.FlipProjectionRequired)
			projection.M22 = -projection.M22;

		CameraUniforms cameraData = .();
		cameraData.ViewProjection = view * projection;
		cameraData.View = view;
		cameraData.Projection = projection;
		cameraData.CameraPosition = mCamera.Position;

		Span<uint8> camData = .((uint8*)&cameraData, sizeof(CameraUniforms));
		Device.Queue.WriteBuffer(mCameraUniformBuffer, 0, camData);

		let redCubeModel = Matrix.CreateRotationY(mCubeRotation) * Matrix.CreateTranslation(2.0f, 0.5f, 0);
		ObjectUniforms redCubeData = .();
		redCubeData.Model = redCubeModel;
		redCubeData.ObjectColor = .(1f, 0f, 0f, 1.0f);

		Span<uint8> redObjData = .((uint8*)&redCubeData, sizeof(ObjectUniforms));
		Device.Queue.WriteBuffer(mObjectUniformBuffer, 0, redObjData);

		let blueCubeModel = Matrix.CreateRotationY(-mCubeRotation) * Matrix.CreateTranslation(-2.0f, 0.5f, 0);
		ObjectUniforms blueCubeData = .();
		blueCubeData.Model = blueCubeModel;
		blueCubeData.ObjectColor = .(0f, 0.3f, 1f, 1.0f);

		Span<uint8> blueObjData = .((uint8*)&blueCubeData, sizeof(ObjectUniforms));
		Device.Queue.WriteBuffer(mBlueCubeObjectBuffer, 0, blueObjData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// Render skybox first
		if (mSkyboxPipeline != null && mSkyboxBindGroup != null && mSkyboxRenderer.IsValid)
		{
			renderPass.SetPipeline(mSkyboxPipeline);
			renderPass.SetBindGroup(0, mSkyboxBindGroup);
			renderPass.Draw(3, 1, 0, 0);
		}

		// Render cubes
		let mesh = mResourceManager.GetMesh(mCubeMesh);
		if (mesh != null)
		{
			renderPass.SetPipeline(mMeshPipeline);
			renderPass.SetVertexBuffer(0, mesh.VertexBuffer, 0);

			if (mesh.IndexBuffer != null)
				renderPass.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);

			// Red cube
			renderPass.SetBindGroup(0, mMeshBindGroup);
			if (mesh.IndexBuffer != null)
				renderPass.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
			else
				renderPass.Draw(mesh.VertexCount, 1, 0, 0);

			// Blue cube
			renderPass.SetBindGroup(0, mBlueCubeBindGroup);
			if (mesh.IndexBuffer != null)
				renderPass.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
			else
				renderPass.Draw(mesh.VertexCount, 1, 0, 0);
		}
	}

	protected override void OnCleanup()
	{
		if (mSkyboxPipeline != null) delete mSkyboxPipeline;
		if (mSkyboxPipelineLayout != null) delete mSkyboxPipelineLayout;
		if (mSkyboxBindGroup != null) delete mSkyboxBindGroup;
		if (mSkyboxBindGroupLayout != null) delete mSkyboxBindGroupLayout;

		if (mMeshPipeline != null) delete mMeshPipeline;
		if (mMeshPipelineLayout != null) delete mMeshPipelineLayout;
		if (mMeshBindGroup != null) delete mMeshBindGroup;
		if (mBlueCubeBindGroup != null) delete mBlueCubeBindGroup;
		if (mMeshBindGroupLayout != null) delete mMeshBindGroupLayout;

		if (mSampler != null) delete mSampler;
		if (mBlueCubeObjectBuffer != null) delete mBlueCubeObjectBuffer;
		if (mObjectUniformBuffer != null) delete mObjectUniformBuffer;
		if (mCameraUniformBuffer != null) delete mCameraUniformBuffer;

		if (mSkyboxRenderer != null) delete mSkyboxRenderer;

		if (mResourceManager != null)
		{
			mResourceManager.ReleaseMesh(mCubeMesh);
			delete mResourceManager;
		}
	}
}

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
	public Vector4 ObjectColor;
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RendererGeometrySample();
		return app.Run();
	}
}
