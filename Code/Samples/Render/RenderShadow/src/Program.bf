namespace RenderShadow;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderShadowApp();
		return app.Run(.()
		{
			Title = "Render Shadow - Shadow Mapping",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
