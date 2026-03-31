namespace StormTactics.Client;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope StormTacticsGame();

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

		return app.Run(.()
		{
			Title = "Storm Tactics",
			Width = 1600, Height = 900,
			EnableDepth = true
		});
	}
}
