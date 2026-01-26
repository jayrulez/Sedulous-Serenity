namespace ImpactArena;

using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;

class HUD
{
	private DrawContext mDrawContext;
	private uint32 mScreenWidth;
	private uint32 mScreenHeight;

	// Font sizes - FontService now supports multiple sizes per family
	private const float FontSmall = 14;
	private const float FontNormal = 18;
	private const float FontLarge = 24;
	private const float FontTitle = 32;
	private const float FontHuge = 48;

	public void Initialize(DrawContext drawContext)
	{
		mDrawContext = drawContext;
	}

	public void Draw(GameState state, Player player, int32 wave, int32 enemiesLeft, int32 score,
		int32 highScore, float waveIntroTimer, uint32 screenWidth, uint32 screenHeight,
		PowerUpType* inventory, int32 inventoryCount, int32 activeSlot, float totalTime)
	{
		mScreenWidth = screenWidth;
		mScreenHeight = screenHeight;

		switch (state)
		{
		case .Title:
			DrawTitle(highScore, totalTime);
		case .Playing:
			DrawPlayingHUD(player, wave, enemiesLeft, score);
			DrawInventory(inventory, inventoryCount, activeSlot, totalTime);
		case .WaveIntro:
			DrawPlayingHUD(player, wave, enemiesLeft, score);
			DrawInventory(inventory, inventoryCount, activeSlot, totalTime);
			DrawWaveIntro(wave, waveIntroTimer);
		case .GameOver:
			DrawGameOver(score, highScore);
		case .Paused:
			DrawPlayingHUD(player, wave, enemiesLeft, score);
			DrawInventory(inventory, inventoryCount, activeSlot, totalTime);
			DrawPaused();
		}
	}

	private void DrawTitle(int32 highScore, float time)
	{
		let screenW = (float)mScreenWidth;
		let screenH = (float)mScreenHeight;
		let centerX = screenW * 0.5f;
		let centerY = screenH * 0.5f;

		// Full-screen darkened overlay
		mDrawContext.FillRect(.(0, 0, screenW, screenH), Color(0, 0, 0, 180));

		// Animated background accents - diagonal lines
		let lineColor = Color(40, 80, 120, 60);
		let lineSpacing = 80.0f;
		let lineOffset = (time * 30.0f) % lineSpacing;
		for (float x = -screenH + lineOffset; x < screenW + screenH; x += lineSpacing)
		{
			// Draw diagonal line segments
			for (float y = 0; y < screenH; y += 4)
			{
				let x1 = x + y;
				if (x1 >= 0 && x1 < screenW)
					mDrawContext.FillRect(.(x1, y, 2, 3), lineColor);
			}
		}

		// Main panel
		let panelW = 420.0f;
		let panelH = 280.0f;
		let panelX = centerX - panelW * 0.5f;
		let panelY = centerY - panelH * 0.5f - 20;

		// Panel shadow
		mDrawContext.FillRect(.(panelX + 6, panelY + 6, panelW, panelH), Color(0, 0, 0, 100));
		// Panel background
		mDrawContext.FillRect(.(panelX, panelY, panelW, panelH), Color(10, 15, 25, 240));

		// Animated border glow
		let glowPulse = (Math.Sin(time * 3.0f) + 1.0f) * 0.5f;
		let borderAlpha = (uint8)(80 + glowPulse * 80);
		let borderColor = Color(60, 140, 220, borderAlpha);
		let borderThick = 3.0f;
		// Top
		mDrawContext.FillRect(.(panelX, panelY, panelW, borderThick), borderColor);
		// Bottom
		mDrawContext.FillRect(.(panelX, panelY + panelH - borderThick, panelW, borderThick), borderColor);
		// Left
		mDrawContext.FillRect(.(panelX, panelY, borderThick, panelH), borderColor);
		// Right
		mDrawContext.FillRect(.(panelX + panelW - borderThick, panelY, borderThick, panelH), borderColor);

		// Corner accents
		let cornerSize = 20.0f;
		let accentColor = Color(100, 180, 255, 200);
		// Top-left
		mDrawContext.FillRect(.(panelX - 2, panelY - 2, cornerSize, 4), accentColor);
		mDrawContext.FillRect(.(panelX - 2, panelY - 2, 4, cornerSize), accentColor);
		// Top-right
		mDrawContext.FillRect(.(panelX + panelW - cornerSize + 2, panelY - 2, cornerSize, 4), accentColor);
		mDrawContext.FillRect(.(panelX + panelW - 2, panelY - 2, 4, cornerSize), accentColor);
		// Bottom-left
		mDrawContext.FillRect(.(panelX - 2, panelY + panelH - 2, cornerSize, 4), accentColor);
		mDrawContext.FillRect(.(panelX - 2, panelY + panelH - cornerSize + 2, 4, cornerSize), accentColor);
		// Bottom-right
		mDrawContext.FillRect(.(panelX + panelW - cornerSize + 2, panelY + panelH - 2, cornerSize, 4), accentColor);
		mDrawContext.FillRect(.(panelX + panelW - 2, panelY + panelH - cornerSize + 2, 4, cornerSize), accentColor);

		// Title with shadow
		let titleY = panelY + 35;
		// Shadow
		mDrawContext.DrawText("IMPACT ARENA", FontHuge, .(centerX - 135 + 3, titleY + 3), Color(0, 0, 0, 150));
		// Main title
		mDrawContext.DrawText("IMPACT ARENA", FontHuge, .(centerX - 135, titleY), Color(100, 180, 255));

		// Subtitle line
		let subY = titleY + 55;
		let lineW = 180.0f;
		mDrawContext.FillRect(.(centerX - lineW * 0.5f, subY, lineW, 2), Color(60, 120, 180, 150));
		mDrawContext.DrawText("SURVIVE THE ONSLAUGHT", FontSmall, .(centerX - 82, subY + 8), Color(150, 180, 210));

		// Pulsing "Press SPACE to start"
		let startY = panelY + 155;
		let startPulse = (Math.Sin(time * 4.0f) + 1.0f) * 0.5f;
		let startAlpha = (uint8)(150 + startPulse * 105);
		let startScale = 1.0f + startPulse * 0.05f;
		mDrawContext.DrawText("Press SPACE to start", FontLarge, .(centerX - 105 * startScale, startY), Color(255, 255, 255, startAlpha));

		// High score
		if (highScore > 0)
		{
			let hsY = panelY + 195;
			let hsText = scope String();
			hsText.AppendF("HIGH SCORE: {}", highScore);
			mDrawContext.DrawText(hsText, FontNormal, .(centerX - 65, hsY), Color(255, 200, 80));
		}

		// Controls section
		let ctrlY = panelY + 235;
		mDrawContext.FillRect(.(panelX + 20, ctrlY - 8, panelW - 40, 1), Color(60, 80, 100, 100));
		mDrawContext.DrawText("WASD Move    SPACE Dash    E Use Item    ESC Pause", FontSmall, .(centerX - 175, ctrlY), Color(120, 140, 160));
	}

	private void DrawPlayingHUD(Player player, int32 wave, int32 enemiesLeft, int32 score)
	{
		// Top-left: Wave and enemies panel
		let waveW = 160.0f;
		let waveH = 58.0f;
		// Panel shadow
		mDrawContext.FillRect(.(8, 8, waveW, waveH), Color(0, 0, 0, 80));
		// Panel background
		mDrawContext.FillRect(.(5, 5, waveW, waveH), Color(10, 15, 25, 220));
		// Left accent bar
		mDrawContext.FillRect(.(5, 5, 3, waveH), Color(255, 200, 80, 200));
		// Text
		let waveText = scope String();
		waveText.AppendF("WAVE {}", wave);
		mDrawContext.DrawText(waveText, FontLarge, .(18, 12), Color(255, 220, 100));
		let enemyText = scope String();
		enemyText.AppendF("Enemies: {}", enemiesLeft);
		mDrawContext.DrawText(enemyText, FontNormal, .(18, 36), Color(180, 190, 200));

		// Top-right: Score panel
		let scoreW = 140.0f;
		let scoreH = 38.0f;
		let scoreX = (float)mScreenWidth - scoreW - 5;
		// Panel shadow
		mDrawContext.FillRect(.(scoreX + 3, 8, scoreW, scoreH), Color(0, 0, 0, 80));
		// Panel background
		mDrawContext.FillRect(.(scoreX, 5, scoreW, scoreH), Color(10, 15, 25, 220));
		// Right accent bar
		mDrawContext.FillRect(.(scoreX + scoreW - 3, 5, 3, scoreH), Color(100, 255, 100, 200));
		// Text
		let scoreText = scope String();
		scoreText.AppendF("{}", score);
		mDrawContext.DrawText("SCORE", FontSmall, .(scoreX + 10, 10), Color(120, 140, 120));
		mDrawContext.DrawText(scoreText, FontLarge, .(scoreX + 10, 22), Color(100, 255, 100));

		// Top-center: Health bar
		let barWidth = 200.0f;
		let barHeight = 22.0f;
		let barX = ((float)mScreenWidth - barWidth) * 0.5f;
		let barY = 10.0f;

		// Bar background with border
		mDrawContext.FillRect(.(barX - 3, barY - 3, barWidth + 6, barHeight + 6), Color(10, 15, 25, 220));
		mDrawContext.FillRect(.(barX - 1, barY - 1, barWidth + 2, barHeight + 2), Color(40, 45, 55, 255));

		// Health fill with gradient effect (darker at bottom)
		let healthWidth = barWidth * player.HealthPercent;
		let healthColor = player.HealthPercent > 0.5f
			? Color(50, 200, 50, 255)
			: (player.HealthPercent > 0.25f ? Color(220, 180, 50, 255) : Color(220, 50, 50, 255));
		let healthColorDark = player.HealthPercent > 0.5f
			? Color(30, 140, 30, 255)
			: (player.HealthPercent > 0.25f ? Color(180, 140, 30, 255) : Color(180, 30, 30, 255));
		// Top half brighter
		mDrawContext.FillRect(.(barX, barY, healthWidth, barHeight * 0.5f), healthColor);
		// Bottom half darker
		mDrawContext.FillRect(.(barX, barY + barHeight * 0.5f, healthWidth, barHeight * 0.5f), healthColorDark);
		// Highlight line at top
		if (healthWidth > 2)
			mDrawContext.FillRect(.(barX + 1, barY + 1, healthWidth - 2, 2), Color(255, 255, 255, 60));

		// Dash cooldown (next to health bar)
		let dashW = 65.0f;
		let dashX = barX + barWidth + 12;
		let dashY = barY;
		// Background
		mDrawContext.FillRect(.(dashX - 3, dashY - 3, dashW + 6, barHeight + 6), Color(10, 15, 25, 220));
		mDrawContext.FillRect(.(dashX - 1, dashY - 1, dashW + 2, barHeight + 2), Color(40, 45, 55, 255));
		// Fill
		let dashFillW = (dashW - 1) * player.DashCooldownPercent;
		let dashReady = player.DashCooldownPercent >= 1.0f;
		let dashColor = dashReady ? Color(60, 140, 220, 255) : Color(40, 70, 100, 200);
		let dashColorDark = dashReady ? Color(40, 100, 180, 255) : Color(30, 50, 80, 200);
		mDrawContext.FillRect(.(dashX, dashY, dashFillW, barHeight * 0.5f), dashColor);
		mDrawContext.FillRect(.(dashX, dashY + barHeight * 0.5f, dashFillW, barHeight * 0.5f), dashColorDark);
		// Label
		let dashLabelColor = dashReady ? Color(255, 255, 255, 255) : Color(150, 160, 170, 200);
		mDrawContext.DrawText("DASH", FontSmall, .(dashX + 14, dashY + 4), dashLabelColor);
	}

	private void DrawWaveIntro(int32 wave, float timer)
	{
		if (timer <= 0) return;
		let screenW = (float)mScreenWidth;
		let screenH = (float)mScreenHeight;
		let centerX = screenW * 0.5f;
		let centerY = screenH * 0.48f; // Lower position to avoid combo text overlap

		// Darken background slightly - with more padding at bottom
		mDrawContext.FillRect(.(0, centerY - 50, screenW, 180), Color(0, 0, 0, 120));

		// Decorative lines
		let lineW = 120.0f;
		mDrawContext.FillRect(.(centerX - lineW - 100, centerY + 5, lineW, 2), Color(255, 200, 80, 150));
		mDrawContext.FillRect(.(centerX + 100, centerY + 5, lineW, 2), Color(255, 200, 80, 150));

		// Wave title with shadow
		let text = scope String();
		text.AppendF("WAVE {}", wave);
		// Shadow
		mDrawContext.DrawText(text, FontHuge, .(centerX - 78 + 3, centerY - 20 + 3), Color(0, 0, 0, 150));
		// Main text
		mDrawContext.DrawText(text, FontHuge, .(centerX - 78, centerY - 20), Color(255, 220, 100));

		// "GET READY" subtitle
		mDrawContext.DrawText("GET READY", FontNormal, .(centerX - 42, centerY + 25), Color(180, 190, 200));

		// Countdown number with pulse effect
		int32 countdown = (int32)Math.Ceiling(timer);
		if (countdown > 3) countdown = 3;
		let countText = scope String();
		countText.AppendF("{}", countdown);
		let countY = centerY + 65;
		// Pulse: scale and alpha based on fractional part of timer
		let frac = timer - (float)Math.Floor(timer);
		let countAlpha = (uint8)Math.Min(255, (int32)(frac * 400));
		let countScale = 1.0f + (1.0f - frac) * 0.3f;
		// Shadow
		mDrawContext.DrawText(countText, FontHuge, .(centerX - 12 * countScale + 2, countY + 2), Color(0, 0, 0, (uint8)(countAlpha * 0.5f)));
		// Main number
		mDrawContext.DrawText(countText, FontHuge, .(centerX - 12 * countScale, countY), Color(255, 255, 255, countAlpha));
	}

	private void DrawInventory(PowerUpType* inventory, int32 count, int32 activeSlot, float totalTime)
	{
		let slotSize = 40.0f;
		let slotGap = 8.0f;
		let totalWidth = 3.0f * slotSize + 2.0f * slotGap;
		let startX = ((float)mScreenWidth - totalWidth) * 0.5f;
		let startY = 45.0f; // Top of screen, below health bar

		for (int32 i = 0; i < 3; i++)
		{
			let x = startX + (float)i * (slotSize + slotGap);
			let isActive = (i == activeSlot && count > 0);
			let hasItem = i < count;

			// Slot shadow
			mDrawContext.FillRect(.(x + 2, startY + 2, slotSize, slotSize), Color(0, 0, 0, 60));

			// Slot background
			let bgColor = isActive ? Color(40, 50, 70, 230) : Color(15, 20, 30, 200);
			mDrawContext.FillRect(.(x, startY, slotSize, slotSize), bgColor);

			// Slot border
			let borderColor = isActive ? Color(100, 150, 220, 200) : Color(40, 50, 60, 150);
			mDrawContext.FillRect(.(x, startY, slotSize, 2), borderColor);
			mDrawContext.FillRect(.(x, startY + slotSize - 2, slotSize, 2), borderColor);
			mDrawContext.FillRect(.(x, startY, 2, slotSize), borderColor);
			mDrawContext.FillRect(.(x + slotSize - 2, startY, 2, slotSize), borderColor);

			// Active slot animated glow
			if (isActive)
			{
				let blink = (Math.Sin(totalTime * 6.0f) + 1.0f) * 0.5f;
				let glowAlpha = (uint8)(100 + blink * 100);
				let glowColor = Color(100, 180, 255, glowAlpha);
				// Outer glow effect
				mDrawContext.FillRect(.(x - 2, startY - 2, slotSize + 4, 2), glowColor);
				mDrawContext.FillRect(.(x - 2, startY + slotSize, slotSize + 4, 2), glowColor);
				mDrawContext.FillRect(.(x - 2, startY, 2, slotSize), glowColor);
				mDrawContext.FillRect(.(x + slotSize, startY, 2, slotSize), glowColor);
			}

			// Draw item icon
			if (hasItem)
			{
				StringView label;
				Color itemColor;
				Color itemBgColor;
				switch (inventory[i])
				{
				case .SpeedBoost:
					label = "SPD";
					itemColor = Color(80, 230, 255);
					itemBgColor = Color(30, 80, 100, 100);
				case .Shockwave:
					label = "SHK";
					itemColor = Color(200, 100, 255);
					itemBgColor = Color(60, 30, 80, 100);
				case .EMP:
					label = "EMP";
					itemColor = Color(255, 240, 80);
					itemBgColor = Color(80, 70, 30, 100);
				default:
					label = "?";
					itemColor = Color(200, 200, 200);
					itemBgColor = Color(50, 50, 50, 100);
				}
				// Item background tint
				mDrawContext.FillRect(.(x + 3, startY + 3, slotSize - 6, slotSize - 6), itemBgColor);
				// Item label
				mDrawContext.DrawText(label, FontNormal, .(x + 6, startY + 11), itemColor);
			}
			else
			{
				// Empty slot indicator
				mDrawContext.FillRect(.(x + slotSize * 0.5f - 1, startY + slotSize * 0.5f - 1, 2, 2), Color(40, 50, 60, 100));
			}

			// Slot number
			let numText = scope String();
			numText.AppendF("{}", i + 1);
			mDrawContext.DrawText(numText, FontSmall, .(x + slotSize - 12, startY + slotSize - 16), Color(80, 90, 100, 150));
		}

		// Controls hint - styled
		if (count > 0)
		{
			let hintY = startY + slotSize + 6;
			mDrawContext.DrawText("E Use   ,/. Cycle", FontSmall, .(startX + 8, hintY), Color(100, 110, 120, 180));
		}
	}

	private void DrawDashedHLine(float x, float y, float length, float thickness, float dashLen, float gapLen, float time, Color color)
	{
		let pattern = dashLen + gapLen;
		let offset = (time * 30.0f) % pattern; // Animate the dashes
		var pos = -offset;
		while (pos < length)
		{
			let segStart = Math.Max(0, pos);
			let segEnd = Math.Min(length, pos + dashLen);
			if (segEnd > segStart)
				mDrawContext.FillRect(.(x + segStart, y, segEnd - segStart, thickness), color);
			pos += pattern;
		}
	}

	private void DrawDashedVLine(float x, float y, float length, float thickness, float dashLen, float gapLen, float time, Color color)
	{
		let pattern = dashLen + gapLen;
		let offset = (time * 30.0f) % pattern; // Animate the dashes
		var pos = -offset;
		while (pos < length)
		{
			let segStart = Math.Max(0, pos);
			let segEnd = Math.Min(length, pos + dashLen);
			if (segEnd > segStart)
				mDrawContext.FillRect(.(x, y + segStart, thickness, segEnd - segStart), color);
			pos += pattern;
		}
	}

	private void DrawGameOver(int32 score, int32 highScore)
	{
		let screenW = (float)mScreenWidth;
		let screenH = (float)mScreenHeight;
		let centerX = screenW * 0.5f;
		let centerY = screenH * 0.5f;

		// Full-screen darkened overlay
		mDrawContext.FillRect(.(0, 0, screenW, screenH), Color(0, 0, 0, 160));

		// Main panel
		let panelW = 320.0f;
		let panelH = 200.0f;
		let panelX = centerX - panelW * 0.5f;
		let panelY = centerY - panelH * 0.5f;

		// Panel shadow
		mDrawContext.FillRect(.(panelX + 5, panelY + 5, panelW, panelH), Color(0, 0, 0, 100));
		// Panel background
		mDrawContext.FillRect(.(panelX, panelY, panelW, panelH), Color(15, 10, 10, 240));
		// Red accent border
		mDrawContext.FillRect(.(panelX, panelY, panelW, 3), Color(200, 50, 50, 200));
		mDrawContext.FillRect(.(panelX, panelY + panelH - 3, panelW, 3), Color(200, 50, 50, 200));
		mDrawContext.FillRect(.(panelX, panelY, 3, panelH), Color(200, 50, 50, 200));
		mDrawContext.FillRect(.(panelX + panelW - 3, panelY, 3, panelH), Color(200, 50, 50, 200));

		// Title with shadow
		let titleY = panelY + 25;
		mDrawContext.DrawText("GAME OVER", FontTitle, .(centerX - 78 + 2, titleY + 2), Color(0, 0, 0, 150));
		mDrawContext.DrawText("GAME OVER", FontTitle, .(centerX - 78, titleY), Color(220, 60, 60));

		// Decorative line
		mDrawContext.FillRect(.(panelX + 40, titleY + 45, panelW - 80, 1), Color(100, 60, 60, 150));

		// Score display
		let scoreY = panelY + 85;
		mDrawContext.DrawText("FINAL SCORE", FontSmall, .(centerX - 42, scoreY), Color(150, 140, 140));
		let scoreText = scope String();
		scoreText.AppendF("{}", score);
		mDrawContext.DrawText(scoreText, FontTitle, .(centerX - 35, scoreY + 18), Color(255, 255, 255));

		// New high score banner
		if (score >= highScore && score > 0)
		{
			let hsY = panelY + 135;
			mDrawContext.FillRect(.(panelX + 20, hsY - 2, panelW - 40, 22), Color(255, 200, 50, 30));
			mDrawContext.DrawText("NEW HIGH SCORE!", FontNormal, .(centerX - 68, hsY), Color(255, 220, 100));
		}

		// Restart prompt
		let promptY = panelY + panelH - 30;
		mDrawContext.DrawText("Press SPACE to restart", FontNormal, .(centerX - 88, promptY), Color(140, 140, 150));
	}

	private void DrawPaused()
	{
		let screenW = (float)mScreenWidth;
		let screenH = (float)mScreenHeight;
		let centerX = screenW * 0.5f;
		let centerY = screenH * 0.5f;

		// Full-screen darkened overlay
		mDrawContext.FillRect(.(0, 0, screenW, screenH), Color(0, 0, 0, 150));

		// Main panel
		let panelW = 240.0f;
		let panelH = 140.0f;
		let panelX = centerX - panelW * 0.5f;
		let panelY = centerY - panelH * 0.5f;

		// Panel shadow
		mDrawContext.FillRect(.(panelX + 4, panelY + 4, panelW, panelH), Color(0, 0, 0, 100));
		// Panel background
		mDrawContext.FillRect(.(panelX, panelY, panelW, panelH), Color(10, 15, 25, 240));
		// Blue accent border
		mDrawContext.FillRect(.(panelX, panelY, panelW, 3), Color(60, 120, 180, 200));
		mDrawContext.FillRect(.(panelX, panelY + panelH - 3, panelW, 3), Color(60, 120, 180, 200));
		mDrawContext.FillRect(.(panelX, panelY, 3, panelH), Color(60, 120, 180, 200));
		mDrawContext.FillRect(.(panelX + panelW - 3, panelY, 3, panelH), Color(60, 120, 180, 200));

		// Corner accents
		let cornerSize = 12.0f;
		let accentColor = Color(100, 160, 220, 220);
		// Top-left
		mDrawContext.FillRect(.(panelX - 1, panelY - 1, cornerSize, 2), accentColor);
		mDrawContext.FillRect(.(panelX - 1, panelY - 1, 2, cornerSize), accentColor);
		// Top-right
		mDrawContext.FillRect(.(panelX + panelW - cornerSize + 1, panelY - 1, cornerSize, 2), accentColor);
		mDrawContext.FillRect(.(panelX + panelW - 1, panelY - 1, 2, cornerSize), accentColor);
		// Bottom-left
		mDrawContext.FillRect(.(panelX - 1, panelY + panelH - 1, cornerSize, 2), accentColor);
		mDrawContext.FillRect(.(panelX - 1, panelY + panelH - cornerSize + 1, 2, cornerSize), accentColor);
		// Bottom-right
		mDrawContext.FillRect(.(panelX + panelW - cornerSize + 1, panelY + panelH - 1, cornerSize, 2), accentColor);
		mDrawContext.FillRect(.(panelX + panelW - 1, panelY + panelH - cornerSize + 1, 2, cornerSize), accentColor);

		// Title with shadow
		let titleY = panelY + 30;
		mDrawContext.DrawText("PAUSED", FontTitle, .(centerX - 52 + 2, titleY + 2), Color(0, 0, 0, 150));
		mDrawContext.DrawText("PAUSED", FontTitle, .(centerX - 52, titleY), Color(180, 200, 220));

		// Decorative line
		mDrawContext.FillRect(.(panelX + 30, titleY + 40, panelW - 60, 1), Color(60, 80, 100, 150));

		// Resume prompt
		let promptY = panelY + panelH - 40;
		mDrawContext.DrawText("Press ESC to resume", FontNormal, .(centerX - 78, promptY), Color(140, 150, 160));
	}

	/// Draw additional UI elements (combo, speed boost, FPS, etc.)
	public void DrawExtras(float comboDisplayTimer, int32 lastComboBonus, bool hasSpeedBoost, float fps, uint32 screenWidth, uint32 screenHeight, bool showGizmo)
	{
		// Combo display (center screen, fades out)
		if (comboDisplayTimer > 0 && lastComboBonus > 0)
		{
			let alpha = (uint8)Math.Min(255, (int32)(comboDisplayTimer * 200));
			let comboText = scope String();
			comboText.AppendF("COMBO +{}", lastComboBonus);
			let cx = (float)screenWidth * 0.5f - 60;
			mDrawContext.DrawText(comboText, FontTitle, .(cx, (float)screenHeight * 0.35f), Color(255, 200, 50, alpha));
		}

		// Speed boost indicator
		if (hasSpeedBoost)
		{
			let boostX = (float)screenWidth * 0.5f - 50;
			mDrawContext.DrawText("SPEED BOOST", FontNormal, .(boostX, (float)screenHeight - 65), Color(50, 220, 255));
		}

		// FPS counter bottom-left
		let fpsText = scope String();
		fpsText.AppendF("FPS: {:.0}", fps);
		mDrawContext.DrawText(fpsText, FontSmall, .(10, (float)screenHeight - 20), Color(150, 150, 150));

		// Light controls hint (only when gizmo visible)
		if (showGizmo)
			mDrawContext.DrawText("Arrows: rotate sun | U/I: intensity | L: print | G: hide", FontSmall, .(10, (float)screenHeight - 40), Color(100, 100, 100));
	}
}
