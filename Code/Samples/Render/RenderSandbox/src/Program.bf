namespace RenderSandbox;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderSandboxApp();
		return app.Run(.()
		{
			Title = "RenderSandbox",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
