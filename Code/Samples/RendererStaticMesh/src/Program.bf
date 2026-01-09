namespace RendererStaticMesh;

using System;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Engine.Renderer;
using Sedulous.Shell.Input;
using SampleFramework;

/// Static mesh sample demonstrating:
/// - GLTF model loading (Duck)
/// - Textured mesh rendering
/// - Skybox background
/// - First-person camera controls
class RendererStaticMeshSample : RHISampleApp
{
	// Renderer components
	private SkyboxRenderer mSkyboxRenderer;

	// GLTF Model resources
	private Model mDuckModel;
	private IBuffer mDuckVertexBuffer;
	private IBuffer mDuckIndexBuffer;
	private ITexture mDuckTexture;
	private ITextureView mDuckTextureView;
	private int32 mDuckIndexCount;
	private bool mDuckUse32BitIndices;
	private int32 mDuckVertexStride;

	// Common resources
	private IBuffer mCameraUniformBuffer;
	private IBuffer mObjectUniformBuffer;
	private ISampler mSampler;

	// GLTF pipeline
	private IBindGroupLayout mGltfBindGroupLayout;
	private IBindGroup mGltfBindGroup;
	private IPipelineLayout mGltfPipelineLayout;
	private IRenderPipeline mGltfPipeline;

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
	private float mModelRotation = 0.0f;

	public this() : base(.()
	{
		Title = "Renderer Static Mesh - GLTF Duck",
		Width = 1024,
		Height = 768,
		ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f),
		EnableDepth = true
	})
	{
	}

	protected override bool OnInitialize()
	{
		// Setup camera
		mCamera = .();
		mCamera.Position = .(0, 1, 3);
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		mCameraYaw = Math.PI_f;
		mCameraPitch = -0.1f;
		UpdateCameraDirection();

		if (!CreateBuffers())
			return false;

		if (!CreateSkybox())
			return false;

		if (!LoadGltfModel())
			return false;

		if (!CreateSkyboxPipeline())
			return false;

		if (!CreateGltfPipeline())
			return false;

		Console.WriteLine("RendererStaticMesh sample initialized");
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

	private bool LoadGltfModel()
	{
		mDuckModel = new Model();
		let loader = scope GltfLoader();

		let modelPath = GetAssetPath("samples/models/Duck/glTF/Duck.gltf", .. scope .());
		let result = loader.Load(modelPath, mDuckModel);
		if (result != .Ok)
		{
			Console.WriteLine(scope $"Failed to load Duck model: {result}");
			delete mDuckModel;
			mDuckModel = null;
			return false;
		}

		Console.WriteLine(scope $"Duck model loaded: {mDuckModel.Meshes.Count} meshes, {mDuckModel.Materials.Count} materials, {mDuckModel.Textures.Count} textures");

		// Create GPU buffers from first mesh
		if (mDuckModel.Meshes.Count > 0)
		{
			let mesh = mDuckModel.Meshes[0];

			// Vertex buffer
			let vertexDataSize = (uint64)mesh.GetVertexDataSize();
			BufferDescriptor vertexDesc = .(vertexDataSize, .Vertex, .Upload);
			if (Device.CreateBuffer(&vertexDesc) case .Ok(let vb))
			{
				mDuckVertexBuffer = vb;
				Span<uint8> data = .(mesh.GetVertexData(), mesh.GetVertexDataSize());
				Device.Queue.WriteBuffer(mDuckVertexBuffer, 0, data);
			}
			else
			{
				Console.WriteLine("Failed to create duck vertex buffer");
				return false;
			}

			// Index buffer
			let indexDataSize = (uint64)mesh.GetIndexDataSize();
			BufferDescriptor indexDesc = .(indexDataSize, .Index, .Upload);
			if (Device.CreateBuffer(&indexDesc) case .Ok(let ib))
			{
				mDuckIndexBuffer = ib;
				Span<uint8> data = .(mesh.GetIndexData(), mesh.GetIndexDataSize());
				Device.Queue.WriteBuffer(mDuckIndexBuffer, 0, data);
			}
			else
			{
				Console.WriteLine("Failed to create duck index buffer");
				return false;
			}

			mDuckIndexCount = mesh.IndexCount;
			mDuckUse32BitIndices = mesh.Use32BitIndices;
			mDuckVertexStride = mesh.VertexStride;

			Console.WriteLine(scope $"Duck mesh: {mesh.VertexCount} vertices, {mesh.IndexCount} indices, stride={mesh.VertexStride}");
		}

		// Load texture from model's embedded data (decoded by GLTF loader)
		if (mDuckModel.Textures.Count > 0)
		{
			let tex = mDuckModel.Textures[0];

			if (tex.HasEmbeddedData && tex.Width > 0 && tex.Height > 0)
			{
				Console.WriteLine(scope $"Using embedded texture: {tex.Width}x{tex.Height}, format={tex.PixelFormat}");

				// Convert pixel format to texture format
				TextureFormat texFormat = .RGBA8Unorm;
				uint32 bytesPerPixel = 4;
				switch (tex.PixelFormat)
				{
				case .RGBA8: texFormat = .RGBA8Unorm; bytesPerPixel = 4;
				case .RGB8: texFormat = .RGBA8Unorm; bytesPerPixel = 4; // Note: data should be RGBA from decoder
				case .BGRA8: texFormat = .BGRA8Unorm; bytesPerPixel = 4;
				default: texFormat = .RGBA8Unorm; bytesPerPixel = 4;
				}

				TextureDescriptor texDesc = .Texture2D((uint32)tex.Width, (uint32)tex.Height, texFormat, .Sampled | .CopyDst);
				if (Device.CreateTexture(&texDesc) case .Ok(let texture))
				{
					mDuckTexture = texture;

					TextureDataLayout layout = .()
					{
						Offset = 0,
						BytesPerRow = (uint32)tex.Width * bytesPerPixel,
						RowsPerImage = (uint32)tex.Height
					};
					Extent3D size = .((uint32)tex.Width, (uint32)tex.Height, 1);
					Span<uint8> data = .(tex.GetData(), tex.GetDataSize());
					Device.Queue.WriteTexture(mDuckTexture, data, &layout, &size, 0, 0);

					TextureViewDescriptor viewDesc = .();
					viewDesc.Format = texFormat;
					viewDesc.Dimension = .Texture2D;
					viewDesc.MipLevelCount = 1;
					viewDesc.ArrayLayerCount = 1;

					if (Device.CreateTextureView(mDuckTexture, &viewDesc) case .Ok(let view))
						mDuckTextureView = view;
				}
			}
			else
			{
				Console.WriteLine("No embedded texture data, texture loading skipped");
			}
		}

		// Create fallback white texture if needed
		if (mDuckTextureView == null)
		{
			Console.WriteLine("Creating fallback white texture");
			TextureDescriptor texDesc = .Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);
			if (Device.CreateTexture(&texDesc) case .Ok(let texture))
			{
				mDuckTexture = texture;
				uint8[4] white = .(255, 255, 255, 255);
				TextureDataLayout layout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
				Extent3D size = .(1, 1, 1);
				Span<uint8> data = .(&white, 4);
				Device.Queue.WriteTexture(mDuckTexture, data, &layout, &size, 0, 0);

				TextureViewDescriptor viewDesc = .();
				viewDesc.Format = .RGBA8Unorm;
				viewDesc.Dimension = .Texture2D;
				viewDesc.MipLevelCount = 1;
				viewDesc.ArrayLayerCount = 1;

				if (Device.CreateTextureView(mDuckTexture, &viewDesc) case .Ok(let view))
					mDuckTextureView = view;
			}
		}

		return true;
	}

	private bool CreateSkyboxPipeline()
	{
		let shaderPath = GetAssetPath("framework/shaders/skybox", .. scope .());
		let shaderResult = ShaderUtils.LoadShaderPair(Device, shaderPath);
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
			Vertex = .() { Shader = .(vertShader, "main"), Buffers = .() },
			Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = depthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
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

	private bool CreateGltfPipeline()
	{
		if (mDuckVertexBuffer == null)
			return false;

		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/gltf_mesh");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load GLTF shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera, b1=object, t0=texture, s0=sampler
		BindGroupLayoutEntry[4] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mGltfBindGroupLayout = layout;

		IBindGroupLayout[1] layouts = .(mGltfBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mGltfPipelineLayout = pipelineLayout;

		BindGroupEntry[4] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Buffer(1, mObjectUniformBuffer),
			BindGroupEntry.Texture(0, mDuckTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mGltfBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mGltfBindGroup = group;

		// Vertex layout: Position(12) + Normal(12) + TexCoord(8) + Color(4) + Tangent(12) = 48
		Sedulous.RHI.VertexAttribute[5] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),
			.(VertexFormat.Float3, 12, 1),
			.(VertexFormat.Float2, 24, 2),
			.(VertexFormat.UByte4Normalized, 32, 3),
			.(VertexFormat.Float3, 36, 4)
		);
		VertexBufferLayout[1] vertexBuffers = .(.((uint64)mDuckVertexStride, vertexAttrs));

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mGltfPipelineLayout,
			Vertex = .() { Shader = .(vertShader, "main"), Buffers = vertexBuffers },
			Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .Back },
			DepthStencil = depthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create GLTF pipeline");
			return false;
		}
		mGltfPipeline = pipeline;

		Console.WriteLine("GLTF pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mModelRotation += deltaTime * 0.3f;

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

		// Duck model - scale and rotate
		let duckScale = Matrix.CreateScale(0.012f);
		let duckRotation = Matrix.CreateRotationY(mModelRotation);
		let duckModel = duckScale * duckRotation;

		ObjectUniforms duckData = .();
		duckData.Model = duckModel;
		duckData.ObjectColor = .(1f, 1f, 1f, 1.0f);

		Span<uint8> objData = .((uint8*)&duckData, sizeof(ObjectUniforms));
		Device.Queue.WriteBuffer(mObjectUniformBuffer, 0, objData);
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

		// Render Duck model
		if (mGltfPipeline != null && mDuckVertexBuffer != null)
		{
			renderPass.SetPipeline(mGltfPipeline);
			renderPass.SetBindGroup(0, mGltfBindGroup);
			renderPass.SetVertexBuffer(0, mDuckVertexBuffer, 0);

			if (mDuckIndexBuffer != null)
			{
				let indexFormat = mDuckUse32BitIndices ? IndexFormat.UInt32 : IndexFormat.UInt16;
				renderPass.SetIndexBuffer(mDuckIndexBuffer, indexFormat, 0);
				renderPass.DrawIndexed((uint32)mDuckIndexCount, 1, 0, 0, 0);
			}
		}
	}

	protected override void OnCleanup()
	{
		if (mGltfPipeline != null) delete mGltfPipeline;
		if (mGltfPipelineLayout != null) delete mGltfPipelineLayout;
		if (mGltfBindGroup != null) delete mGltfBindGroup;
		if (mGltfBindGroupLayout != null) delete mGltfBindGroupLayout;

		if (mSkyboxPipeline != null) delete mSkyboxPipeline;
		if (mSkyboxPipelineLayout != null) delete mSkyboxPipelineLayout;
		if (mSkyboxBindGroup != null) delete mSkyboxBindGroup;
		if (mSkyboxBindGroupLayout != null) delete mSkyboxBindGroupLayout;

		if (mDuckTextureView != null) delete mDuckTextureView;
		if (mDuckTexture != null) delete mDuckTexture;
		if (mDuckIndexBuffer != null) delete mDuckIndexBuffer;
		if (mDuckVertexBuffer != null) delete mDuckVertexBuffer;
		if (mDuckModel != null) delete mDuckModel;

		if (mSampler != null) delete mSampler;
		if (mObjectUniformBuffer != null) delete mObjectUniformBuffer;
		if (mCameraUniformBuffer != null) delete mCameraUniformBuffer;

		if (mSkyboxRenderer != null) delete mSkyboxRenderer;
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
		let app = scope RendererStaticMeshSample();
		return app.Run();
	}
}
