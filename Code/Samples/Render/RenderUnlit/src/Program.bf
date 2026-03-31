namespace RenderUnlit;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderUnlitApp();
		return app.Run(.()
		{
			Title = "Render Unlit - Unlit vs PBR Materials",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
