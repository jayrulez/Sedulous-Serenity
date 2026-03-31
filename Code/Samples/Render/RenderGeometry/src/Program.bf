namespace RenderGeometry;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderGeometryApp();
		return app.Run(.()
		{
			Title = "Render Geometry - Basic Meshes",
			Width = 1024, Height = 768,
			EnableDepth = true
		});
	}
}
