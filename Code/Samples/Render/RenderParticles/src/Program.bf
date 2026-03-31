namespace RenderParticles;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderParticlesApp();
		return app.Run(.()
		{
			Title = "Render Particles - GPU Particle Systems",
			Width = 1024, Height = 768,
			EnableDepth = true
		});
	}
}
