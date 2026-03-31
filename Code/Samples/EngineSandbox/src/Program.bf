namespace EngineSandbox;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope EngineSandboxApp();
		return app.Run(.()
		{
			Title = "Framework Sandbox",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
