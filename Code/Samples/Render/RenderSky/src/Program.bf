namespace RenderSky;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderSkyApp();
		return app.Run(.()
		{
			Title = "Render Sky - Sky Mode Demo",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
