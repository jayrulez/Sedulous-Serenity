namespace RenderMultiView;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderMultiViewApp();
		return app.Run(.()
		{
			Title = "Render Multi-View - Split Screen",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
