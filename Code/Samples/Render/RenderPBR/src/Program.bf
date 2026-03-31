namespace RenderPBR;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderPBRApp();
		return app.Run(.()
		{
			Title = "Render PBR - Physically Based Rendering",
			Width = 1024, Height = 768,
			EnableDepth = true
		});
	}
}
