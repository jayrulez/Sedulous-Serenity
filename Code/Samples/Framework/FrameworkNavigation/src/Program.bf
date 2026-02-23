namespace FrameworkNavigation;

using System;
using System.Collections;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;
using Sedulous.Framework.Runtime;

class Program
{
	public static int Main(String[] args)
	{
		// Create and initialize shell (SDL3)
		let shell = new SDL3Shell();
		defer delete shell;

		if (shell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return 1;
		}

		// Create Vulkan backend with validation
		let backend = new VulkanBackend(enableValidation: true);
		defer delete backend;

		if (!backend.IsInitialized)
		{
			Console.WriteLine("Failed to initialize Vulkan backend");
			return 1;
		}

		// Enumerate adapters and create device
		List<IAdapter> adapters = scope .();
		backend.EnumerateAdapters(adapters);

		if (adapters.Count == 0)
		{
			Console.WriteLine("No GPU adapters found");
			return 1;
		}

		Console.WriteLine($"Using adapter: {adapters[0].Info.Name}");

		IDevice device;
		switch (adapters[0].CreateDevice())
		{
		case .Ok(let d): device = d;
		case .Err:
			Console.WriteLine("Failed to create device");
			return 1;
		}
		defer delete device;

		// Application settings
		let settings = ApplicationSettings()
		{
			Title = "Navigation Demo",
			Width = 1280,
			Height = 720,
			EnableDepth = true,
			PresentMode = .Mailbox,
			ClearColor = .(0.08f, 0.08f, 0.12f, 1.0f)
		};

		let app = scope FrameworkNavigationApp(shell, device, backend);
		return app.Run(settings);
	}
}
