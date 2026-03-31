namespace RenderWater;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderWaterApp();
		return app.Run(.()
		{
			Title = "RenderWater",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
