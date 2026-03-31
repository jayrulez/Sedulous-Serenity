namespace RenderScreenEffects;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderScreenEffectsApp();
		return app.Run(.()
		{
			Title = "Render Screen Effects - SSAO, SSR, Contact Shadows",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
