using System;
using Sedulous.Shell.SDL3;
using Sedulous.RHI.Vulkan;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Framework.Runtime;
namespace RenderSandbox;

class Program
{
	public static int Main(String[] args)
	{
		// Create and initialize shell
		let shell = new SDL3Shell();
		defer { shell.Shutdown(); delete shell; }

		if (shell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return -1;
		}

		// Create Vulkan backend
		let backend = new VulkanBackend(enableValidation: true);
		defer delete backend;

		if (!backend.IsInitialized)
		{
			Console.WriteLine("Failed to initialize Vulkan backend");
			return -1;
		}

		// Enumerate adapters and create device
		List<IAdapter> adapters = scope .();
		backend.EnumerateAdapters(adapters);

		if (adapters.Count == 0)
		{
			Console.WriteLine("No GPU adapters found");
			return -1;
		}

		Console.WriteLine("Using adapter: {0}", adapters[0].Info.Name);

		let device = adapters[0].CreateDevice().GetValueOrDefault();
		if (device == null)
		{
			Console.WriteLine("Failed to create device");
			return -1;
		}
		defer delete device;

		// Create and run application
		let settings = ApplicationSettings()
		{
			Title = "RenderSandbox",
			Width = 1280,
			Height = 720,
			EnableDepth = true,
			ClearColor = .(0.2f, 0.3f, 0.4f, 1.0f)
		};

		let app = scope RenderIntegratedApp(shell, device, backend);
		return app.Run(settings);
	}
}