namespace EngineAnimation;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope EngineAnimationApp();
		return app.Run(.()
		{
			Title = "Animation Graph Demo",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
