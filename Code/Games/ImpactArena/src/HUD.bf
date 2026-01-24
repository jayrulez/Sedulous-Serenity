namespace ImpactArena;

using System;
using Sedulous.Render;
using Sedulous.Mathematics;

class HUD
{
	private DebugRenderFeature mDebug;
	private uint32 mScreenWidth;
	private uint32 mScreenHeight;

	public void Initialize(DebugRenderFeature debug)
	{
		mDebug = debug;
	}

	public void Draw(GameState state, Player player, int32 wave, int32 enemiesLeft, int32 score,
		int32 highScore, float waveIntroTimer, uint32 screenWidth, uint32 screenHeight)
	{
		mScreenWidth = screenWidth;
		mScreenHeight = screenHeight;

		switch (state)
		{
		case .Title:
			DrawTitle(highScore);
		case .Playing:
			DrawPlayingHUD(player, wave, enemiesLeft, score);
		case .WaveIntro:
			DrawPlayingHUD(player, wave, enemiesLeft, score);
			DrawWaveIntro(wave, waveIntroTimer);
		case .GameOver:
			DrawGameOver(score, highScore);
		case .Paused:
			DrawPlayingHUD(player, wave, enemiesLeft, score);
			DrawPaused();
		}
	}

	private void DrawTitle(int32 highScore)
	{
		let centerX = (float)mScreenWidth * 0.5f - 100;
		let centerY = (float)mScreenHeight * 0.5f;

		mDebug.AddRect2D(centerX - 50, centerY - 60, 300, 140, Color(0, 0, 0, 200));
		mDebug.AddText2D("IMPACT ARENA", centerX - 20, centerY - 45, Color(100, 180, 255), 2.5f);
		mDebug.AddText2D("Press SPACE to start", centerX + 10, centerY + 10, Color(200, 200, 200), 1.2f);

		if (highScore > 0)
		{
			let hsText = scope String();
			hsText.AppendF("High Score: {}", highScore);
			mDebug.AddText2D(hsText, centerX + 30, centerY + 40, Color(255, 220, 100), 1.0f);
		}

		mDebug.AddText2D("WASD: Move   SPACE: Dash   ESC: Exit", centerX - 30, centerY + 65, Color(150, 150, 150), 0.9f);
	}

	private void DrawPlayingHUD(Player player, int32 wave, int32 enemiesLeft, int32 score)
	{
		// Top-left: Wave and enemies
		mDebug.AddRect2D(5, 5, 180, 55, Color(0, 0, 0, 180));
		let waveText = scope String();
		waveText.AppendF("Wave {}", wave);
		mDebug.AddText2D(waveText, 15, 12, Color(255, 220, 100), 1.5f);
		let enemyText = scope String();
		enemyText.AppendF("Enemies: {}", enemiesLeft);
		mDebug.AddText2D(enemyText, 15, 38, Color(200, 200, 200), 1.0f);

		// Top-right: Score
		let scoreX = (float)mScreenWidth - 160;
		mDebug.AddRect2D(scoreX, 5, 155, 35, Color(0, 0, 0, 180));
		let scoreText = scope String();
		scoreText.AppendF("Score: {}", score);
		mDebug.AddText2D(scoreText, scoreX + 10, 14, Color(100, 255, 100), 1.3f);

		// Bottom-center: Health bar
		let barWidth = 200.0f;
		let barHeight = 20.0f;
		let barX = ((float)mScreenWidth - barWidth) * 0.5f;
		let barY = (float)mScreenHeight - 40;

		mDebug.AddRect2D(barX - 2, barY - 2, barWidth + 4, barHeight + 4, Color(40, 40, 40, 200));

		let healthWidth = barWidth * player.HealthPercent;
		let healthColor = player.HealthPercent > 0.5f
			? Color(50, 200, 50, 255)
			: (player.HealthPercent > 0.25f ? Color(220, 200, 50, 255) : Color(220, 50, 50, 255));
		mDebug.AddRect2D(barX, barY, healthWidth, barHeight, healthColor);

		// Bottom-right: Dash cooldown
		let dashX = (float)mScreenWidth - 80;
		let dashY = (float)mScreenHeight - 40;
		mDebug.AddRect2D(dashX - 2, dashY - 2, 64, barHeight + 4, Color(40, 40, 40, 200));
		let dashWidth = 60.0f * player.DashCooldownPercent;
		let dashColor = player.DashCooldownPercent >= 1.0f ? Color(100, 180, 255, 255) : Color(60, 80, 120, 200);
		mDebug.AddRect2D(dashX, dashY, dashWidth, barHeight, dashColor);
		mDebug.AddText2D("DASH", dashX + 10, dashY + 3, Color(255, 255, 255, 200), 0.9f);
	}

	private void DrawWaveIntro(int32 wave, float timer)
	{
		if (timer <= 0) return;
		let alpha = (uint8)Math.Min(255, (int32)(timer * 200));
		let centerX = (float)mScreenWidth * 0.5f - 60;
		let centerY = (float)mScreenHeight * 0.4f;

		let text = scope String();
		text.AppendF("WAVE {}", wave);
		mDebug.AddText2D(text, centerX, centerY, Color(255, 220, 100, alpha), 3.0f);
	}

	private void DrawGameOver(int32 score, int32 highScore)
	{
		let centerX = (float)mScreenWidth * 0.5f - 80;
		let centerY = (float)mScreenHeight * 0.5f;

		mDebug.AddRect2D(centerX - 40, centerY - 50, 260, 130, Color(0, 0, 0, 220));
		mDebug.AddText2D("GAME OVER", centerX - 10, centerY - 35, Color(220, 50, 50), 2.5f);

		let scoreText = scope String();
		scoreText.AppendF("Score: {}", score);
		mDebug.AddText2D(scoreText, centerX + 20, centerY + 10, Color(200, 200, 200), 1.3f);

		if (score >= highScore && score > 0)
			mDebug.AddText2D("NEW HIGH SCORE!", centerX + 10, centerY + 35, Color(255, 220, 100), 1.2f);

		mDebug.AddText2D("Press SPACE to restart", centerX + 5, centerY + 60, Color(150, 150, 150), 1.0f);
	}

	private void DrawPaused()
	{
		let centerX = (float)mScreenWidth * 0.5f - 50;
		let centerY = (float)mScreenHeight * 0.5f;

		mDebug.AddRect2D(centerX - 20, centerY - 25, 160, 60, Color(0, 0, 0, 220));
		mDebug.AddText2D("PAUSED", centerX, centerY - 10, Color(200, 200, 200), 2.0f);
		mDebug.AddText2D("ESC to resume", centerX + 5, centerY + 20, Color(150, 150, 150), 1.0f);
	}
}
