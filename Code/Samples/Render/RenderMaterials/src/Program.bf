namespace RenderMaterials;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderMaterialsApp();
		return app.Run(.()
		{
			Title = "Render Materials - PBR Parameter Grid",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
