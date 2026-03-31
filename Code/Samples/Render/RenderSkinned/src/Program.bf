namespace RenderSkinned;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderSkinnedApp();
		return app.Run(.()
		{
			Title = "Render Skinned - Skeletal Animation",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
