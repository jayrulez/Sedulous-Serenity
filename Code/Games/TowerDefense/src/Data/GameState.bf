namespace TowerDefense.Data;

/// Current state of the game.
enum GameState
{
	/// Waiting to start the first wave.
	WaitingToStart,

	/// A wave is in progress.
	WaveInProgress,

	/// Between waves, waiting for player to start next.
	WavePaused,

	/// Player has won (all waves completed).
	Victory,

	/// Player has lost (lives reached 0).
	GameOver
}
