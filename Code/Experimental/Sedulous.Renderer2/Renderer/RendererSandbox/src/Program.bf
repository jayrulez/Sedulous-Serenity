namespace RendererSandbox;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RendererSandboxApp();
		return app.Run(.()
		{
			Title = "Renderer Sandbox",
			Width = 1280, Height = 720
		});
	}
}
