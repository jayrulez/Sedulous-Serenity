namespace StormTactics.Client;

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
			Title = "Storm Tactics",
			Width = 1600,
			Height = 900,
			EnableDepth = true,
			PresentMode = .Mailbox,
			ClearColor = .(0.1f, 0.12f, 0.15f, 1.0f)
		};

		let app = scope StormTacticsGame(shell, device, backend);

		// Parse command-line arguments
		for (int i = 0; i < args.Count; i++)
		{
			if (args[i] == "--local")
			{
				app.SetLocalMode();
				Console.WriteLine("Local save mode enabled");
			}
			else if (args[i] == "--server")
			{
				if (i + 1 < args.Count && !args[i + 1].StartsWith("--"))
				{
					// Parse host:port
					let arg = StringView(args[i + 1]);
					let colonIdx = arg.LastIndexOf(':');
					var host = StringView("127.0.0.1");
					uint16 port = 8080;
					if (colonIdx >= 0)
					{
						host = arg[0..<colonIdx];
						if (uint16.Parse(arg[(colonIdx + 1)...]) case .Ok(let p))
							port = p;
					}
					else
					{
						host = arg;
					}
					app.SetServerMode(host, port);
					i++;
				}
			}
		}

		return app.Run(settings);
	}
}
