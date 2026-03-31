namespace RenderTriangle;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderTriangleApp();
		return app.Run(.()
		{
			Title = "Render Triangle",
			Width = 800, Height = 600,
			EnableDepth = false
		});
	}
}
