namespace TowerDefense;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope TowerDefenseGame();
		return app.Run(.()
		{
			Title = "Tower Defense",
			Width = 1600, Height = 900,
			EnableDepth = true
		});
	}
}
