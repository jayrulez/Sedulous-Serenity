namespace RenderScene;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderSceneApp();
		return app.Run(.()
		{
			Title = "Render Scene - Large Scale Scene Management",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
