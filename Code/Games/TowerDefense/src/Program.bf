namespace TowerDefense;

using System;

class Program
{
	public static int Main(String[] args)
	{
		let game = scope TowerDefenseGame();
		return game.Run();
	}
}
