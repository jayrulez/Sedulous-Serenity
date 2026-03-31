namespace EngineRender;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope EngineRenderApp();
		return app.Run(.()
		{
			Title = "Framework Render - Sphere Stress Test",
			Width = 1366, Height = 768,
			EnableDepth = true
		});
	}
}
