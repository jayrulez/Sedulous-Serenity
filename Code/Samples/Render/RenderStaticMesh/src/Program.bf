namespace RenderStaticMesh;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderStaticMeshApp();
		return app.Run(.()
		{
			Title = "Render Static Mesh - GLTF Model Loading",
			Width = 1024, Height = 768,
			EnableDepth = true
		});
	}
}
