namespace RenderCinematic;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderCinematicApp();
		return app.Run(.()
		{
			Title = "Render Cinematic - DOF, Motion Blur, Film Grain, Color Grading",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
