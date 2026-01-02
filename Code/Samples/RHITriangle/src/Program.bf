using System;
using System.IO;
using System.Collections;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;  // Only needed for backend instantiation
using Sedulous.RHI.HLSLShaderCompiler;

namespace RHITriangle;

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
				Title = "RHI Triangle",
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

		// Get the window
		sWindow = window;

		if (sWindow == null)
		{
			Console.WriteLine("No window available");
			return 1;
		}

		// Create Vulkan backend
		sBackend = new VulkanBackend(false);
		defer delete sBackend;

		if (!sBackend.IsInitialized)
		{
			Console.WriteLine("Failed to initialize Vulkan backend");
			return 1;
		}

		// Create surface from window
		if (sBackend.CreateSurface(sWindow.NativeHandle) case .Ok(let surface))
		{
			sSurface = surface;
		}
		else
		{
			Console.WriteLine("Failed to create surface");
			return 1;
		}
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
		if (adapters[0].CreateDevice() case .Ok(let device))
		{
			sDevice = device;
		}
		else
		{
			Console.WriteLine("Failed to create device");
			return 1;
		}
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

		if (sDevice.CreateSwapChain(sSurface, &swapChainDesc) case .Ok(let swapChain))
		{
			sSwapChain = swapChain;
		}
		else
		{
			Console.WriteLine("Failed to create swap chain");
			return 1;
		}
		defer delete sSwapChain;

		Console.WriteLine(scope $"Swap chain created: {sSwapChain.Width}x{sSwapChain.Height}");

		// Load shaders
		if (!LoadShaders())
		{
			Console.WriteLine("Failed to load shaders");
			return 1;
		}
		defer { delete sVertShader; delete sFragShader; }

		// Create pipeline layout (no bindings for simple triangle)
		PipelineLayoutDescriptor layoutDesc = .();
		if (sDevice.CreatePipelineLayout(&layoutDesc) case .Ok(let layout))
		{
			sPipelineLayout = layout;
		}
		else
		{
			Console.WriteLine("Failed to create pipeline layout");
			return 1;
		}
		defer delete sPipelineLayout;

		// Create render pipeline
		if (!CreatePipeline())
		{
			Console.WriteLine("Failed to create render pipeline");
			return 1;
		}
		defer delete sPipeline;

		Console.WriteLine("RHI Triangle running. Press Escape to exit.");

		// Main loop
		while (sShell.IsRunning)
		{
			sShell.ProcessEvents();

			if (sShell.InputManager.Keyboard.IsKeyPressed(.Escape))
			{
				sShell.RequestExit();
				continue;
			}

			// Render frame
			RenderFrame();
		}

		sDevice.WaitIdle();
		Console.WriteLine("RHI Triangle finished.");
		return 0;
	}

	private static bool LoadShaders()
	{
		// Create shader compiler
		let compiler = scope HLSLCompiler();
		if (!compiler.IsInitialized)
		{
			Console.WriteLine("Failed to initialize shader compiler");
			return false;
		}

		// Shader directory is in the project folder (working directory when running from IDE)
		StringView shaderDir = "shaders";

		Console.WriteLine(scope $"Compiling shaders from: {shaderDir}");

		// Load and compile vertex shader
		String vertSource = scope .();
		if (!ReadTextFile(scope $"{shaderDir}/triangle.vert.hlsl", vertSource))
		{
			Console.WriteLine("Failed to read vertex shader source");
			return false;
		}

		let vertResult = compiler.Compile(vertSource, "main", .Vertex, .SPIRV);
		defer delete vertResult;
		if (!vertResult.Success)
		{
			Console.WriteLine(scope $"Vertex shader compilation failed: {vertResult.Errors}");
			return false;
		}

		Console.WriteLine("Vertex shader compiled successfully");

		// Create vertex shader module
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
		if (!ReadTextFile(scope $"{shaderDir}/triangle.frag.hlsl", fragSource))
		{
			Console.WriteLine("Failed to read fragment shader source");
			delete sVertShader;
			return false;
		}

		let fragResult = compiler.Compile(fragSource, "main", .Fragment, .SPIRV);
		defer delete fragResult;
		if (!fragResult.Success)
		{
			Console.WriteLine(scope $"Fragment shader compilation failed: {fragResult.Errors}");
			delete sVertShader;
			return false;
		}

		Console.WriteLine("Fragment shader compiled successfully");

		// Create fragment shader module
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

	private static bool CreatePipeline()
	{
		// Vertex data is hardcoded in the shader, no vertex input needed

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

		// Vertex state (no vertex buffers)
		VertexState vertex = .()
			{
				Shader = .(sVertShader, "main"),
				Buffers = default
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
			// Need to recreate swap chain
			HandleResize();
			return;
		}

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
				ClearValue = .(0.0f, 0.2f, 0.4f, 1.0f)
			});

		RenderPassDescriptor renderPassDesc = .(colorAttachments);

		let renderPass = encoder.BeginRenderPass(&renderPassDesc);
		if (renderPass == null)
			return;
		defer delete renderPass;

		// Draw triangle
		renderPass.SetPipeline(sPipeline);
		renderPass.SetViewport(0, 0, sSwapChain.Width, sSwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, sSwapChain.Width, sSwapChain.Height);
		renderPass.Draw(3, 1, 0, 0);
		renderPass.End();

		// Finish recording
		let commandBuffer = encoder.Finish();
		if (commandBuffer == null)
			return;
		defer delete commandBuffer;

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

		// Recreate swap chain
		if (sSwapChain.Resize((uint32)sWindow.Width, (uint32)sWindow.Height) case .Err)
		{
			Console.WriteLine("Failed to resize swap chain");
		}
	}
}
