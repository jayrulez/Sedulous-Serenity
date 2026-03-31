namespace RenderTerrain;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderTerrainApp();
		return app.Run(.()
		{
			Title = "RenderTerrain",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
