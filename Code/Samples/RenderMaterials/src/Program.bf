namespace RenderMaterials;

using System;
using System.Collections;
using Sedulous.Shell.SDL3;
using Sedulous.RHI.Vulkan;
using Sedulous.RHI;
using Sedulous.Framework.Runtime;

class Program
{
	public static int Main(String[] args)
	{
		let shell = new SDL3Shell();
		defer { shell.Shutdown(); delete shell; }
		if (shell.Initialize() case .Err) { Console.WriteLine("Failed to initialize shell"); return -1; }

		let backend = new VulkanBackend(enableValidation: true);
		defer delete backend;
		if (!backend.IsInitialized) { Console.WriteLine("Failed to initialize Vulkan backend"); return -1; }

		List<IAdapter> adapters = scope .();
		backend.EnumerateAdapters(adapters);
		if (adapters.Count == 0) { Console.WriteLine("No GPU adapters found"); return -1; }
		Console.WriteLine("Using adapter: {0}", adapters[0].Info.Name);

		let device = adapters[0].CreateDevice().GetValueOrDefault();
		if (device == null) { Console.WriteLine("Failed to create device"); return -1; }
		defer delete device;

		let settings = ApplicationSettings()
		{
			Title = "Render Materials - PBR Parameter Grid",
			Width = 1280, Height = 720, EnableDepth = true,
			ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f)
		};

		let app = scope RenderMaterialsApp(shell, device, backend);
		return app.Run(settings);
	}
}
