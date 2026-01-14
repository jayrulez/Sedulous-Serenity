namespace SandboxNext;

using System;
using Sedulous.EngineNext;
using Sedulous.RendererNext;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Simple vertex format for colored geometry.
[CRepr]
struct ColorVertex
{
	public Vector3 Position;
	public Color Color;

	public this(Vector3 pos, Color col)
	{
		Position = pos;
		Color = col;
	}
}

/// Textured vertex format with position, normal, and UV.
[CRepr]
struct TexturedVertex
{
	public Vector3 Position;
	public Vector3 Normal;
	public Vector2 UV;

	public this(Vector3 pos, Vector3 normal, Vector2 uv)
	{
		Position = pos;
		Normal = normal;
		UV = uv;
	}
}

/// Camera uniform data for shaders.
[CRepr]
struct CameraUniformData
{
	public Matrix ViewProjection;
	public Vector3 CameraPosition;
	public float _pad0;
}

/// Object uniform data for shaders.
[CRepr]
struct ObjectUniformData
{
	public Matrix WorldMatrix;
}

/// Simple sandbox application demonstrating RendererNext with textured geometry.
class SandboxApplication : SDL3VulkanApplication
{
	// Rendering resources for simple colored pipeline
	private IRenderPipeline mColorPipeline;
	private IPipelineLayout mColorPipelineLayout;
	private IBindGroupLayout mColorBindGroupLayout;
	private IBindGroup mColorBindGroup;

	// Rendering resources for textured pipeline
	private IRenderPipeline mTexturedPipeline;
	private IPipelineLayout mTexturedPipelineLayout;
	private IBindGroupLayout mTexturedBindGroupLayout;
	private IBindGroup mTexturedBindGroup;

	// Shared uniform buffers
	private IBuffer mCameraBuffer;
	private IBuffer mObjectBuffer;

	// Texture resources
	private ITexture mCheckerTexture;
	private ITextureView mCheckerTextureView;
	private ISampler mLinearSampler;

	// Depth buffer
	private ITexture mDepthTexture;
	private ITextureView mDepthTextureView;

	// Meshes
	private GPUStaticMeshHandle mTriangleMesh;
	private GPUStaticMeshHandle mCubeMesh;

	// Animation
	private float mRotation = 0;

	// Current mode
	private bool mShowTexturedCube = true;

	public this()
	{
		mTitle.Set("SandboxNext - Textured Cube Demo");
		mWidth = 1280;
		mHeight = 720;
	}

	protected override Result<void> OnInitialize()
	{
		Console.WriteLine("SandboxNext initializing...");

		// Set shader path
		mShaderLibrary.SetShaderPath("shaders");

		// Create depth buffer first (needed for pipelines)
		if (!CreateDepthBuffer())
		{
			Console.WriteLine("Failed to create depth buffer");
			return .Err;
		}

		// Create shared resources
		if (!CreateSharedResources())
		{
			Console.WriteLine("Failed to create shared resources");
			return .Err;
		}

		// Create colored pipeline
		if (!CreateColorPipeline())
		{
			Console.WriteLine("Failed to create color pipeline");
			return .Err;
		}

		// Create textured pipeline
		if (!CreateTexturedPipeline())
		{
			Console.WriteLine("Failed to create textured pipeline");
			return .Err;
		}

		// Create meshes
		if (!CreateTriangleMesh())
		{
			Console.WriteLine("Failed to create triangle mesh");
			return .Err;
		}

		if (!CreateCubeMesh())
		{
			Console.WriteLine("Failed to create cube mesh");
			return .Err;
		}

		// Create checkerboard texture
		if (!CreateCheckerTexture())
		{
			Console.WriteLine("Failed to create checker texture");
			return .Err;
		}

		// Create bind groups (after all resources are ready)
		if (!CreateBindGroups())
		{
			Console.WriteLine("Failed to create bind groups");
			return .Err;
		}

		Console.WriteLine("SandboxNext initialized successfully");
		Console.WriteLine($"  Window: {mWidth}x{mHeight}");
		Console.WriteLine($"  Device: {mDevice.GetType().GetName(.. scope .())}");
		Console.WriteLine("Press SPACE to toggle between triangle and textured cube");
		Console.WriteLine("Press ESC to exit");

		return .Ok;
	}

	private bool CreateDepthBuffer()
	{
		TextureDescriptor depthDesc = .Texture2D(
			(.)mWidth, (.)mHeight,
			.Depth24PlusStencil8,
			.DepthStencil
		);
		depthDesc.Label = "DepthBuffer";

		if (mDevice.CreateTexture(&depthDesc) case .Ok(let tex))
			mDepthTexture = tex;
		else
			return false;

		TextureViewDescriptor viewDesc = .();
		viewDesc.Dimension = .Texture2D;
		viewDesc.Format = .Depth24PlusStencil8;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = 1;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = 1;
		viewDesc.Aspect = .DepthOnly;

		if (mDevice.CreateTextureView(mDepthTexture, &viewDesc) case .Ok(let view))
			mDepthTextureView = view;
		else
			return false;

		return true;
	}

	private bool CreateSharedResources()
	{
		// Create uniform buffers
		BufferDescriptor cameraBufDesc = .((.)sizeof(CameraUniformData), .Uniform, .Upload);
		if (mDevice.CreateBuffer(&cameraBufDesc) case .Ok(let cameraBuf))
			mCameraBuffer = cameraBuf;
		else
			return false;

		BufferDescriptor objectBufDesc = .((.)sizeof(ObjectUniformData), .Uniform, .Upload);
		if (mDevice.CreateBuffer(&objectBufDesc) case .Ok(let objectBuf))
			mObjectBuffer = objectBuf;
		else
			return false;

		// Create sampler (anisotropy disabled - requires device feature)
		SamplerDescriptor samplerDesc = .LinearRepeat();
		samplerDesc.MaxAnisotropy = 1;  // 1 = disabled (avoid needing samplerAnisotropy feature)
		if (mDevice.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mLinearSampler = sampler;
		else
			return false;

		return true;
	}

	private bool CreateColorPipeline()
	{
		// Create bind group layout for color pipeline (uniforms only)
		BindGroupLayoutEntry[2] layoutEntries = .(
			.UniformBuffer(0, .Vertex),  // CameraData at register(b0)
			.UniformBuffer(1, .Vertex)   // ObjectData at register(b1)
		);
		BindGroupLayoutDescriptor layoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&layoutDesc) case .Ok(let bgLayout))
			mColorBindGroupLayout = bgLayout;
		else
			return false;

		// Load shaders
		let vertResult = mShaderLibrary.GetShader("simple", .Vertex);
		if (vertResult case .Err)
		{
			Console.WriteLine("Failed to load simple vertex shader");
			return false;
		}

		let fragResult = mShaderLibrary.GetShader("simple", .Fragment);
		if (fragResult case .Err)
		{
			Console.WriteLine("Failed to load simple fragment shader");
			return false;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mColorBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) case .Ok(let pipeLayout))
			mColorPipelineLayout = pipeLayout;
		else
			return false;

		// Vertex attributes for ColorVertex
		VertexAttribute[2] vertexAttributes = .(
			.(.Float3, 0, 0),                           // Position at offset 0, location 0
			.(.Float4, (.)sizeof(Vector3), 1)           // Color at offset 12, location 1
		);
		VertexBufferLayout[1] vertexLayouts = .(
			.((.)sizeof(ColorVertex), vertexAttributes, .Vertex)
		);

		// Color target
		ColorTargetState[1] colorTargets = .(.(mSwapChain.Format));

		// Create pipeline
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mColorPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertResult.Value.Module, "main"),
				Buffers = vertexLayouts
			},
			Fragment = .()
			{
				Shader = .(fragResult.Value.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = .()
			{
				Format = .Depth24PlusStencil8,
				DepthTestEnabled = true,
				DepthWriteEnabled = true,
				DepthCompare = .Less
			},
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (mDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
		{
			mColorPipeline = pipeline;
			return true;
		}

		return false;
	}

	private bool CreateTexturedPipeline()
	{
		// Create bind group layout for textured pipeline (uniforms + texture + sampler)
		BindGroupLayoutEntry[4] layoutEntries = .(
			.UniformBuffer(0, .Vertex),              // CameraData at register(b0)
			.UniformBuffer(1, .Vertex),              // ObjectData at register(b1)
			.SampledTexture(0, .Fragment),           // Texture at register(t0)
			.Sampler(0, .Fragment)                   // Sampler at register(s0)
		);
		BindGroupLayoutDescriptor texLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&texLayoutDesc) case .Ok(let bgLayout))
			mTexturedBindGroupLayout = bgLayout;
		else
			return false;

		// Load shaders
		let vertResult = mShaderLibrary.GetShader("textured", .Vertex);
		if (vertResult case .Err)
		{
			Console.WriteLine("Failed to load textured vertex shader");
			return false;
		}

		let fragResult = mShaderLibrary.GetShader("textured", .Fragment);
		if (fragResult case .Err)
		{
			Console.WriteLine("Failed to load textured fragment shader");
			return false;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mTexturedBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) case .Ok(let pipeLayout))
			mTexturedPipelineLayout = pipeLayout;
		else
			return false;

		// Vertex attributes for TexturedVertex
		VertexAttribute[3] vertexAttributes = .(
			.(.Float3, 0, 0),                                          // Position at offset 0, location 0
			.(.Float3, (.)sizeof(Vector3), 1),                         // Normal at offset 12, location 1
			.(.Float2, (.)sizeof(Vector3) + (.)sizeof(Vector3), 2)     // UV at offset 24, location 2
		);
		VertexBufferLayout[1] vertexLayouts = .(
			.((.)sizeof(TexturedVertex), vertexAttributes, .Vertex)
		);

		// Color target
		ColorTargetState[1] colorTargets = .(.(mSwapChain.Format));

		// Create pipeline
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mTexturedPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertResult.Value.Module, "main"),
				Buffers = vertexLayouts
			},
			Fragment = .()
			{
				Shader = .(fragResult.Value.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = .()
			{
				Format = .Depth24PlusStencil8,
				DepthTestEnabled = true,
				DepthWriteEnabled = true,
				DepthCompare = .Less
			},
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (mDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
		{
			mTexturedPipeline = pipeline;
			return true;
		}

		return false;
	}

	private bool CreateTriangleMesh()
	{
		// Create a simple colored triangle
		ColorVertex[3] vertices = .(
			.(.(0.0f, 0.5f, 0.0f), .(1.0f, 0.0f, 0.0f, 1.0f)),    // Top - Red
			.(.(0.5f, -0.5f, 0.0f), .(0.0f, 1.0f, 0.0f, 1.0f)),   // Bottom right - Green
			.(.(-0.5f, -0.5f, 0.0f), .(0.0f, 0.0f, 1.0f, 1.0f))   // Bottom left - Blue
		);

		Span<uint8> vertexData = .((.)&vertices[0], sizeof(ColorVertex) * 3);
		mTriangleMesh = mResourceManager.CreateStaticMeshFromData(
			vertexData,
			(.)sizeof(ColorVertex),
			3
		);

		return mTriangleMesh.IsValid;
	}

	private bool CreateCubeMesh()
	{
		// Create a textured cube with proper normals and UVs
		// Each face has 4 vertices with unique normals and UVs
		TexturedVertex[24] vertices = .();
		uint16[36] indices = .();

		// Front face (z = 0.5)
		vertices[0] = .(.(-0.5f, -0.5f, 0.5f), .(0, 0, 1), .(0, 1));
		vertices[1] = .(.(0.5f, -0.5f, 0.5f), .(0, 0, 1), .(1, 1));
		vertices[2] = .(.(0.5f, 0.5f, 0.5f), .(0, 0, 1), .(1, 0));
		vertices[3] = .(.(-0.5f, 0.5f, 0.5f), .(0, 0, 1), .(0, 0));
		indices[0] = 0; indices[1] = 1; indices[2] = 2;
		indices[3] = 0; indices[4] = 2; indices[5] = 3;

		// Back face (z = -0.5)
		vertices[4] = .(.(0.5f, -0.5f, -0.5f), .(0, 0, -1), .(0, 1));
		vertices[5] = .(.(-0.5f, -0.5f, -0.5f), .(0, 0, -1), .(1, 1));
		vertices[6] = .(.(-0.5f, 0.5f, -0.5f), .(0, 0, -1), .(1, 0));
		vertices[7] = .(.(0.5f, 0.5f, -0.5f), .(0, 0, -1), .(0, 0));
		indices[6] = 4; indices[7] = 5; indices[8] = 6;
		indices[9] = 4; indices[10] = 6; indices[11] = 7;

		// Right face (x = 0.5)
		vertices[8] = .(.(0.5f, -0.5f, 0.5f), .(1, 0, 0), .(0, 1));
		vertices[9] = .(.(0.5f, -0.5f, -0.5f), .(1, 0, 0), .(1, 1));
		vertices[10] = .(.(0.5f, 0.5f, -0.5f), .(1, 0, 0), .(1, 0));
		vertices[11] = .(.(0.5f, 0.5f, 0.5f), .(1, 0, 0), .(0, 0));
		indices[12] = 8; indices[13] = 9; indices[14] = 10;
		indices[15] = 8; indices[16] = 10; indices[17] = 11;

		// Left face (x = -0.5)
		vertices[12] = .(.(-0.5f, -0.5f, -0.5f), .(-1, 0, 0), .(0, 1));
		vertices[13] = .(.(-0.5f, -0.5f, 0.5f), .(-1, 0, 0), .(1, 1));
		vertices[14] = .(.(-0.5f, 0.5f, 0.5f), .(-1, 0, 0), .(1, 0));
		vertices[15] = .(.(-0.5f, 0.5f, -0.5f), .(-1, 0, 0), .(0, 0));
		indices[18] = 12; indices[19] = 13; indices[20] = 14;
		indices[21] = 12; indices[22] = 14; indices[23] = 15;

		// Top face (y = 0.5)
		vertices[16] = .(.(-0.5f, 0.5f, 0.5f), .(0, 1, 0), .(0, 1));
		vertices[17] = .(.(0.5f, 0.5f, 0.5f), .(0, 1, 0), .(1, 1));
		vertices[18] = .(.(0.5f, 0.5f, -0.5f), .(0, 1, 0), .(1, 0));
		vertices[19] = .(.(-0.5f, 0.5f, -0.5f), .(0, 1, 0), .(0, 0));
		indices[24] = 16; indices[25] = 17; indices[26] = 18;
		indices[27] = 16; indices[28] = 18; indices[29] = 19;

		// Bottom face (y = -0.5)
		vertices[20] = .(.(-0.5f, -0.5f, -0.5f), .(0, -1, 0), .(0, 1));
		vertices[21] = .(.(0.5f, -0.5f, -0.5f), .(0, -1, 0), .(1, 1));
		vertices[22] = .(.(0.5f, -0.5f, 0.5f), .(0, -1, 0), .(1, 0));
		vertices[23] = .(.(-0.5f, -0.5f, 0.5f), .(0, -1, 0), .(0, 0));
		indices[30] = 20; indices[31] = 21; indices[32] = 22;
		indices[33] = 20; indices[34] = 22; indices[35] = 23;

		Span<uint8> vertexData = .((.)&vertices[0], sizeof(TexturedVertex) * 24);
		Span<uint8> indexData = .((.)&indices[0], sizeof(uint16) * 36);

		mCubeMesh = mResourceManager.CreateStaticMeshFromData(
			vertexData,
			(.)sizeof(TexturedVertex),
			24,
			indexData,
			.UInt16
		);

		return mCubeMesh.IsValid;
	}

	private bool CreateCheckerTexture()
	{
		// Create a 64x64 checkerboard texture
		const int32 SIZE = 64;
		const int32 CHECKER_SIZE = 8;
		uint8[SIZE * SIZE * 4] pixels = .();

		for (int32 y = 0; y < SIZE; y++)
		{
			for (int32 x = 0; x < SIZE; x++)
			{
				int32 checkerX = x / CHECKER_SIZE;
				int32 checkerY = y / CHECKER_SIZE;
				bool isWhite = ((checkerX + checkerY) % 2) == 0;

				int32 idx = (y * SIZE + x) * 4;
				if (isWhite)
				{
					pixels[idx + 0] = 255;  // R
					pixels[idx + 1] = 255;  // G
					pixels[idx + 2] = 255;  // B
					pixels[idx + 3] = 255;  // A
				}
				else
				{
					pixels[idx + 0] = 64;   // R
					pixels[idx + 1] = 64;   // G
					pixels[idx + 2] = 64;   // B
					pixels[idx + 3] = 255;  // A
				}
			}
		}

		// Create texture
		TextureDescriptor texDesc = .Texture2D(SIZE, SIZE, .RGBA8Unorm, .Sampled | .CopyDst);
		texDesc.Label = "CheckerTexture";

		if (mDevice.CreateTexture(&texDesc) case .Ok(let tex))
			mCheckerTexture = tex;
		else
			return false;

		// Upload texture data
		TextureDataLayout layout = .();
		layout.BytesPerRow = SIZE * 4;
		layout.RowsPerImage = SIZE;

		Extent3D extent = .(SIZE, SIZE, 1);

		mDevice.Queue.WriteTexture(
			mCheckerTexture,
			.(&pixels[0], SIZE * SIZE * 4),
			&layout,
			&extent
		);

		// Create texture view
		TextureViewDescriptor viewDesc = .();
		viewDesc.Dimension = .Texture2D;
		viewDesc.Format = .RGBA8Unorm;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = 1;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = 1;
		viewDesc.Aspect = .All;

		if (mDevice.CreateTextureView(mCheckerTexture, &viewDesc) case .Ok(let view))
			mCheckerTextureView = view;
		else
			return false;

		return true;
	}

	private bool CreateBindGroups()
	{
		// Create color bind group (uniforms only)
		BindGroupEntry[2] colorEntries = .(
			.Buffer(0, mCameraBuffer, 0, (.)sizeof(CameraUniformData)),
			.Buffer(1, mObjectBuffer, 0, (.)sizeof(ObjectUniformData))
		);
		BindGroupDescriptor colorBgDesc = .(mColorBindGroupLayout, colorEntries);
		if (mDevice.CreateBindGroup(&colorBgDesc) case .Ok(let colorBg))
			mColorBindGroup = colorBg;
		else
			return false;

		// Create textured bind group (uniforms + texture + sampler)
		BindGroupEntry[4] texturedEntries = .(
			.Buffer(0, mCameraBuffer, 0, (.)sizeof(CameraUniformData)),
			.Buffer(1, mObjectBuffer, 0, (.)sizeof(ObjectUniformData)),
			.Texture(0, mCheckerTextureView),
			.Sampler(0, mLinearSampler)
		);
		BindGroupDescriptor texturedBgDesc = .(mTexturedBindGroupLayout, texturedEntries);
		if (mDevice.CreateBindGroup(&texturedBgDesc) case .Ok(let texturedBg))
			mTexturedBindGroup = texturedBg;
		else
			return false;

		return true;
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("SandboxNext shutting down...");

		// Release meshes
		if (mTriangleMesh.IsValid)
			mResourceManager.ReleaseStaticMesh(mTriangleMesh);
		if (mCubeMesh.IsValid)
			mResourceManager.ReleaseStaticMesh(mCubeMesh);

		// Clean up texture resources
		if (mCheckerTextureView != null) delete mCheckerTextureView;
		if (mCheckerTexture != null) delete mCheckerTexture;
		if (mLinearSampler != null) delete mLinearSampler;

		// Clean up depth buffer
		if (mDepthTextureView != null) delete mDepthTextureView;
		if (mDepthTexture != null) delete mDepthTexture;

		// Clean up color pipeline resources
		if (mColorPipeline != null) delete mColorPipeline;
		if (mColorPipelineLayout != null) delete mColorPipelineLayout;
		if (mColorBindGroup != null) delete mColorBindGroup;
		if (mColorBindGroupLayout != null) delete mColorBindGroupLayout;

		// Clean up textured pipeline resources
		if (mTexturedPipeline != null) delete mTexturedPipeline;
		if (mTexturedPipelineLayout != null) delete mTexturedPipelineLayout;
		if (mTexturedBindGroup != null) delete mTexturedBindGroup;
		if (mTexturedBindGroupLayout != null) delete mTexturedBindGroupLayout;

		// Clean up shared resources
		if (mCameraBuffer != null) delete mCameraBuffer;
		if (mObjectBuffer != null) delete mObjectBuffer;
	}

	protected override void OnUpdate(float deltaTime)
	{
		// Check for ESC to exit
		let keyboard = mShell.InputManager.Keyboard;
		if (keyboard.IsKeyPressed(.Escape))
			Stop();

		// Toggle mode with space
		if (keyboard.IsKeyPressed(.Space))
		{
			mShowTexturedCube = !mShowTexturedCube;
			Console.WriteLine(mShowTexturedCube ? "Showing textured cube" : "Showing colored triangle");
		}

		// Animate rotation
		mRotation += deltaTime * 1.0f;
	}

	protected override void OnRender()
	{
		if (mShowTexturedCube)
			RenderTexturedCube();
		else
			RenderColoredTriangle();
	}

	private void RenderColoredTriangle()
	{
		// Update camera uniform (orthographic, no transformation)
		CameraUniformData cameraData = .()
		{
			ViewProjection = Matrix.Identity,
			CameraPosition = .(0, 0, -5),
			_pad0 = 0
		};
		mDevice.Queue.WriteBuffer(mCameraBuffer, 0, .((.)&cameraData, sizeof(CameraUniformData)));

		// Update object uniform with rotation
		ObjectUniformData objectData = .()
		{
			WorldMatrix = Matrix.CreateRotationZ(mRotation)
		};
		mDevice.Queue.WriteBuffer(mObjectBuffer, 0, .((.)&objectData, sizeof(ObjectUniformData)));

		// Import swap chain and depth
		let swapChainTexture = mSwapChain.CurrentTexture;
		let swapChainView = mSwapChain.CurrentTextureView;
		let colorHandle = mRenderGraph.ImportTexture("SwapChain", swapChainTexture, swapChainView);
		let depthHandle = mRenderGraph.ImportTexture("Depth", mDepthTexture, mDepthTextureView);

		// Clear pass
		let clearPass = new ClearPass();
		clearPass.SetRenderTarget(colorHandle, depthHandle);
		clearPass.SetClearColor(.(0.1f, 0.1f, 0.15f, 1.0f));
		clearPass.SetViewport(mSwapChain.Width, mSwapChain.Height);
		mRenderGraph.AddPass(clearPass);

		// Geometry pass
		let mesh = mResourceManager.GetStaticMesh(mTriangleMesh);
		if (mesh != null && mColorPipeline != null)
		{
			let geometryPass = new GeometryPass();
			geometryPass.SetRenderTargets(colorHandle, depthHandle, mSwapChain.Width, mSwapChain.Height);
			geometryPass.SetPipeline(mColorPipeline);
			geometryPass.SetCameraBindGroup(mColorBindGroup);
			geometryPass.AddDrawItem(mesh, Matrix.Identity, null);
			mRenderGraph.AddPass(geometryPass);
		}
	}

	private void RenderTexturedCube()
	{
		// Setup perspective camera
		float aspect = (float)mWidth / (float)mHeight;
		Matrix projection = Matrix.CreatePerspectiveFieldOfView(
			Math.PI_f / 4.0f,  // 45 degree FOV
			aspect,
			0.1f,
			100.0f
		);

		// Camera looking at origin from distance
		Vector3 cameraPos = .(0, 1.5f, 3.0f);
		Matrix view = Matrix.CreateLookAt(cameraPos, .(0, 0, 0), .(0, 1, 0));

		CameraUniformData cameraData = .()
		{
			ViewProjection = view * projection,
			CameraPosition = cameraPos,
			_pad0 = 0
		};
		mDevice.Queue.WriteBuffer(mCameraBuffer, 0, .((.)&cameraData, sizeof(CameraUniformData)));

		// Rotate cube around Y axis
		ObjectUniformData objectData = .()
		{
			WorldMatrix = Matrix.CreateRotationY(mRotation)
		};
		mDevice.Queue.WriteBuffer(mObjectBuffer, 0, .((.)&objectData, sizeof(ObjectUniformData)));

		// Import swap chain and depth
		let swapChainTexture = mSwapChain.CurrentTexture;
		let swapChainView = mSwapChain.CurrentTextureView;
		let colorHandle = mRenderGraph.ImportTexture("SwapChain", swapChainTexture, swapChainView);
		let depthHandle = mRenderGraph.ImportTexture("Depth", mDepthTexture, mDepthTextureView);

		// Clear pass
		let clearPass = new ClearPass();
		clearPass.SetRenderTarget(colorHandle, depthHandle);
		clearPass.SetClearColor(.(0.1f, 0.1f, 0.15f, 1.0f));
		clearPass.SetViewport(mSwapChain.Width, mSwapChain.Height);
		mRenderGraph.AddPass(clearPass);

		// Geometry pass for textured cube
		let mesh = mResourceManager.GetStaticMesh(mCubeMesh);
		if (mesh != null && mTexturedPipeline != null)
		{
			let geometryPass = new GeometryPass();
			geometryPass.SetRenderTargets(colorHandle, depthHandle, mSwapChain.Width, mSwapChain.Height);
			geometryPass.SetPipeline(mTexturedPipeline);
			geometryPass.SetCameraBindGroup(mTexturedBindGroup);
			geometryPass.AddDrawItem(mesh, Matrix.Identity, null);
			mRenderGraph.AddPass(geometryPass);
		}
	}

	protected override void OnResize(int32 width, int32 height)
	{
		Console.WriteLine($"Window resized to {width}x{height}");

		// Recreate depth buffer for new size
		if (mDepthTextureView != null)
		{
			delete mDepthTextureView;
			mDepthTextureView = null;
		}
		if (mDepthTexture != null)
		{
			delete mDepthTexture;
			mDepthTexture = null;
		}

		CreateDepthBuffer();
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope SandboxApplication();
		app.Run();
		return 0;
	}
}
