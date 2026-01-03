namespace RHIMRT;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using RHI.SampleFramework;

/// Vertex with position, normal, and color
[CRepr]
struct Vertex
{
	public float[3] Position;
	public float[3] Normal;
	public float[3] Color;

	public this(float px, float py, float pz, float nx, float ny, float nz, float r, float g, float b)
	{
		Position = .(px, py, pz);
		Normal = .(nx, ny, nz);
		Color = .(r, g, b);
	}
}

/// G-buffer pass uniforms
[CRepr]
struct GBufferUniforms
{
	public Matrix4x4 MVP;
	public Matrix4x4 Model;
}

/// Composite pass uniforms
[CRepr]
struct LightParams
{
	public float[3] LightDir;
	public float Padding1;
	public float[3] LightColor;
	public float Padding2;
	public float[3] AmbientColor;
	public float DisplayMode;
}

/// Demonstrates multiple render targets (MRT) for deferred rendering.
/// Press 1-4 to switch display modes: 1=Lit, 2=Albedo, 3=Normals, 4=Position
class MRTSample : RHISampleApp
{
	// Per-frame tracking for G-buffer command buffers
	private const int GBUFFER_BUFFER_COUNT = 3;
	private ICommandBuffer[GBUFFER_BUFFER_COUNT] mGBufferCommandBuffers;
	private int mGBufferFrameIndex = 0;

	// G-buffer textures
	private ITexture mAlbedoTexture;
	private ITexture mNormalTexture;
	private ITexture mPositionTexture;
	private ITexture mGBufferDepth;
	private ITextureView mAlbedoView;
	private ITextureView mNormalView;
	private ITextureView mPositionView;
	private ITextureView mGBufferDepthView;

	// G-buffer pass resources
	private IBuffer mCubeVertexBuffer;
	private IBuffer mCubeIndexBuffer;
	private IBuffer mGBufferUniformBuffer;
	private IShaderModule mGBufferVertShader;
	private IShaderModule mGBufferFragShader;
	private IBindGroupLayout mGBufferBindGroupLayout;
	private IBindGroup mGBufferBindGroup;
	private IPipelineLayout mGBufferPipelineLayout;
	private IRenderPipeline mGBufferPipeline;

	// Composite pass resources
	private IBuffer mLightParamsBuffer;
	private ISampler mSampler;
	private IShaderModule mCompositeVertShader;
	private IShaderModule mCompositeFragShader;
	private IBindGroupLayout mCompositeBindGroupLayout;
	private IBindGroup mCompositeBindGroup;
	private IPipelineLayout mCompositePipelineLayout;
	private IRenderPipeline mCompositePipeline;

	private int mDisplayMode = 0;  // 0=lit, 1=albedo, 2=normals, 3=position

	public this() : base(.()
		{
			Title = "RHI Multiple Render Targets",
			Width = 800,
			Height = 600,
			ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateGBufferTextures())
			return false;

		if (!CreateGeometry())
			return false;

		if (!CreateGBufferPipeline())
			return false;

		if (!CreateCompositePipeline())
			return false;

		Console.WriteLine("Press 1-4 to switch display modes:");
		Console.WriteLine("  1 = Lit (with lighting)");
		Console.WriteLine("  2 = Albedo only");
		Console.WriteLine("  3 = Normals");
		Console.WriteLine("  4 = World Position");
		return true;
	}

	private bool CreateGBufferTextures()
	{
		uint32 width = SwapChain.Width;
		uint32 height = SwapChain.Height;

		// Albedo texture (RGBA8)
		TextureDescriptor albedoDesc = TextureDescriptor.Texture2D(width, height, .RGBA8Unorm, .RenderTarget | .Sampled);
		if (Device.CreateTexture(&albedoDesc) not case .Ok(let tex))
			return false;
		mAlbedoTexture = tex;

		TextureViewDescriptor viewDesc = .();
		if (Device.CreateTextureView(mAlbedoTexture, &viewDesc) not case .Ok(let view))
			return false;
		mAlbedoView = view;

		// Normal texture (RGBA16F for better precision)
		TextureDescriptor normalDesc = TextureDescriptor.Texture2D(width, height, .RGBA16Float, .RenderTarget | .Sampled);
		if (Device.CreateTexture(&normalDesc) not case .Ok(let tex2))
			return false;
		mNormalTexture = tex2;

		TextureViewDescriptor normalViewDesc = .() { Format = .RGBA16Float };
		if (Device.CreateTextureView(mNormalTexture, &normalViewDesc) not case .Ok(let view2))
			return false;
		mNormalView = view2;

		// Position texture (RGBA32F for world coordinates)
		TextureDescriptor posDesc = TextureDescriptor.Texture2D(width, height, .RGBA32Float, .RenderTarget | .Sampled);
		if (Device.CreateTexture(&posDesc) not case .Ok(let tex3))
			return false;
		mPositionTexture = tex3;

		TextureViewDescriptor posViewDesc = .() { Format = .RGBA32Float };
		if (Device.CreateTextureView(mPositionTexture, &posViewDesc) not case .Ok(let view3))
			return false;
		mPositionView = view3;

		// Depth texture for G-buffer pass
		TextureDescriptor depthDesc = TextureDescriptor.Texture2D(width, height, .Depth24PlusStencil8, .DepthStencil);
		if (Device.CreateTexture(&depthDesc) not case .Ok(let tex4))
			return false;
		mGBufferDepth = tex4;

		TextureViewDescriptor depthViewDesc = .() { Format = .Depth24PlusStencil8 };
		if (Device.CreateTextureView(mGBufferDepth, &depthViewDesc) not case .Ok(let view4))
			return false;
		mGBufferDepthView = view4;

		Console.WriteLine("G-buffer textures created");
		return true;
	}

	private bool CreateGeometry()
	{
		// Create a colored cube
		Vertex[24] vertices = .(
			// Front face (red)
			.(-0.5f, -0.5f,  0.5f,  0, 0, 1, 1.0f, 0.3f, 0.3f),
			.( 0.5f, -0.5f,  0.5f,  0, 0, 1, 1.0f, 0.3f, 0.3f),
			.( 0.5f,  0.5f,  0.5f,  0, 0, 1, 1.0f, 0.3f, 0.3f),
			.(-0.5f,  0.5f,  0.5f,  0, 0, 1, 1.0f, 0.3f, 0.3f),
			// Back face (green)
			.( 0.5f, -0.5f, -0.5f,  0, 0,-1, 0.3f, 1.0f, 0.3f),
			.(-0.5f, -0.5f, -0.5f,  0, 0,-1, 0.3f, 1.0f, 0.3f),
			.(-0.5f,  0.5f, -0.5f,  0, 0,-1, 0.3f, 1.0f, 0.3f),
			.( 0.5f,  0.5f, -0.5f,  0, 0,-1, 0.3f, 1.0f, 0.3f),
			// Top face (blue)
			.(-0.5f,  0.5f,  0.5f,  0, 1, 0, 0.3f, 0.3f, 1.0f),
			.( 0.5f,  0.5f,  0.5f,  0, 1, 0, 0.3f, 0.3f, 1.0f),
			.( 0.5f,  0.5f, -0.5f,  0, 1, 0, 0.3f, 0.3f, 1.0f),
			.(-0.5f,  0.5f, -0.5f,  0, 1, 0, 0.3f, 0.3f, 1.0f),
			// Bottom face (yellow)
			.(-0.5f, -0.5f, -0.5f,  0,-1, 0, 1.0f, 1.0f, 0.3f),
			.( 0.5f, -0.5f, -0.5f,  0,-1, 0, 1.0f, 1.0f, 0.3f),
			.( 0.5f, -0.5f,  0.5f,  0,-1, 0, 1.0f, 1.0f, 0.3f),
			.(-0.5f, -0.5f,  0.5f,  0,-1, 0, 1.0f, 1.0f, 0.3f),
			// Right face (magenta)
			.( 0.5f, -0.5f,  0.5f,  1, 0, 0, 1.0f, 0.3f, 1.0f),
			.( 0.5f, -0.5f, -0.5f,  1, 0, 0, 1.0f, 0.3f, 1.0f),
			.( 0.5f,  0.5f, -0.5f,  1, 0, 0, 1.0f, 0.3f, 1.0f),
			.( 0.5f,  0.5f,  0.5f,  1, 0, 0, 1.0f, 0.3f, 1.0f),
			// Left face (cyan)
			.(-0.5f, -0.5f, -0.5f, -1, 0, 0, 0.3f, 1.0f, 1.0f),
			.(-0.5f, -0.5f,  0.5f, -1, 0, 0, 0.3f, 1.0f, 1.0f),
			.(-0.5f,  0.5f,  0.5f, -1, 0, 0, 0.3f, 1.0f, 1.0f),
			.(-0.5f,  0.5f, -0.5f, -1, 0, 0, 0.3f, 1.0f, 1.0f)
		);

		uint16[36] indices = .(
			0,1,2, 0,2,3,       // Front
			4,5,6, 4,6,7,       // Back
			8,9,10, 8,10,11,    // Top
			12,13,14, 12,14,15, // Bottom
			16,17,18, 16,18,19, // Right
			20,21,22, 20,22,23  // Left
		);

		// Create vertex buffer
		BufferDescriptor vertexDesc = .()
		{
			Size = (uint64)(sizeof(Vertex) * vertices.Count),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};
		if (Device.CreateBuffer(&vertexDesc) not case .Ok(let vb))
			return false;
		mCubeVertexBuffer = vb;
		Device.Queue.WriteBuffer(mCubeVertexBuffer, 0, .((uint8*)&vertices, (int)vertexDesc.Size));

		// Create index buffer
		BufferDescriptor indexDesc = .()
		{
			Size = (uint64)(sizeof(uint16) * indices.Count),
			Usage = .Index,
			MemoryAccess = .Upload
		};
		if (Device.CreateBuffer(&indexDesc) not case .Ok(let ib))
			return false;
		mCubeIndexBuffer = ib;
		Device.Queue.WriteBuffer(mCubeIndexBuffer, 0, .((uint8*)&indices, (int)indexDesc.Size));

		// Create uniform buffer for G-buffer pass
		BufferDescriptor uniformDesc = .()
		{
			Size = (uint64)sizeof(GBufferUniforms),
			Usage = .Uniform,
			MemoryAccess = .Upload
		};
		if (Device.CreateBuffer(&uniformDesc) not case .Ok(let ub))
			return false;
		mGBufferUniformBuffer = ub;

		// Create light params buffer for composite pass
		BufferDescriptor lightDesc = .()
		{
			Size = (uint64)sizeof(LightParams),
			Usage = .Uniform,
			MemoryAccess = .Upload
		};
		if (Device.CreateBuffer(&lightDesc) not case .Ok(let lb))
			return false;
		mLightParamsBuffer = lb;

		Console.WriteLine("Geometry created");
		return true;
	}

	private bool CreateGBufferPipeline()
	{
		// Load G-buffer shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/gbuffer");
		if (shaderResult case .Err)
			return false;
		(mGBufferVertShader, mGBufferFragShader) = shaderResult.Get();

		// Bind group layout
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mGBufferBindGroupLayout = layout;

		// Bind group
		BindGroupEntry[1] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mGBufferUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mGBufferBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mGBufferBindGroup = group;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mGBufferBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mGBufferPipelineLayout = pipelineLayout;

		// Vertex attributes
		VertexAttribute[3] vertexAttributes = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float3, 24, 2)   // Color
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// THREE color targets for MRT
		ColorTargetState[3] colorTargets = .(
			.(.RGBA8Unorm),     // Albedo
			.(.RGBA16Float),    // Normal
			.(.RGBA32Float)     // Position
		);

		// Depth stencil
		DepthStencilState depthStencil = .()
		{
			Format = .Depth24PlusStencil8,
			DepthWriteEnabled = true,
			DepthCompare = .Less,
			StencilFront = .(),
			StencilBack = .()
		};

		// Pipeline
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mGBufferPipelineLayout,
			Vertex = .()
			{
				Shader = .(mGBufferVertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(mGBufferFragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = depthStencil,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mGBufferPipeline = pipeline;

		Console.WriteLine("G-buffer pipeline created");
		return true;
	}

	private bool CreateCompositePipeline()
	{
		// Load composite shaders
		BindingShifts fragShifts = .() { Texture = 1, Sampler = 4 };  // t0-t2 -> 1-3, s0 -> 4
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/composite", .(), fragShifts);
		if (shaderResult case .Err)
			return false;
		(mCompositeVertShader, mCompositeFragShader) = shaderResult.Get();

		// Create sampler
		SamplerDescriptor samplerDesc = SamplerDescriptor.NearestClamp();
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return false;
		mSampler = sampler;

		// Bind group layout (3 textures + 1 sampler + 1 uniform)
		BindGroupLayoutEntry[5] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Fragment),
			BindGroupLayoutEntry.SampledTexture(1, .Fragment),
			BindGroupLayoutEntry.SampledTexture(2, .Fragment),
			BindGroupLayoutEntry.SampledTexture(3, .Fragment),
			BindGroupLayoutEntry.Sampler(4, .Fragment)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mCompositeBindGroupLayout = layout;

		// Bind group
		BindGroupEntry[5] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mLightParamsBuffer),
			BindGroupEntry.Texture(1, mAlbedoView),
			BindGroupEntry.Texture(2, mNormalView),
			BindGroupEntry.Texture(3, mPositionView),
			BindGroupEntry.Sampler(4, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mCompositeBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mCompositeBindGroup = group;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mCompositeBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mCompositePipelineLayout = pipelineLayout;

		// No vertex buffers needed - fullscreen triangle generated in shader
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		// Pipeline
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mCompositePipelineLayout,
			Vertex = .()
			{
				Shader = .(mCompositeVertShader, "main"),
				Buffers = default
			},
			Fragment = .()
			{
				Shader = .(mCompositeFragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = null,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mCompositePipeline = pipeline;

		Console.WriteLine("Composite pipeline created");
		return true;
	}

	protected override void OnInput()
	{
		// Switch display modes with number keys
		if (Shell.InputManager.Keyboard.IsKeyPressed(.Num1))
			mDisplayMode = 0;
		if (Shell.InputManager.Keyboard.IsKeyPressed(.Num2))
			mDisplayMode = 1;
		if (Shell.InputManager.Keyboard.IsKeyPressed(.Num3))
			mDisplayMode = 2;
		if (Shell.InputManager.Keyboard.IsKeyPressed(.Num4))
			mDisplayMode = 3;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Update G-buffer uniforms
		float angle = totalTime * 0.5f;
		let model = Matrix4x4.CreateRotationY(angle) * Matrix4x4.CreateRotationX(angle * 0.3f);

		float aspect = (float)SwapChain.Width / (float)SwapChain.Height;
		let projection = Matrix4x4.CreatePerspective(Math.PI_f / 4.0f, aspect, 0.1f, 100.0f);
		let view = Matrix4x4.CreateLookAt(.(0, 0, 3), .(0, 0, 0), .(0, 1, 0));

		GBufferUniforms gbufferUniforms = .()
		{
			MVP = projection * view * model,
			Model = model
		};
		Device.Queue.WriteBuffer(mGBufferUniformBuffer, 0, .((uint8*)&gbufferUniforms, sizeof(GBufferUniforms)));

		// Update light params
		LightParams lightParams = .()
		{
			LightDir = .(0.5f, -0.7f, 0.5f),  // Diagonal light
			Padding1 = 0,
			LightColor = .(1.0f, 0.95f, 0.9f),
			Padding2 = 0,
			AmbientColor = .(0.15f, 0.15f, 0.2f),
			DisplayMode = (float)mDisplayMode
		};
		Device.Queue.WriteBuffer(mLightParamsBuffer, 0, .((uint8*)&lightParams, sizeof(LightParams)));

		// Run G-buffer pass before the main render pass
		RenderGBufferPass();
	}

	private void RenderGBufferPass()
	{
		// Use per-frame tracking for command buffer lifetime
		let frameIndex = mGBufferFrameIndex;
		mGBufferFrameIndex = (mGBufferFrameIndex + 1) % GBUFFER_BUFFER_COUNT;

		// Clean up previous command buffer for this frame slot
		if (mGBufferCommandBuffers[frameIndex] != null)
		{
			delete mGBufferCommandBuffers[frameIndex];
			mGBufferCommandBuffers[frameIndex] = null;
		}

		let encoder = Device.CreateCommandEncoder();
		defer delete encoder;

		// G-buffer render pass with 3 color attachments
		RenderPassColorAttachment[3] colorAttachments = .(
			.() { View = mAlbedoView, LoadOp = .Clear, StoreOp = .Store, ClearValue = .(0, 0, 0, 1) },
			.() { View = mNormalView, LoadOp = .Clear, StoreOp = .Store, ClearValue = .(0.5f, 0.5f, 1, 1) },
			.() { View = mPositionView, LoadOp = .Clear, StoreOp = .Store, ClearValue = .(0, 0, 0, 1) }
		);

		RenderPassDepthStencilAttachment depthAttachment = .()
		{
			View = mGBufferDepthView,
			DepthLoadOp = .Clear,
			DepthStoreOp = .Store,
			DepthClearValue = 1.0f,
			StencilLoadOp = .Clear,
			StencilStoreOp = .Discard,
			StencilClearValue = 0
		};

		RenderPassDescriptor renderPassDesc = .(colorAttachments);
		renderPassDesc.DepthStencilAttachment = depthAttachment;

		let renderPass = encoder.BeginRenderPass(&renderPassDesc);
		defer delete renderPass;

		renderPass.SetPipeline(mGBufferPipeline);
		renderPass.SetBindGroup(0, mGBufferBindGroup);
		renderPass.SetVertexBuffer(0, mCubeVertexBuffer, 0);
		renderPass.SetIndexBuffer(mCubeIndexBuffer, .UInt16, 0);
		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);
		renderPass.DrawIndexed(36, 1, 0, 0, 0);
		renderPass.End();

		// Transition G-buffer textures from ColorAttachment to ShaderReadOnly
		// so they can be sampled in the composite pass
		encoder.TextureBarrier(mAlbedoTexture, .ColorAttachment, .ShaderReadOnly);
		encoder.TextureBarrier(mNormalTexture, .ColorAttachment, .ShaderReadOnly);
		encoder.TextureBarrier(mPositionTexture, .ColorAttachment, .ShaderReadOnly);

		let cmdBuffer = encoder.Finish();
		// Store for later deletion (after GPU is done)
		mGBufferCommandBuffers[frameIndex] = cmdBuffer;
		Device.Queue.Submit(cmdBuffer);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// The framework already started a render pass for the swap chain
		// We do the composite pass here (G-buffer was rendered in OnUpdate)
		renderPass.SetPipeline(mCompositePipeline);
		renderPass.SetBindGroup(0, mCompositeBindGroup);
		renderPass.Draw(3, 1, 0, 0);  // Fullscreen triangle
	}

	protected override void OnCleanup()
	{
		// Clean up G-buffer command buffers
		for (int i = 0; i < GBUFFER_BUFFER_COUNT; i++)
		{
			if (mGBufferCommandBuffers[i] != null)
			{
				delete mGBufferCommandBuffers[i];
				mGBufferCommandBuffers[i] = null;
			}
		}

		// Composite resources
		if (mCompositePipeline != null) delete mCompositePipeline;
		if (mCompositePipelineLayout != null) delete mCompositePipelineLayout;
		if (mCompositeBindGroup != null) delete mCompositeBindGroup;
		if (mCompositeBindGroupLayout != null) delete mCompositeBindGroupLayout;
		if (mCompositeFragShader != null) delete mCompositeFragShader;
		if (mCompositeVertShader != null) delete mCompositeVertShader;
		if (mSampler != null) delete mSampler;
		if (mLightParamsBuffer != null) delete mLightParamsBuffer;

		// G-buffer resources
		if (mGBufferPipeline != null) delete mGBufferPipeline;
		if (mGBufferPipelineLayout != null) delete mGBufferPipelineLayout;
		if (mGBufferBindGroup != null) delete mGBufferBindGroup;
		if (mGBufferBindGroupLayout != null) delete mGBufferBindGroupLayout;
		if (mGBufferFragShader != null) delete mGBufferFragShader;
		if (mGBufferVertShader != null) delete mGBufferVertShader;
		if (mGBufferUniformBuffer != null) delete mGBufferUniformBuffer;
		if (mCubeIndexBuffer != null) delete mCubeIndexBuffer;
		if (mCubeVertexBuffer != null) delete mCubeVertexBuffer;

		// G-buffer textures
		if (mGBufferDepthView != null) delete mGBufferDepthView;
		if (mGBufferDepth != null) delete mGBufferDepth;
		if (mPositionView != null) delete mPositionView;
		if (mPositionTexture != null) delete mPositionTexture;
		if (mNormalView != null) delete mNormalView;
		if (mNormalTexture != null) delete mNormalTexture;
		if (mAlbedoView != null) delete mAlbedoView;
		if (mAlbedoTexture != null) delete mAlbedoTexture;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope MRTSample();
		return app.Run();
	}
}
