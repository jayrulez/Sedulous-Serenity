namespace ImpactArena;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope ImpactArenaGame();
		return app.Run(.()
		{
			Title = "Impact Arena",
			Width = 1600, Height = 900,
			EnableDepth = true
		});
	}
}
