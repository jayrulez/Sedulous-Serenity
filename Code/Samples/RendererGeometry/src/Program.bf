namespace RendererGeometry;

using System;
using System.IO;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Imaging;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Framework.Renderer;
using Sedulous.Resources;
using Sedulous.Shell.Input;
using RHI.SampleFramework;

/// Geometry sample demonstrating various geometry types:
/// - Static mesh rendering (cube)
/// - Particle system (fountain)
/// - Skybox (gradient)
/// - Sprites (billboards)
/// - GLTF model loading (Duck)
class RendererGeometrySample : RHISampleApp
{
	// Renderer components
	private GPUResourceManager mResourceManager;
	private ParticleSystem mParticleSystem;
	private SkyboxRenderer mSkyboxRenderer;
	private SpriteRenderer mSpriteRenderer;

	// Mesh resources
	private GPUMeshHandle mCubeMesh;
	private IBuffer mCameraUniformBuffer;
	private IBuffer mObjectUniformBuffer;
	private IBuffer mBlueCubeObjectBuffer;  // Second cube uniform buffer
	private ISampler mSampler;

	// GLTF Model resources
	private Model mDuckModel;
	private IBuffer mDuckVertexBuffer;
	private IBuffer mDuckIndexBuffer;
	private ITexture mDuckTexture;
	private ITextureView mDuckTextureView;
	private int32 mDuckIndexCount;
	private bool mDuckUse32BitIndices;
	private int32 mDuckVertexStride;

	// Mesh pipeline
	private IBindGroupLayout mMeshBindGroupLayout;
	private IBindGroup mMeshBindGroup;
	private IBindGroup mBlueCubeBindGroup;  // Bind group for blue cube
	private IPipelineLayout mMeshPipelineLayout;
	private IRenderPipeline mMeshPipeline;

	// Particle pipeline
	private IBindGroupLayout mParticleBindGroupLayout;
	private IBindGroup mParticleBindGroup;
	private IPipelineLayout mParticlePipelineLayout;
	private IRenderPipeline mParticlePipeline;

	// Skybox pipeline
	private IBindGroupLayout mSkyboxBindGroupLayout;
	private IBindGroup mSkyboxBindGroup;
	private IPipelineLayout mSkyboxPipelineLayout;
	private IRenderPipeline mSkyboxPipeline;

	// Sprite pipeline
	private IBindGroupLayout mSpriteBindGroupLayout;
	private IBindGroup mSpriteBindGroup;
	private IPipelineLayout mSpritePipelineLayout;
	private IRenderPipeline mSpritePipeline;

	// GLTF pipeline
	private IBindGroupLayout mGltfBindGroupLayout;
	private IBindGroup mGltfBindGroup;
	private IPipelineLayout mGltfPipelineLayout;
	private IRenderPipeline mGltfPipeline;
	private IBuffer mGltfObjectBuffer;

	// Fox (skinned mesh) resources - using SkinnedMeshResource
	private Model mFoxModel;
	private SkinnedMeshResource mFoxResource ~ delete _;
	private GPUSkinnedMeshHandle mFoxGPUMesh;
	private ITexture mFoxTexture;
	private ITextureView mFoxTextureView;
	private AnimationPlayer mFoxAnimPlayer;
	private int32 mCurrentAnimIndex = 0;

	// Skinned mesh pipeline
	private IBindGroupLayout mSkinnedBindGroupLayout;
	private IBindGroup mSkinnedBindGroup;
	private IPipelineLayout mSkinnedPipelineLayout;
	private IRenderPipeline mSkinnedPipeline;
	private IBuffer mSkinnedObjectBuffer;
	private IBuffer mBoneBuffer;

	// Camera
	private Camera mCamera;

	// Animation state
	private float mCubeRotation = 0.0f;

	// Camera control
	private float mCameraYaw = 0.0f;    // Horizontal rotation
	private float mCameraPitch = 0.0f;  // Vertical rotation
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 5.0f;
	private float mCameraLookSpeed = 0.003f;

	public this() : base(.(){ Title = "Renderer Geometry Sample", Width = 1024, Height = 768, ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f), EnableDepth = true })
	{
	}

	protected override bool OnInitialize()
	{
		// Initialize renderer components
		mResourceManager = new GPUResourceManager(Device);

		// Setup camera
		mCamera = .();
		mCamera.Position = .(0, 2, 8);
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		// Initialize yaw/pitch from a forward direction looking at origin
		mCameraYaw = Math.PI_f;  // Looking toward -Z
		mCameraPitch = -0.1f;    // Slightly looking down
		UpdateCameraDirection();

		if (!CreateBuffers())
			return false;

		if (!CreateMesh())
			return false;

		if (!CreateParticleSystem())
			return false;

		if (!CreateSkybox())
			return false;

		if (!CreateSprites())
			return false;

		if (!LoadGltfModel())
			return false;

		if (!CreateMeshPipeline())
			return false;

		if (!CreateParticlePipeline())
			return false;

		if (!CreateSkyboxPipeline())
			return false;

		if (!CreateSpritePipeline())
			return false;

		if (!CreateGltfPipeline())
			return false;

		if (!LoadFoxModel())
			return false;

		if (!CreateSkinnedPipeline())
			return false;

		Console.WriteLine("RendererGeometry sample initialized");
		Console.WriteLine("Demonstrating: Static Mesh, Particle System, Skybox, Sprites, GLTF Model, Skinned Mesh");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Right-click+Drag=Look, Tab=Toggle mouse capture");
		Console.WriteLine("          Left/Right or ,/. = Cycle Fox animations");
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

		// Cycle through Fox animations with left/right arrow keys
		if (mFoxAnimPlayer != null && mFoxResource != null && mFoxResource.AnimationCount > 0)
		{
			if (keyboard.IsKeyPressed(.Right) || keyboard.IsKeyPressed(.Period))
			{
				mCurrentAnimIndex = (mCurrentAnimIndex + 1) % (int32)mFoxResource.AnimationCount;
				mFoxAnimPlayer.Play(mFoxResource.Animations[mCurrentAnimIndex]);
				Console.WriteLine(scope $"Playing animation: {mFoxResource.Animations[mCurrentAnimIndex].Name}");
			}
			if (keyboard.IsKeyPressed(.Left) || keyboard.IsKeyPressed(.Comma))
			{
				mCurrentAnimIndex = (mCurrentAnimIndex - 1 + (int32)mFoxResource.AnimationCount) % (int32)mFoxResource.AnimationCount;
				mFoxAnimPlayer.Play(mFoxResource.Animations[mCurrentAnimIndex]);
				Console.WriteLine(scope $"Playing animation: {mFoxResource.Animations[mCurrentAnimIndex].Name}");
			}
		}
	}

	private bool CreateBuffers()
	{
		// Camera uniform buffer
		BufferDescriptor cameraDesc = .(256, .Uniform, .Upload);
		if (Device.CreateBuffer(&cameraDesc) case .Ok(let buf))
			mCameraUniformBuffer = buf;
		else
			return false;

		// Object uniform buffer (red cube - right)
		BufferDescriptor objectDesc = .(128, .Uniform, .Upload);
		if (Device.CreateBuffer(&objectDesc) case .Ok(let objBuf))
			mObjectUniformBuffer = objBuf;
		else
			return false;

		// Blue cube object uniform buffer (left)
		BufferDescriptor blueCubeDesc = .(128, .Uniform, .Upload);
		if (Device.CreateBuffer(&blueCubeDesc) case .Ok(let blueBuf))
			mBlueCubeObjectBuffer = blueBuf;
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
		// Create a cube mesh
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

	private bool CreateParticleSystem()
	{
		mParticleSystem = new ParticleSystem(Device, 1000);

		// Configure as fountain effect
		var config = ref mParticleSystem.Config;
		config.EmissionRate = 80;
		config.MinVelocity = .(-0.8f, 4.0f, -0.8f);
		config.MaxVelocity = .(0.8f, 6.0f, 0.8f);
		config.MinSize = 0.15f;
		config.MaxSize = 0.3f;
		config.MinLife = 1.5f;
		config.MaxLife = 2.5f;
		config.StartColor = .(255, 220, 80, 255);   // Bright yellow-orange
		config.EndColor = .(255, 80, 0, 180);       // Red-orange, semi-transparent
		config.Gravity = .(0, -5.0f, 0);
		config.SizeOverLife = 0.5f;

		// Position emitter far left
		mParticleSystem.Position = .(-4.0f, 0.0f, 0.0f);

		Console.WriteLine("Particle system created");
		return true;
	}

	private bool CreateSkybox()
	{
		mSkyboxRenderer = new SkyboxRenderer(Device);

		// Create gradient sky (natural sky colors)
		let topColor = Color(70, 130, 200, 255);     // Deep sky blue
		let bottomColor = Color(180, 210, 240, 255); // Light horizon blue

		if (!mSkyboxRenderer.CreateGradientSky(topColor, bottomColor, 32))
		{
			Console.WriteLine("Failed to create skybox");
			return false;
		}

		Console.WriteLine("Skybox created");
		return true;
	}

	private bool CreateSprites()
	{
		mSpriteRenderer = new SpriteRenderer(Device, 1000);
		Console.WriteLine("Sprite renderer created");
		return true;
	}

	private bool LoadGltfModel()
	{
		// Load the Duck model
		mDuckModel = new Model();
		let loader = scope GltfLoader();

		let result = loader.Load("models/Duck/glTF/Duck.gltf", mDuckModel);
		if (result != .Ok)
		{
			Console.WriteLine(scope $"Failed to load Duck model: {result}");
			delete mDuckModel;
			mDuckModel = null;
			return true; // Continue without model
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
				return true;
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
				return true;
			}

			mDuckIndexCount = mesh.IndexCount;
			mDuckUse32BitIndices = mesh.Use32BitIndices;
			mDuckVertexStride = mesh.VertexStride;

			Console.WriteLine(scope $"Duck mesh: {mesh.VertexCount} vertices, {mesh.IndexCount} indices, stride={mesh.VertexStride}");
		}

		// Load texture
		if (mDuckModel.Textures.Count > 0)
		{
			let tex = mDuckModel.Textures[0];
			let uri = tex.Uri;

			if (!uri.IsEmpty)
			{
				let texPath = scope String();
				texPath.Append("models/Duck/glTF/");
				texPath.Append(uri);

				Console.WriteLine(scope $"Loading texture: {texPath}");

				// Load image using SDLImageLoader
				let imageLoader = scope SDLImageLoader();
				if (imageLoader.LoadFromFile(texPath) case .Ok(var loadInfo))
				{
					defer loadInfo.Dispose();
					Console.WriteLine(scope $"Texture loaded: {loadInfo.Width}x{loadInfo.Height}");

					// Create GPU texture
					TextureDescriptor texDesc = .Texture2D(loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .Sampled | .CopyDst);
					if (Device.CreateTexture(&texDesc) case .Ok(let texture))
					{
						mDuckTexture = texture;

						// Upload texture data
						TextureDataLayout layout = .()
						{
							Offset = 0,
							BytesPerRow = loadInfo.Width * 4,
							RowsPerImage = loadInfo.Height
						};
						Extent3D size = .(loadInfo.Width, loadInfo.Height, 1);
						Span<uint8> data = .(loadInfo.Data.Ptr, loadInfo.Data.Count);
						Device.Queue.WriteTexture(mDuckTexture, data, &layout, &size, 0, 0);

						// Create texture view
						TextureViewDescriptor viewDesc = .();
						viewDesc.Format = .RGBA8Unorm;
						viewDesc.Dimension = .Texture2D;
						viewDesc.MipLevelCount = 1;
						viewDesc.ArrayLayerCount = 1;

						if (Device.CreateTextureView(mDuckTexture, &viewDesc) case .Ok(let view))
							mDuckTextureView = view;
					}
				}
				else
				{
					Console.WriteLine(scope $"Failed to load texture: {texPath}");
				}
			}
		}

		// Create a fallback white texture if no texture loaded
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

	private bool CreateMeshPipeline()
	{
		// Load shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/simple_mesh");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load mesh shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera, b1=object
		BindGroupLayoutEntry[2] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mMeshBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mMeshBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mMeshPipelineLayout = pipelineLayout;

		// Bind group for red cube (right)
		BindGroupEntry[2] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Buffer(1, mObjectUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mMeshBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mMeshBindGroup = group;

		// Bind group for blue cube (left)
		BindGroupEntry[2] blueEntries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Buffer(1, mBlueCubeObjectBuffer)
		);
		BindGroupDescriptor blueBindGroupDesc = .(mMeshBindGroupLayout, blueEntries);
		if (Device.CreateBindGroup(&blueBindGroupDesc) not case .Ok(let blueGroup))
			return false;
		mBlueCubeBindGroup = blueGroup;

		// Vertex layout for common mesh format
		Sedulous.RHI.VertexAttribute[3] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2)   // UV
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

	private bool CreateParticlePipeline()
	{
		// Load particle shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/particle");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load particle shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mParticleBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mParticleBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mParticlePipelineLayout = pipelineLayout;

		// Bind group
		BindGroupEntry[1] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mParticleBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mParticleBindGroup = group;

		// Vertex layout for ParticleVertex: Position(12) + Size(8) + Color(4) + Rotation(4) = 28 bytes
		Sedulous.RHI.VertexAttribute[4] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float2, 12, 1),  // Size
			.(VertexFormat.UByte4Normalized, 16, 2), // Color (RGBA bytes)
			.(VertexFormat.Float, 20, 3)   // Rotation
		);
		// Step per instance for instanced rendering
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(28, vertexAttrs, .Instance)
		);

		// Blending for particles (alpha blend)
		ColorTargetState[1] colorTargets = .(
			ColorTargetState(SwapChain.Format, .AlphaBlend)
		);

		// Depth test but no write (particles rendered after opaque)
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;  // Don't write depth for transparent particles
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mParticlePipelineLayout,
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
				CullMode = .None  // Particles are billboards, no culling
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
			Console.WriteLine("Failed to create particle pipeline");
			return false;
		}
		mParticlePipeline = pipeline;

		Console.WriteLine("Particle pipeline created");
		return true;
	}

	private bool CreateSkyboxPipeline()
	{
		// Load skybox shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/skybox");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load skybox shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera, t0=cubemap, s0=sampler
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .TextureCube),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mSkyboxBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mSkyboxBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mSkyboxPipelineLayout = pipelineLayout;

		// Bind group
		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Texture(0, mSkyboxRenderer.CubemapView),
			BindGroupEntry.Sampler(0, mSkyboxRenderer.Sampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mSkyboxBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mSkyboxBindGroup = group;

		// No vertex buffers needed - fullscreen triangle uses SV_VertexID
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		// Depth test at far plane, no write
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .LessEqual;  // Skybox at far plane
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSkyboxPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader, "main"),
				Buffers = .()  // No vertex buffers
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

	private bool CreateSpritePipeline()
	{
		// Load sprite shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/sprite");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load sprite shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mSpriteBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mSpriteBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mSpritePipelineLayout = pipelineLayout;

		// Bind group
		BindGroupEntry[1] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mSpriteBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mSpriteBindGroup = group;

		// SpriteInstance layout: Position(12) + Size(8) + UVRect(16) + Color(4) = 40 bytes
		Sedulous.RHI.VertexAttribute[4] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),            // Position
			.(VertexFormat.Float2, 12, 1),           // Size
			.(VertexFormat.Float4, 20, 2),           // UVRect
			.(VertexFormat.UByte4Normalized, 36, 3)  // Color
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(40, vertexAttrs, .Instance)
		);

		// Alpha blending for sprites
		ColorTargetState[1] colorTargets = .(
			ColorTargetState(SwapChain.Format, .AlphaBlend)
		);

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSpritePipelineLayout,
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
			Console.WriteLine("Failed to create sprite pipeline");
			return false;
		}
		mSpritePipeline = pipeline;

		Console.WriteLine("Sprite pipeline created");
		return true;
	}

	private bool CreateGltfPipeline()
	{
		if (mDuckVertexBuffer == null)
			return true; // No model loaded

		// Load GLTF shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/gltf_mesh");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load GLTF shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Create object uniform buffer for GLTF
		BufferDescriptor objectDesc = .(128, .Uniform, .Upload);
		if (Device.CreateBuffer(&objectDesc) case .Ok(let buf))
			mGltfObjectBuffer = buf;
		else
			return false;

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

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mGltfBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mGltfPipelineLayout = pipelineLayout;

		// Bind group
		BindGroupEntry[4] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Buffer(1, mGltfObjectBuffer),
			BindGroupEntry.Texture(0, mDuckTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mGltfBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mGltfBindGroup = group;

		// Vertex layout matching GLTF loader output:
		// Position(Float3) + Normal(Float3) + TexCoord(Float2) + Color(uint32) + Tangent(Float3)
		// = 12 + 12 + 8 + 4 + 12 = 48 bytes
		Sedulous.RHI.VertexAttribute[5] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),    // Position
			.(VertexFormat.Float3, 12, 1),   // Normal
			.(VertexFormat.Float2, 24, 2),   // TexCoord
			.(VertexFormat.UByte4Normalized, 32, 3), // Color
			.(VertexFormat.Float3, 36, 4)    // Tangent
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
			Console.WriteLine("Failed to create GLTF pipeline");
			return false;
		}
		mGltfPipeline = pipeline;

		Console.WriteLine("GLTF pipeline created");
		return true;
	}

	private bool LoadFoxModel_REPLACE_MARKER()
	{
		// Load Fox model
		mFoxModel = new Model();
		let loader = scope GltfLoader();

		let result = loader.Load("models/Fox/glTF/Fox.gltf", mFoxModel);
		if (result != .Ok)
		{
			Console.WriteLine(scope $"Failed to load Fox model: {result}");
			delete mFoxModel;
			mFoxModel = null;
			return true; // Continue without model
		}

		Console.WriteLine(scope $"Fox model loaded: {mFoxModel.Meshes.Count} meshes, {mFoxModel.Bones.Count} bones, {mFoxModel.Animations.Count} animations");

		// Get skin - required for conversion
		if (mFoxModel.Skins.Count == 0 || mFoxModel.Meshes.Count == 0)
		{
			Console.WriteLine("Fox model has no skin or mesh data");
			return true;
		}
		let skin = mFoxModel.Skins[0];
		let modelMesh = mFoxModel.Meshes[0];
		Console.WriteLine(scope $"Fox skin: {skin.Joints.Count} joints");

		// Use converters from Sedulous.Geometry.Tooling to create SkinnedMeshResource
		if (ModelMeshConverter.ConvertToSkinnedMesh(modelMesh, skin) case .Ok(var conversionResult))
		{
			defer conversionResult.Dispose();

			// Create skeleton using the converter
			let skeleton = SkeletonConverter.CreateFromSkin(mFoxModel, skin);
			if (skeleton == null)
			{
				Console.WriteLine("Failed to create skeleton");
				delete conversionResult.Mesh;
				return true;
			}

			// Convert animations using the node-to-bone mapping
			let animations = AnimationConverter.ConvertAll(mFoxModel, conversionResult.NodeToBoneMapping);

			// Create the SkinnedMeshResource with all the data
			mFoxResource = new SkinnedMeshResource(conversionResult.Mesh, true);
			mFoxResource.SetSkeleton(skeleton, true);
			mFoxResource.SetAnimations(animations, true);

			Console.WriteLine(scope $"Fox resource created: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton.BoneCount} bones, {mFoxResource.AnimationCount} animations");

			// Create GPU mesh
			mFoxGPUMesh = mResourceManager.CreateSkinnedMesh(mFoxResource.Mesh);
		}
		else
		{
			Console.WriteLine("Failed to convert Fox mesh");
			return true;
		}

		// Create AnimationPlayer and start playing
		if (mFoxResource?.Skeleton != null && mFoxResource.AnimationCount > 0)
		{
			mFoxAnimPlayer = mFoxResource.CreatePlayer();
			mFoxAnimPlayer.Play(mFoxResource.Animations[0]);
			Console.WriteLine(scope $"Fox animation player started: {mFoxResource.Animations[0].Name}");
		}

		// Load texture
		let texPath = "models/Fox/glTF/Texture.png";
		let imageLoader = scope SDLImageLoader();
		if (imageLoader.LoadFromFile(texPath) case .Ok(var loadInfo))
		{
			defer loadInfo.Dispose();
			Console.WriteLine(scope $"Fox texture: {loadInfo.Width}x{loadInfo.Height}, data size={loadInfo.Data.Count}, expected={loadInfo.Width * loadInfo.Height * 4}");

			TextureDescriptor texDesc = .Texture2D(loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .Sampled | .CopyDst);
			if (Device.CreateTexture(&texDesc) case .Ok(let texture))
			{
				mFoxTexture = texture;

				TextureDataLayout layout = .() { Offset = 0, BytesPerRow = loadInfo.Width * 4, RowsPerImage = loadInfo.Height };
				Extent3D size = .(loadInfo.Width, loadInfo.Height, 1);
				Span<uint8> data = .(loadInfo.Data.Ptr, loadInfo.Data.Count);
				Device.Queue.WriteTexture(mFoxTexture, data, &layout, &size, 0, 0);

				TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D, MipLevelCount = 1, ArrayLayerCount = 1 };
				if (Device.CreateTextureView(mFoxTexture, &viewDesc) case .Ok(let view))
					mFoxTextureView = view;
			}
		}

		// Create fallback white texture if needed
		if (mFoxTextureView == null)
		{
			TextureDescriptor texDesc = .Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);
			if (Device.CreateTexture(&texDesc) case .Ok(let texture))
			{
				mFoxTexture = texture;
				uint8[4] white = .(255, 255, 255, 255);
				TextureDataLayout layout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
				Extent3D size = .(1, 1, 1);
				Span<uint8> data = .(&white, 4);
				Device.Queue.WriteTexture(mFoxTexture, data, &layout, &size, 0, 0);

				TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D, MipLevelCount = 1, ArrayLayerCount = 1 };
				if (Device.CreateTextureView(mFoxTexture, &viewDesc) case .Ok(let view))
					mFoxTextureView = view;
			}
		}

		return true;
	}

	private bool CreateSkinnedPipeline()
	{
		if (mFoxGPUMesh.Index == uint32.MaxValue)
			return true; // No skinned mesh loaded

		// Load skinned mesh shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/skinned_mesh");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load skinned mesh shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Create uniform buffers
		BufferDescriptor objectDesc = .(128, .Uniform, .Upload);
		if (Device.CreateBuffer(&objectDesc) case .Ok(let buf))
			mSkinnedObjectBuffer = buf;
		else
			return false;

		// Bone buffer: 128 bones * 64 bytes per matrix = 8192 bytes
		BufferDescriptor boneDesc = .(128 * 64, .Uniform, .Upload);
		if (Device.CreateBuffer(&boneDesc) case .Ok(let boneBuf))
			mBoneBuffer = boneBuf;
		else
			return false;

		// Bind group layout: b0=camera, b1=object, b2=bones, t0=texture, s0=sampler
		BindGroupLayoutEntry[5] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(2, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mSkinnedBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mSkinnedBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mSkinnedPipelineLayout = pipelineLayout;

		// Bind group
		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Buffer(1, mSkinnedObjectBuffer),
			BindGroupEntry.Buffer(2, mBoneBuffer),
			BindGroupEntry.Texture(0, mFoxTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mSkinnedBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mSkinnedBindGroup = group;

		// Vertex layout for SkinnedVertex (72 bytes):
		// Position(12) + Normal(12) + TexCoord(8) + Color(4) + Tangent(12) + Joints(8) + Weights(16)
		Sedulous.RHI.VertexAttribute[7] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),             // Position
			.(VertexFormat.Float3, 12, 1),            // Normal
			.(VertexFormat.Float2, 24, 2),            // TexCoord
			.(VertexFormat.UByte4Normalized, 32, 3),  // Color
			.(VertexFormat.Float3, 36, 4),            // Tangent
			.(VertexFormat.UShort4, 48, 5),           // Joints
			.(VertexFormat.Float4, 56, 6)             // Weights
		);
		VertexBufferLayout[1] vertexBuffers = .(.(72, vertexAttrs));

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSkinnedPipelineLayout,
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
			Console.WriteLine("Failed to create skinned mesh pipeline");
			return false;
		}
		mSkinnedPipeline = pipeline;

		Console.WriteLine("Skinned mesh pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Rotate the cube
		mCubeRotation += deltaTime * 0.5f;

		// Update Fox animation
		if (mFoxAnimPlayer != null)
		{
			mFoxAnimPlayer.Update(deltaTime);

			// Upload bone matrices to GPU
			// Skeleton is now ordered by skin joint index, so no remapping needed
			if (mBoneBuffer != null)
			{
				Span<uint8> boneData = .((uint8*)mFoxAnimPlayer.BoneMatrices.Ptr, 128 * sizeof(Matrix4x4));
				Device.Queue.WriteBuffer(mBoneBuffer, 0, boneData);
			}
		}

		// Update particle system
		mParticleSystem.Update(deltaTime);
		mParticleSystem.Upload();

		// Update sprites - create some animated sprites
		mSpriteRenderer.Begin();

		// Add 8 floating sprites in a circle around center
		for (int i = 0; i < 8; i++)
		{
			float angle = (float)i / 8.0f * Math.PI_f * 2.0f + totalTime * 0.5f;
			float radius = 3.5f;
			float x = Math.Cos(angle) * radius;
			float z = Math.Sin(angle) * radius;
			float y = 2.0f + Math.Sin(totalTime * 2.0f + (float)i) * 0.5f;

			// Cycle through bright colors
			uint8 r = (uint8)(128 + 127 * Math.Sin(totalTime + (float)i * 0.5f));
			uint8 g = (uint8)(128 + 127 * Math.Sin(totalTime * 1.3f + (float)i * 0.7f));
			uint8 b = (uint8)(128 + 127 * Math.Sin(totalTime * 0.7f + (float)i * 0.3f));

			mSpriteRenderer.AddSprite(.(x, y, z), .(0.5f, 0.5f), Color(r, g, b, 230));
		}

		mSpriteRenderer.End();

		// Update camera uniforms
		CameraUniforms cameraData = .();
		cameraData.ViewProjection = mCamera.ViewProjectionMatrix;
		cameraData.View = mCamera.ViewMatrix;
		cameraData.Projection = mCamera.ProjectionMatrix;
		cameraData.CameraPosition = mCamera.Position;

		Span<uint8> camData = .((uint8*)&cameraData, sizeof(CameraUniforms));
		Device.Queue.WriteBuffer(mCameraUniformBuffer, 0, camData);

		// Update object uniforms for red cube (right)
		// Translation * Rotation = rotate in place, then translate
		let redCubeModel = Matrix4x4.CreateTranslation(2.0f, 0.5f, 0) * Matrix4x4.CreateRotationY(mCubeRotation);
		ObjectUniforms redCubeData = .();
		redCubeData.Model = redCubeModel;
		redCubeData.ObjectColor = .(1f, 0f, 0f, 1.0f);  // Red color

		Span<uint8> redObjData = .((uint8*)&redCubeData, sizeof(ObjectUniforms));
		Device.Queue.WriteBuffer(mObjectUniformBuffer, 0, redObjData);

		// Update object uniforms for blue cube (left)
		let blueCubeModel = Matrix4x4.CreateTranslation(-2.0f, 0.5f, 0) * Matrix4x4.CreateRotationY(-mCubeRotation);
		ObjectUniforms blueCubeData = .();
		blueCubeData.Model = blueCubeModel;
		blueCubeData.ObjectColor = .(0f, 0.3f, 1f, 1.0f);  // Blue color

		Span<uint8> blueObjData = .((uint8*)&blueCubeData, sizeof(ObjectUniforms));
		Device.Queue.WriteBuffer(mBlueCubeObjectBuffer, 0, blueObjData);

		// Update GLTF object uniforms (duck in center)
		if (mGltfObjectBuffer != null)
		{
			// Duck model is quite large, scale it down and position it in center
			let duckScale = Matrix4x4.CreateScale(0.012f);
			let duckTranslation = Matrix4x4.CreateTranslation(0, 0, 0); // Center
			let duckModel = duckScale * duckTranslation;

			ObjectUniforms duckData = .();
			duckData.Model = duckModel;
			duckData.ObjectColor = .(1f, 1f, 1f, 1.0f);  // White (use texture color)

			Span<uint8> duckObjData = .((uint8*)&duckData, sizeof(ObjectUniforms));
			Device.Queue.WriteBuffer(mGltfObjectBuffer, 0, duckObjData);
		}

		// Update Fox object uniforms (right of duck)
		if (mSkinnedObjectBuffer != null)
		{
			// Fox model - scale it down and position to the right
			let foxScale = Matrix4x4.CreateScale(0.02f);
			let foxTranslation = Matrix4x4.CreateTranslation(3.5f, 0, 0);
			let foxModel = foxTranslation * foxScale;

			ObjectUniforms foxData = .();
			foxData.Model = foxModel;
			foxData.ObjectColor = .(1f, 1f, 1f, 1.0f);  // White (use texture color)

			Span<uint8> foxObjData = .((uint8*)&foxData, sizeof(ObjectUniforms));
			Device.Queue.WriteBuffer(mSkinnedObjectBuffer, 0, foxObjData);
		}
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// 1. Render skybox first (at far plane)
		RenderSkybox(renderPass);

		// 2. Render opaque geometry
		RenderMesh(renderPass);
		RenderGltfModel(renderPass);
		RenderSkinnedMesh(renderPass);

		// 3. Render transparent (particles, sprites) last
		RenderSprites(renderPass);
		RenderParticles(renderPass);
	}

	private void RenderSkybox(IRenderPassEncoder renderPass)
	{
		if (mSkyboxPipeline == null || mSkyboxBindGroup == null || !mSkyboxRenderer.IsValid)
			return;

		renderPass.SetPipeline(mSkyboxPipeline);
		renderPass.SetBindGroup(0, mSkyboxBindGroup);
		renderPass.Draw(3, 1, 0, 0);  // Fullscreen triangle
	}

	private void RenderMesh(IRenderPassEncoder renderPass)
	{
		let mesh = mResourceManager.GetMesh(mCubeMesh);
		if (mesh == null)
			return;

		renderPass.SetPipeline(mMeshPipeline);
		renderPass.SetVertexBuffer(0, mesh.VertexBuffer, 0);

		if (mesh.IndexBuffer != null)
			renderPass.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);

		// Render red cube (right)
		renderPass.SetBindGroup(0, mMeshBindGroup);
		if (mesh.IndexBuffer != null)
			renderPass.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
		else
			renderPass.Draw(mesh.VertexCount, 1, 0, 0);

		// Render blue cube (left)
		renderPass.SetBindGroup(0, mBlueCubeBindGroup);
		if (mesh.IndexBuffer != null)
			renderPass.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
		else
			renderPass.Draw(mesh.VertexCount, 1, 0, 0);
	}

	private void RenderGltfModel(IRenderPassEncoder renderPass)
	{
		if (mGltfPipeline == null || mDuckVertexBuffer == null)
			return;

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

	private void RenderSkinnedMesh(IRenderPassEncoder renderPass)
	{
		if (mSkinnedPipeline == null || mSkinnedBindGroup == null)
			return;

		let mesh = mResourceManager.GetSkinnedMesh(mFoxGPUMesh);
		if (mesh == null)
			return;

		renderPass.SetPipeline(mSkinnedPipeline);
		renderPass.SetBindGroup(0, mSkinnedBindGroup);
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

	private void RenderSprites(IRenderPassEncoder renderPass)
	{
		if (mSpritePipeline == null || mSpriteBindGroup == null)
			return;

		let spriteCount = mSpriteRenderer.SpriteCount;
		if (spriteCount == 0)
			return;

		renderPass.SetPipeline(mSpritePipeline);
		renderPass.SetBindGroup(0, mSpriteBindGroup);
		renderPass.SetVertexBuffer(0, mSpriteRenderer.InstanceBuffer, 0);

		// Draw 6 vertices per sprite (quad), with spriteCount instances
		// The vertex shader generates quad corners using SV_VertexID
		renderPass.Draw(6, (uint32)spriteCount, 0, 0);
	}

	private void RenderParticles(IRenderPassEncoder renderPass)
	{
		if (mParticlePipeline == null || mParticleBindGroup == null)
			return;

		let particleCount = mParticleSystem.ParticleCount;
		if (particleCount == 0)
			return;

		renderPass.SetPipeline(mParticlePipeline);
		renderPass.SetBindGroup(0, mParticleBindGroup);
		renderPass.SetVertexBuffer(0, mParticleSystem.VertexBuffer, 0);
		renderPass.SetIndexBuffer(mParticleSystem.IndexBuffer, .UInt16, 0);

		// Draw 6 indices per particle (quad), particle count instances
		renderPass.DrawIndexed(6, (uint32)particleCount, 0, 0, 0);
	}

	protected override void OnCleanup()
	{
		// Skinned mesh (Fox)
		if (mSkinnedPipeline != null) delete mSkinnedPipeline;
		if (mSkinnedPipelineLayout != null) delete mSkinnedPipelineLayout;
		if (mSkinnedBindGroup != null) delete mSkinnedBindGroup;
		if (mSkinnedBindGroupLayout != null) delete mSkinnedBindGroupLayout;
		if (mSkinnedObjectBuffer != null) delete mSkinnedObjectBuffer;
		if (mBoneBuffer != null) delete mBoneBuffer;
		if (mFoxTextureView != null) delete mFoxTextureView;
		if (mFoxTexture != null) delete mFoxTexture;
		if (mFoxAnimPlayer != null) delete mFoxAnimPlayer;
		// mFoxResource is deleted via ~ destructor declaration
		if (mFoxModel != null) delete mFoxModel;

		// GLTF
		if (mGltfPipeline != null) delete mGltfPipeline;
		if (mGltfPipelineLayout != null) delete mGltfPipelineLayout;
		if (mGltfBindGroup != null) delete mGltfBindGroup;
		if (mGltfBindGroupLayout != null) delete mGltfBindGroupLayout;
		if (mGltfObjectBuffer != null) delete mGltfObjectBuffer;
		if (mDuckTextureView != null) delete mDuckTextureView;
		if (mDuckTexture != null) delete mDuckTexture;
		if (mDuckIndexBuffer != null) delete mDuckIndexBuffer;
		if (mDuckVertexBuffer != null) delete mDuckVertexBuffer;
		if (mDuckModel != null) delete mDuckModel;

		// Sprites
		if (mSpritePipeline != null) delete mSpritePipeline;
		if (mSpritePipelineLayout != null) delete mSpritePipelineLayout;
		if (mSpriteBindGroup != null) delete mSpriteBindGroup;
		if (mSpriteBindGroupLayout != null) delete mSpriteBindGroupLayout;

		// Skybox
		if (mSkyboxPipeline != null) delete mSkyboxPipeline;
		if (mSkyboxPipelineLayout != null) delete mSkyboxPipelineLayout;
		if (mSkyboxBindGroup != null) delete mSkyboxBindGroup;
		if (mSkyboxBindGroupLayout != null) delete mSkyboxBindGroupLayout;

		// Particle
		if (mParticlePipeline != null) delete mParticlePipeline;
		if (mParticlePipelineLayout != null) delete mParticlePipelineLayout;
		if (mParticleBindGroup != null) delete mParticleBindGroup;
		if (mParticleBindGroupLayout != null) delete mParticleBindGroupLayout;

		// Mesh
		if (mMeshPipeline != null) delete mMeshPipeline;
		if (mMeshPipelineLayout != null) delete mMeshPipelineLayout;
		if (mMeshBindGroup != null) delete mMeshBindGroup;
		if (mBlueCubeBindGroup != null) delete mBlueCubeBindGroup;
		if (mMeshBindGroupLayout != null) delete mMeshBindGroupLayout;

		// Buffers
		if (mSampler != null) delete mSampler;
		if (mBlueCubeObjectBuffer != null) delete mBlueCubeObjectBuffer;
		if (mObjectUniformBuffer != null) delete mObjectUniformBuffer;
		if (mCameraUniformBuffer != null) delete mCameraUniformBuffer;

		// Renderers
		if (mSpriteRenderer != null) delete mSpriteRenderer;
		if (mSkyboxRenderer != null) delete mSkyboxRenderer;
		if (mParticleSystem != null) delete mParticleSystem;

		// Resources
		if (mResourceManager != null)
		{
			mResourceManager.ReleaseMesh(mCubeMesh);
			mResourceManager.ReleaseSkinnedMesh(mFoxGPUMesh);
			delete mResourceManager;
		}
	}

	private bool LoadFoxModel()
	{
		let cachedPath = "models/Fox/Fox.skinnedmesh";

		// Try to load from cached resource first
		if (File.Exists(cachedPath))
		{
			Console.WriteLine("Loading Fox from cached resource...");
			if (ResourceSerializer.LoadSkinnedMeshBundle(cachedPath) case .Ok(let resource))
			{
				mFoxResource = resource;
				Console.WriteLine(scope $"Fox resource loaded from cache: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.AnimationCount} animations");

				// Create GPU mesh from loaded resource
				mFoxGPUMesh = mResourceManager.CreateSkinnedMesh(mFoxResource.Mesh);

				ResourceSerializer.SaveSkinnedMeshBundle(mFoxResource, scope $"{cachedPath}2");
			}
			else
			{
				Console.WriteLine("Failed to load cached Fox resource, falling back to GLTF import...");
			}
		}

		// If not loaded from cache, import from GLTF
		if (mFoxResource == null)
		{
			mFoxModel = new Model();
			let loader = scope GltfLoader();

			let result = loader.Load("models/Fox/glTF/Fox.gltf", mFoxModel);
			if (result != .Ok)
			{
				Console.WriteLine(scope $"Failed to load Fox model: {result}");
				delete mFoxModel;
				mFoxModel = null;
				return true; // Continue without model
			}

			Console.WriteLine(scope $"Fox model loaded: {mFoxModel.Meshes.Count} meshes, {mFoxModel.Bones.Count} bones, {mFoxModel.Animations.Count} animations");

			// Get skin - required for conversion
			if (mFoxModel.Skins.Count == 0 || mFoxModel.Meshes.Count == 0)
			{
				Console.WriteLine("Fox model has no skin or mesh data");
				return true;
			}
			let skin = mFoxModel.Skins[0];
			let modelMesh = mFoxModel.Meshes[0];
			Console.WriteLine(scope $"Fox skin: {skin.Joints.Count} joints");

			// Use converters from Sedulous.Geometry.Tooling to create SkinnedMeshResource
			if (ModelMeshConverter.ConvertToSkinnedMesh(modelMesh, skin) case .Ok(var conversionResult))
			{
				defer conversionResult.Dispose();

				// Create skeleton using the converter
				let skeleton = SkeletonConverter.CreateFromSkin(mFoxModel, skin);
				if (skeleton == null)
				{
					Console.WriteLine("Failed to create skeleton");
					delete conversionResult.Mesh;
					return true;
				}

				// Convert animations using the node-to-bone mapping
				let animations = AnimationConverter.ConvertAll(mFoxModel, conversionResult.NodeToBoneMapping);

				// Create the SkinnedMeshResource with all the data
				mFoxResource = new SkinnedMeshResource(conversionResult.Mesh, true);
				mFoxResource.Name.Set("Fox");
				mFoxResource.SetSkeleton(skeleton, true);
				mFoxResource.SetAnimations(animations, true);

				Console.WriteLine(scope $"Fox resource created: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton.BoneCount} bones, {mFoxResource.AnimationCount} animations");

				// Save to cache for next time
				if (ResourceSerializer.SaveSkinnedMeshBundle(mFoxResource, cachedPath) case .Ok)
					Console.WriteLine(scope $"Fox resource saved to: {cachedPath}");
				else
					Console.WriteLine("Warning: Failed to save Fox resource to cache");

				// Create GPU mesh
				mFoxGPUMesh = mResourceManager.CreateSkinnedMesh(mFoxResource.Mesh);
			}
			else
			{
				Console.WriteLine("Failed to convert Fox mesh");
				return true;
			}
		}

		// Create AnimationPlayer and start playing
		if (mFoxResource?.Skeleton != null && mFoxResource.AnimationCount > 0)
		{
			mFoxAnimPlayer = mFoxResource.CreatePlayer();
			mFoxAnimPlayer.Play(mFoxResource.Animations[0]);
			Console.WriteLine(scope $"Fox animation player started: {mFoxResource.Animations[0].Name}");
		}

		// Load texture (still needed - not part of cached resource)
		let texPath = "models/Fox/glTF/Texture.png";
		let imageLoader = scope SDLImageLoader();
		if (imageLoader.LoadFromFile(texPath) case .Ok(var loadInfo))
		{
			defer loadInfo.Dispose();
			Console.WriteLine(scope $"Fox texture: {loadInfo.Width}x{loadInfo.Height}, data size={loadInfo.Data.Count}, expected={loadInfo.Width * loadInfo.Height * 4}");

			TextureDescriptor texDesc = .Texture2D(loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .Sampled | .CopyDst);
			if (Device.CreateTexture(&texDesc) case .Ok(let texture))
			{
				mFoxTexture = texture;

				TextureDataLayout layout = .() { Offset = 0, BytesPerRow = loadInfo.Width * 4, RowsPerImage = loadInfo.Height };
				Extent3D size = .(loadInfo.Width, loadInfo.Height, 1);
				Span<uint8> data = .(loadInfo.Data.Ptr, loadInfo.Data.Count);
				Device.Queue.WriteTexture(mFoxTexture, data, &layout, &size, 0, 0);

				TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D, MipLevelCount = 1, ArrayLayerCount = 1 };
				if (Device.CreateTextureView(mFoxTexture, &viewDesc) case .Ok(let view))
					mFoxTextureView = view;
			}
		}

		// Create fallback white texture if needed
		if (mFoxTextureView == null)
		{
			TextureDescriptor texDesc = .Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);
			if (Device.CreateTexture(&texDesc) case .Ok(let texture))
			{
				mFoxTexture = texture;
				uint8[4] white = .(255, 255, 255, 255);
				TextureDataLayout layout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
				Extent3D size = .(1, 1, 1);
				Span<uint8> data = .(&white, 4);
				Device.Queue.WriteTexture(mFoxTexture, data, &layout, &size, 0, 0);

				TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D, MipLevelCount = 1, ArrayLayerCount = 1 };
				if (Device.CreateTextureView(mFoxTexture, &viewDesc) case .Ok(let view))
					mFoxTextureView = view;
			}
		}

		return true;
	}

}

// Uniform buffer structures
[CRepr]
struct CameraUniforms
{
	public Matrix4x4 ViewProjection;
	public Matrix4x4 View;
	public Matrix4x4 Projection;
	public Vector3 CameraPosition;
	public float _pad0;
}

[CRepr]
struct ObjectUniforms
{
	public Matrix4x4 Model;
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
