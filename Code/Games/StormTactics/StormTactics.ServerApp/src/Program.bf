namespace StormTactics.ServerApp;

using System;
using StormTactics.Server;

class Program
{
	public static int Main(String[] args)
	{
		Console.WriteLine("=== StormTactics Server ===");

		let config = scope ServerConfig();

		// Parse command-line arguments
		for (int i = 0; i < args.Count; i++)
		{
			if (args[i] == "--port" && i + 1 < args.Count)
			{
				if (uint16.Parse(args[i + 1]) case .Ok(let port))
					config.mPort = port;
				i++;
			}
			else if (args[i] == "--data-dir" && i + 1 < args.Count)
			{
				config.mDataDir.Set(args[i + 1]);
				i++;
			}
		}

		let server = scope GameServer();

		if (server.Initialize(config) case .Err)
		{
			Console.WriteLine("Failed to initialize server");
			return 1;
		}

		if (server.Start() case .Err)
		{
			Console.WriteLine("Failed to start server");
			return 1;
		}

		Console.WriteLine("Server running on port {}", config.mPort);
		Console.WriteLine("Press Ctrl+C to stop");

		// Main loop
		while (true)
		{
			server.Update();
			System.Threading.Thread.Sleep(10);
		}
	}
}
