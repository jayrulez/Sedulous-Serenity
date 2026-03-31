namespace RenderIntegrated;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderIntegratedApp();
		return app.Run(.()
		{
			Title = "Render Integrated - Full Feature Demo",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
