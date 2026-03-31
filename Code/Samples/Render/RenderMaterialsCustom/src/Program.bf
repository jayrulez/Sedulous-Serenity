namespace RenderMaterialsCustom;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderMaterialsCustomApp();
		return app.Run(.()
		{
			Title = "Render Materials Custom - Material Styles",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
