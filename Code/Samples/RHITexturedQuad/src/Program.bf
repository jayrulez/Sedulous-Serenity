using System;
using System.IO;
using System.Collections;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Mathematics;
using Sedulous.Imaging;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;
using Sedulous.RHI.HLSLShaderCompiler;

namespace RHITexturedQuad;

/// Vertex structure with position and texture coordinates
[CRepr]
struct Vertex
{
	public float[2] Position;
	public float[2] TexCoord;

	public this(float x, float y, float u, float v)
	{
		Position = .(x, y);
		TexCoord = .(u, v);
	}
}

/// Uniform buffer data for the transform matrix
[CRepr]
struct Uniforms
{
	public Matrix4x4 Transform;
}

class Program
{
	private static SDL3Shell sShell;
	private static IWindow sWindow;
	private static IBackend sBackend;
	private static IDevice sDevice;
	private static ISurface sSurface;
	private static ISwapChain sSwapChain;
	private static IRenderPipeline sPipeline;
	private static IShaderModule sVertShader;
	private static IShaderModule sFragShader;
	private static IPipelineLayout sPipelineLayout;
	private static IBuffer sVertexBuffer;
	private static IBuffer sIndexBuffer;
	private static IBuffer sUniformBuffer;
	private static ITexture sTexture;
	private static ITextureView sTextureView;
	private static ISampler sSampler;
	private static IBindGroupLayout sBindGroupLayout;
	private static IBindGroup sBindGroup;

	// Per-frame command buffers
	private const int MAX_FRAMES_IN_FLIGHT = 2;
	private static ICommandBuffer[MAX_FRAMES_IN_FLIGHT] sCommandBuffers;

	// Time tracking for rotation
	private static System.Diagnostics.Stopwatch sStopwatch = new .() ~ delete _;

	public static int Main(String[] args)
	{
		// Initialize shell and create window
		sShell = new SDL3Shell();
		defer { sShell.Shutdown(); delete sShell; }

		if (sShell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return 1;
		}

		let windowSettings = WindowSettings()
			{
				Title = "RHI Textured Quad",
				Width = 800,
				Height = 600,
				Resizable = true,
				Bordered = true
			};

		if (sShell.WindowManager.CreateWindow(windowSettings) not case .Ok(let window))
		{
			Console.WriteLine("Failed to create window");
			return 1;
		}

		sWindow = window;

		// Create Vulkan backend
		sBackend = new VulkanBackend(true);
		defer delete sBackend;

		if (!sBackend.IsInitialized)
		{
			Console.WriteLine("Failed to initialize Vulkan backend");
			return 1;
		}

		// Create surface from window
		if (sBackend.CreateSurface(sWindow.NativeHandle) not case .Ok(let surface))
		{
			Console.WriteLine("Failed to create surface");
			return 1;
		}
		sSurface = surface;
		defer delete sSurface;

		// Get an adapter
		List<IAdapter> adapters = scope .();
		sBackend.EnumerateAdapters(adapters);

		if (adapters.Count == 0)
		{
			Console.WriteLine("No GPU adapters found");
			return 1;
		}

		Console.WriteLine(scope $"Using adapter: {adapters[0].Info.Name}");

		// Create device
		if (adapters[0].CreateDevice() not case .Ok(let device))
		{
			Console.WriteLine("Failed to create device");
			return 1;
		}
		sDevice = device;
		defer delete sDevice;

		// Create swap chain
		SwapChainDescriptor swapChainDesc = .()
			{
				Width = (uint32)sWindow.Width,
				Height = (uint32)sWindow.Height,
				Format = .BGRA8UnormSrgb,
				Usage = .RenderTarget,
				PresentMode = .Fifo
			};

		if (sDevice.CreateSwapChain(sSurface, &swapChainDesc) not case .Ok(let swapChain))
		{
			Console.WriteLine("Failed to create swap chain");
			return 1;
		}
		sSwapChain = swapChain;
		defer delete sSwapChain;

		Console.WriteLine(scope $"Swap chain created: {sSwapChain.Width}x{sSwapChain.Height}");

		// Create vertex buffer with quad data
		if (!CreateVertexBuffer())
		{
			Console.WriteLine("Failed to create vertex buffer");
			return 1;
		}
		defer delete sVertexBuffer;

		// Create index buffer
		if (!CreateIndexBuffer())
		{
			Console.WriteLine("Failed to create index buffer");
			return 1;
		}
		defer delete sIndexBuffer;

		// Create uniform buffer for rotation transform
		if (!CreateUniformBuffer())
		{
			Console.WriteLine("Failed to create uniform buffer");
			return 1;
		}
		defer delete sUniformBuffer;

		// Create checkerboard texture
		if (!CreateTexture())
		{
			Console.WriteLine("Failed to create texture");
			return 1;
		}
		defer { delete sTextureView; delete sTexture; }

		// Create sampler
		if (!CreateSampler())
		{
			Console.WriteLine("Failed to create sampler");
			return 1;
		}
		defer delete sSampler;

		// Create bind group layout (uniform buffer + texture + sampler)
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(1, .Fragment),
			BindGroupLayoutEntry.Sampler(2, .Fragment)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (sDevice.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let bindGroupLayout))
		{
			Console.WriteLine("Failed to create bind group layout");
			return 1;
		}
		sBindGroupLayout = bindGroupLayout;
		defer delete sBindGroupLayout;

		// Create bind group
		BindGroupEntry[3] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, sUniformBuffer),
			BindGroupEntry.Texture(1, sTextureView),
			BindGroupEntry.Sampler(2, sSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(sBindGroupLayout, bindGroupEntries);
		if (sDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let bindGroup))
		{
			Console.WriteLine("Failed to create bind group");
			return 1;
		}
		sBindGroup = bindGroup;
		defer delete sBindGroup;

		// Load shaders
		if (!LoadShaders())
		{
			Console.WriteLine("Failed to load shaders");
			return 1;
		}
		defer { delete sVertShader; delete sFragShader; }

		// Create pipeline layout
		IBindGroupLayout[1] bindGroupLayouts = .(sBindGroupLayout);
		PipelineLayoutDescriptor layoutDesc = .(bindGroupLayouts);
		if (sDevice.CreatePipelineLayout(&layoutDesc) not case .Ok(let layout))
		{
			Console.WriteLine("Failed to create pipeline layout");
			return 1;
		}
		sPipelineLayout = layout;
		defer delete sPipelineLayout;

		// Create render pipeline
		if (!CreatePipeline())
		{
			Console.WriteLine("Failed to create render pipeline");
			return 1;
		}
		defer delete sPipeline;

		Console.WriteLine("RHI Textured Quad running. Press Escape to exit.");

		// Start timing for rotation
		sStopwatch.Start();

		// Main loop
		while (sShell.IsRunning)
		{
			sShell.ProcessEvents();

			if (sShell.InputManager.Keyboard.IsKeyPressed(.Escape))
			{
				sShell.RequestExit();
				continue;
			}

			RenderFrame();
		}

		sDevice.WaitIdle();

		// Clean up per-frame command buffers
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (sCommandBuffers[i] != null)
			{
				delete sCommandBuffers[i];
				sCommandBuffers[i] = null;
			}
		}

		Console.WriteLine("RHI Textured Quad finished.");
		return 0;
	}

	private static bool LoadShaders()
	{
		let compiler = scope HLSLCompiler();
		if (!compiler.IsInitialized)
		{
			Console.WriteLine("Failed to initialize shader compiler");
			return false;
		}

		StringView shaderDir = "shaders";
		Console.WriteLine(scope $"Compiling shaders from: {shaderDir}");

		// Configure binding shifts for SPIRV:
		// - ConstantBufferShift = 0 (b0 → binding 0)
		// - TextureShift = 1 (t0 → binding 1)
		// - SamplerShift = 2 (s0 → binding 2)
		// This matches our bind group layout order: uniform, texture, sampler

		// Load and compile vertex shader
		String vertSource = scope .();
		if (!ReadTextFile(scope $"{shaderDir}/quad.vert.hlsl", vertSource))
		{
			Console.WriteLine("Failed to read vertex shader source");
			return false;
		}

		ShaderCompileOptions vertOptions = .Vertex("main", .SPIRV);
		// No shifts needed for vertex shader (only uses b0 → binding 0)

		let vertResult = compiler.Compile(vertSource, vertOptions);
		defer delete vertResult;
		if (!vertResult.Success)
		{
			Console.WriteLine(scope $"Vertex shader compilation failed: {vertResult.Errors}");
			return false;
		}

		Console.WriteLine("Vertex shader compiled successfully");

		ShaderModuleDescriptor vertDesc = .(vertResult.Bytecode);
		if (sDevice.CreateShaderModule(&vertDesc) case .Ok(let vertShader))
		{
			sVertShader = vertShader;
		}
		else
		{
			Console.WriteLine("Failed to create vertex shader module");
			return false;
		}

		// Load and compile fragment shader
		String fragSource = scope .();
		if (!ReadTextFile(scope $"{shaderDir}/quad.frag.hlsl", fragSource))
		{
			Console.WriteLine("Failed to read fragment shader source");
			delete sVertShader;
			return false;
		}

		ShaderCompileOptions fragOptions = .Fragment("main", .SPIRV);
		fragOptions.TextureShift = 1;   // t0 → binding 1
		fragOptions.SamplerShift = 2;   // s0 → binding 2

		let fragResult = compiler.Compile(fragSource, fragOptions);
		defer delete fragResult;
		if (!fragResult.Success)
		{
			Console.WriteLine(scope $"Fragment shader compilation failed: {fragResult.Errors}");
			delete sVertShader;
			return false;
		}

		Console.WriteLine("Fragment shader compiled successfully");

		ShaderModuleDescriptor fragDesc = .(fragResult.Bytecode);
		if (sDevice.CreateShaderModule(&fragDesc) case .Ok(let fragShader))
		{
			sFragShader = fragShader;
		}
		else
		{
			Console.WriteLine("Failed to create fragment shader module");
			delete sVertShader;
			return false;
		}

		return true;
	}

	private static bool ReadTextFile(StringView path, String outContent)
	{
		let stream = scope FileStream();
		if (stream.Open(path, .Read, .Read) case .Err)
			return false;

		let reader = scope StreamReader(stream);
		if (reader.ReadToEnd(outContent) case .Err)
			return false;

		return true;
	}

	private static bool CreateVertexBuffer()
	{
		// Define quad vertices (position + UV)
		// Counter-clockwise winding
		Vertex[4] vertices = .(
			.(-0.5f, -0.5f, 0.0f, 1.0f),  // Bottom-left
			.( 0.5f, -0.5f, 1.0f, 1.0f),  // Bottom-right
			.( 0.5f,  0.5f, 1.0f, 0.0f),  // Top-right
			.(-0.5f,  0.5f, 0.0f, 0.0f)   // Top-left
		);

		BufferDescriptor bufferDesc = .()
			{
				Size = (uint64)(sizeof(Vertex) * vertices.Count),
				Usage = .Vertex,
				MemoryAccess = .Upload
			};

		if (sDevice.CreateBuffer(&bufferDesc) not case .Ok(let buffer))
			return false;

		sVertexBuffer = buffer;

		Span<uint8> vertexData = .((uint8*)&vertices, (int)bufferDesc.Size);
		sDevice.Queue.WriteBuffer(sVertexBuffer, 0, vertexData);

		Console.WriteLine("Vertex buffer created");
		return true;
	}

	private static bool CreateIndexBuffer()
	{
		// Two triangles forming a quad
		uint16[6] indices = .(
			0, 1, 2,  // First triangle
			0, 2, 3   // Second triangle
		);

		BufferDescriptor bufferDesc = .()
			{
				Size = (uint64)(sizeof(uint16) * indices.Count),
				Usage = .Index,
				MemoryAccess = .Upload
			};

		if (sDevice.CreateBuffer(&bufferDesc) not case .Ok(let buffer))
			return false;

		sIndexBuffer = buffer;

		Span<uint8> indexData = .((uint8*)&indices, (int)bufferDesc.Size);
		sDevice.Queue.WriteBuffer(sIndexBuffer, 0, indexData);

		Console.WriteLine("Index buffer created");
		return true;
	}

	private static bool CreateUniformBuffer()
	{
		BufferDescriptor bufferDesc = .()
			{
				Size = (uint64)sizeof(Uniforms),
				Usage = .Uniform,
				MemoryAccess = .Upload
			};

		if (sDevice.CreateBuffer(&bufferDesc) not case .Ok(let buffer))
			return false;

		sUniformBuffer = buffer;

		// Initialize with identity matrix
		Uniforms uniforms = .() { Transform = Matrix4x4.Identity };
		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		sDevice.Queue.WriteBuffer(sUniformBuffer, 0, uniformData);

		Console.WriteLine("Uniform buffer created");
		return true;
	}

	private static bool CreateTexture()
	{
		// Generate checkerboard image using Sedulous.Imaging
		let image = Image.CreateCheckerboard(256, Color.White, Color(0.2f, 0.2f, 0.8f, 1.0f), 32, .RGBA8);
		defer delete image;

		Console.WriteLine(scope $"Created checkerboard image: {image.Width}x{image.Height}");

		// Create texture
		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			image.Width,
			image.Height,
			.RGBA8Unorm,
			.Sampled | .CopyDst
		);

		if (sDevice.CreateTexture(&textureDesc) not case .Ok(let texture))
		{
			Console.WriteLine("Failed to create texture");
			return false;
		}
		sTexture = texture;

		// Upload texture data
		TextureDataLayout dataLayout = .()
			{
				Offset = 0,
				BytesPerRow = image.Width * 4,  // 4 bytes per RGBA pixel
				RowsPerImage = image.Height
			};

		Extent3D writeSize = .(image.Width, image.Height, 1);
		sDevice.Queue.WriteTexture(sTexture, image.Data, &dataLayout, &writeSize);

		Console.WriteLine("Texture data uploaded");

		// Create texture view
		TextureViewDescriptor viewDesc = .();
		if (sDevice.CreateTextureView(sTexture, &viewDesc) not case .Ok(let textureView))
		{
			Console.WriteLine("Failed to create texture view");
			return false;
		}
		sTextureView = textureView;

		Console.WriteLine("Texture created successfully");
		return true;
	}

	private static bool CreateSampler()
	{
		// Use linear filtering with repeat wrapping
		SamplerDescriptor samplerDesc = SamplerDescriptor.LinearRepeat();

		if (sDevice.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return false;

		sSampler = sampler;
		Console.WriteLine("Sampler created");
		return true;
	}

	private static bool CreatePipeline()
	{
		// Define vertex attributes
		// Position: location 0, offset 0, Float2
		// TexCoord: location 1, offset 8 (2 floats * 4 bytes), Float2
		VertexAttribute[2] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),    // Position at location 0
			.(VertexFormat.Float2, 8, 1)     // TexCoord at location 1
		);

		// Define vertex buffer layout
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// Color target state
		ColorTargetState[1] colorTargets = .(.(sSwapChain.Format));

		// Multisample state
		MultisampleState multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue,
				AlphaToCoverageEnabled = false
			};

		// Primitive state
		PrimitiveState primitive = .()
			{
				Topology = .TriangleList,
				StripIndexFormat = .UInt16,
				FrontFace = .CCW,
				CullMode = .None
			};

		// Vertex state with buffer layout
		VertexState vertex = .()
			{
				Shader = .(sVertShader, "main"),
				Buffers = vertexBuffers
			};

		// Fragment state
		FragmentState fragment = .()
			{
				Shader = .(sFragShader, "main"),
				Targets = colorTargets
			};

		// Pipeline descriptor
		RenderPipelineDescriptor pipelineDesc = .()
			{
				Layout = sPipelineLayout,
				Vertex = vertex,
				Fragment = fragment,
				Primitive = primitive,
				DepthStencil = null,
				Multisample = multisample
			};

		if (sDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
		{
			sPipeline = pipeline;
			return true;
		}

		return false;
	}

	private static void RenderFrame()
	{
		// Acquire next swap chain image
		if (sSwapChain.AcquireNextImage() case .Err)
		{
			HandleResize();
			return;
		}

		// Clean up previous command buffer for this frame slot
		let frameIndex = sSwapChain.CurrentFrameIndex;
		if (sCommandBuffers[frameIndex] != null)
		{
			delete sCommandBuffers[frameIndex];
			sCommandBuffers[frameIndex] = null;
		}

		// Update rotation based on elapsed time
		float elapsedSeconds = (float)sStopwatch.Elapsed.TotalSeconds;
		float rotationAngle = elapsedSeconds * 0.5f;  // Slower rotation

		// Create rotation matrix around Z axis
		Uniforms uniforms = .() { Transform = Matrix4x4.CreateRotationZ(rotationAngle) };
		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		sDevice.Queue.WriteBuffer(sUniformBuffer, 0, uniformData);

		// Get current texture view
		let textureView = sSwapChain.CurrentTextureView;
		if (textureView == null)
			return;

		// Create command encoder
		let encoder = sDevice.CreateCommandEncoder();
		if (encoder == null)
			return;
		defer delete encoder;

		// Begin render pass
		RenderPassColorAttachment[1] colorAttachments = .(.()
			{
				View = textureView,
				ResolveTarget = null,
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = .(0.1f, 0.1f, 0.1f, 1.0f)  // Dark gray background
			});

		RenderPassDescriptor renderPassDesc = .(colorAttachments);

		let renderPass = encoder.BeginRenderPass(&renderPassDesc);
		if (renderPass == null)
			return;
		defer delete renderPass;

		// Draw textured quad
		renderPass.SetPipeline(sPipeline);
		renderPass.SetBindGroup(0, sBindGroup);
		renderPass.SetVertexBuffer(0, sVertexBuffer, 0);
		renderPass.SetIndexBuffer(sIndexBuffer, .UInt16, 0);
		renderPass.SetViewport(0, 0, sSwapChain.Width, sSwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, sSwapChain.Width, sSwapChain.Height);
		renderPass.DrawIndexed(6, 1, 0, 0, 0);  // 6 indices, 1 instance
		renderPass.End();

		// Finish recording
		let commandBuffer = encoder.Finish();
		if (commandBuffer == null)
			return;

		// Store command buffer for later deletion
		sCommandBuffers[frameIndex] = commandBuffer;

		// Submit commands with swap chain synchronization
		sDevice.Queue.Submit(commandBuffer, sSwapChain);

		// Present
		if (sSwapChain.Present() case .Err)
		{
			HandleResize();
		}
	}

	private static void HandleResize()
	{
		sDevice.WaitIdle();

		// Clean up per-frame command buffers
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (sCommandBuffers[i] != null)
			{
				delete sCommandBuffers[i];
				sCommandBuffers[i] = null;
			}
		}

		// Recreate swap chain
		if (sSwapChain.Resize((uint32)sWindow.Width, (uint32)sWindow.Height) case .Err)
		{
			Console.WriteLine("Failed to resize swap chain");
		}
	}
}
