namespace TowerDefense.Data;

/// Current state of the game.
enum GameState
{
	/// At the main menu.
	MainMenu,

	/// Waiting to start the first wave.
	WaitingToStart,

	/// A wave is in progress.
	WaveInProgress,

	/// Between waves, waiting for player to start next.
	WavePaused,

	/// Game is paused by the player.
	Paused,

	/// Player has won (all waves completed).
	Victory,

	/// Player has lost (lives reached 0).
	GameOver
}
