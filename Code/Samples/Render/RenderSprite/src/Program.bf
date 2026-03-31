namespace RenderSprite;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RenderSpriteApp();
		return app.Run(.()
		{
			Title = "Render Sprite - Billboard Sprites",
			Width = 1024, Height = 768,
			EnableDepth = true
		});
	}
}
