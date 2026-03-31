namespace EngineNavigation;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope EngineNavigationApp();
		return app.Run(.()
		{
			Title = "Navigation Demo",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
