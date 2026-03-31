namespace RenderAsset;

using Sedulous.Runtime.Client;
using System;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderAssetApp();
		return app.Run(.()
		{
			Title = "Render Asset - Cache Demo",
			Width = 1280, Height = 720, EnableDepth = true,
			ClearColor = .(0.05f, 0.05f, 0.1f, 1.0f)
		});
	}
}
