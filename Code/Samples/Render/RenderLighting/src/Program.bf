namespace RenderLighting;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderLightingApp();
		return app.Run(.()
		{
			Title = "Render Lighting - Clustered Lights & Shadows",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
