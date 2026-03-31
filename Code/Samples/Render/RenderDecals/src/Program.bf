namespace RenderDecals;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderDecalsApp();
		return app.Run(.()
		{
			Title = "Render Decals - Screen-Space Projected Decals",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
