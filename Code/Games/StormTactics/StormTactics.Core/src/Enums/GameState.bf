namespace StormTactics.Core;

enum GameState : int32
{
	Loading = 0,
	MainMenu = 1,
	City = 2,
	BattlePrepare = 3,
	Battle = 4,
	BattleResult = 5,
	Campaign = 6,
	Shop = 7,
	UnitManagement = 8,
	Arena = 9,
	Guild = 10,
	Settings = 11,
	Inventory = 12,
	Gacha = 13,
	Formation = 14,
	DailyChallenge = 15,
	BossRush = 16
}
