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
		int32 highScore, float waveIntroTimer, uint32 screenWidth, uint32 screenHeight,
		PowerUpType* inventory, int32 inventoryCount, int32 activeSlot)
	{
		mScreenWidth = screenWidth;
		mScreenHeight = screenHeight;

		switch (state)
		{
		case .Title:
			DrawTitle(highScore);
		case .Playing:
			DrawPlayingHUD(player, wave, enemiesLeft, score);
			DrawInventory(inventory, inventoryCount, activeSlot);
		case .WaveIntro:
			DrawPlayingHUD(player, wave, enemiesLeft, score);
			DrawInventory(inventory, inventoryCount, activeSlot);
			DrawWaveIntro(wave, waveIntroTimer);
		case .GameOver:
			DrawGameOver(score, highScore);
		case .Paused:
			DrawPlayingHUD(player, wave, enemiesLeft, score);
			DrawInventory(inventory, inventoryCount, activeSlot);
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

		// Top-center: Health bar
		let barWidth = 200.0f;
		let barHeight = 20.0f;
		let barX = ((float)mScreenWidth - barWidth) * 0.5f;
		let barY = 12.0f;

		mDebug.AddRect2D(barX - 2, barY - 2, barWidth + 4, barHeight + 4, Color(40, 40, 40, 200));

		let healthWidth = barWidth * player.HealthPercent;
		let healthColor = player.HealthPercent > 0.5f
			? Color(50, 200, 50, 255)
			: (player.HealthPercent > 0.25f ? Color(220, 200, 50, 255) : Color(220, 50, 50, 255));
		mDebug.AddRect2D(barX, barY, healthWidth, barHeight, healthColor);

		// Top-center-right: Dash cooldown (next to health bar)
		let dashX = barX + barWidth + 10;
		let dashY = barY;
		mDebug.AddRect2D(dashX - 2, dashY - 2, 64, barHeight + 4, Color(40, 40, 40, 200));
		let dashWidth = 60.0f * player.DashCooldownPercent;
		let dashColor = player.DashCooldownPercent >= 1.0f ? Color(100, 180, 255, 255) : Color(60, 80, 120, 200);
		mDebug.AddRect2D(dashX, dashY, dashWidth, barHeight, dashColor);
		mDebug.AddText2D("DASH", dashX + 10, dashY + 3, Color(255, 255, 255, 200), 0.9f);
	}

	private void DrawWaveIntro(int32 wave, float timer)
	{
		if (timer <= 0) return;
		let centerX = (float)mScreenWidth * 0.5f - 60;
		let centerY = (float)mScreenHeight * 0.4f;

		// Wave title
		let text = scope String();
		text.AppendF("WAVE {}", wave);
		mDebug.AddText2D(text, centerX, centerY, Color(255, 220, 100), 3.0f);

		// Countdown number
		int32 countdown = (int32)Math.Ceiling(timer);
		if (countdown > 3) countdown = 3;
		let countText = scope String();
		countText.AppendF("{}", countdown);
		let countX = (float)mScreenWidth * 0.5f - 10;
		let countY = centerY + 50;
		// Pulse: scale based on fractional part of timer
		let frac = timer - (float)Math.Floor(timer);
		let pulse = 1.0f + frac * 0.5f;
		let countAlpha = (uint8)Math.Min(255, (int32)(frac * 400));
		mDebug.AddText2D(countText, countX, countY, Color(255, 255, 255, countAlpha), 3.5f * pulse);
	}

	private void DrawInventory(PowerUpType* inventory, int32 count, int32 activeSlot)
	{
		let slotSize = 36.0f;
		let slotGap = 6.0f;
		let totalWidth = 3.0f * slotSize + 2.0f * slotGap;
		let startX = ((float)mScreenWidth - totalWidth) * 0.5f;
		let startY = (float)mScreenHeight - 50;

		for (int32 i = 0; i < 3; i++)
		{
			let x = startX + (float)i * (slotSize + slotGap);
			let isActive = (i == activeSlot && count > 0);

			// Slot background
			let bgColor = isActive ? Color(80, 80, 100, 220) : Color(30, 30, 40, 180);
			mDebug.AddRect2D(x, startY, slotSize, slotSize, bgColor);

			// Active slot border highlight
			if (isActive)
			{
				mDebug.AddRect2D(x - 2, startY - 2, slotSize + 4, 2, Color(255, 255, 255, 200));
				mDebug.AddRect2D(x - 2, startY + slotSize, slotSize + 4, 2, Color(255, 255, 255, 200));
				mDebug.AddRect2D(x - 2, startY, 2, slotSize, Color(255, 255, 255, 200));
				mDebug.AddRect2D(x + slotSize, startY, 2, slotSize, Color(255, 255, 255, 200));
			}

			// Draw item icon (colored text abbreviation)
			if (i < count)
			{
				StringView label;
				Color itemColor;
				switch (inventory[i])
				{
				case .SpeedBoost:
					label = "SPD";
					itemColor = Color(50, 220, 255);
				case .Shockwave:
					label = "SHK";
					itemColor = Color(180, 80, 255);
				case .EMP:
					label = "EMP";
					itemColor = Color(255, 230, 50);
				default:
					label = "?";
					itemColor = Color(200, 200, 200);
				}
				mDebug.AddText2D(label, x + 4, startY + 10, itemColor, 1.1f);
			}
		}

		// Controls hint
		if (count > 0)
		{
			mDebug.AddText2D("[E] Use  [</>] Cycle", startX - 10, startY + slotSize + 5,
				Color(150, 150, 150, 180), 0.7f);
		}
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
