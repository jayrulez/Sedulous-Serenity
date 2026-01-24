namespace ImpactArena;

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
		let shell = new SDL3Shell();
		defer delete shell;

		if (shell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return 1;
		}

		let backend = new VulkanBackend(enableValidation: true);
		defer delete backend;

		if (!backend.IsInitialized)
		{
			Console.WriteLine("Failed to initialize Vulkan backend");
			return 1;
		}

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

		let settings = ApplicationSettings()
		{
			Title = "Impact Arena",
			Width = 1600,
			Height = 900,
			EnableDepth = true,
			PresentMode = .Mailbox,
			ClearColor = .(0.02f, 0.02f, 0.05f, 1.0f)
		};

		let app = scope ImpactArenaGame(shell, device, backend);
		return app.Run(settings);
	}
}
