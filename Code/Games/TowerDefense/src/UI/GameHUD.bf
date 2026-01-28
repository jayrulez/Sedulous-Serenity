namespace TowerDefense.UI;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;
using TowerDefense.Data;
using TowerDefense.Components;
using TowerDefense.Towers;

/// Delegate for tower selection events.
delegate void TowerSelectedDelegate(int32 towerIndex);

/// Delegate for game action events.
delegate void GameActionDelegate();

/// Delegate for volume change events.
delegate void VolumeChangeDelegate(float newVolume);

/// Delegate for game speed change events.
delegate void SpeedChangeDelegate(float speedMultiplier);

/// Main game HUD for Tower Defense.
/// Displays money, lives, wave info, tower selection, and game state overlays.
class GameHUD
{
	// Root UI element - Grid allows full-screen overlays on top of HUD
	private Grid mRoot ~ delete _;
	private DockPanel mHudPanel;

	// Top bar elements
	private TextBlock mMoneyLabel;
	private TextBlock mLivesLabel;
	private TextBlock mWaveLabel;

	// Tower selection panel
	private StackPanel mTowerPanel;
	private List<Button> mTowerButtons = new .() ~ delete _;
	private int32 mSelectedTowerIndex = -1;

	// Action buttons
	private Button mStartWaveButton;
	private Button mSpeed1xButton;
	private Button mSpeed2xButton;
	private Button mSpeed3xButton;
	private float mCurrentSpeed = 1.0f;

	// Game state overlays
	private Border mGameOverOverlay;
	private Border mVictoryOverlay;
	private Border mPauseOverlay;
	private TextBlock mGameOverText;
	private TextBlock mVictoryText;

	// Tower info panel (shown when a placed tower is selected)
	private Border mTowerInfoPanel;
	private TextBlock mTowerInfoName;
	private TextBlock mTowerInfoLevel;
	private TextBlock mTowerInfoDamage;
	private TextBlock mTowerInfoRange;
	private TextBlock mTowerInfoFireRate;
	private Button mUpgradeButton;
	private TextBlock mTowerInfoSellPrice;
	private Button mSellButton;

	// Volume controls (in pause menu)
	private TextBlock mMusicVolumeLabel;
	private TextBlock mSFXVolumeLabel;
	private float mMusicVolume = 0.1f;
	private float mSFXVolume = 0.1f;

	// Events
	private EventAccessor<TowerSelectedDelegate> mOnTowerSelected = new .() ~ delete _;
	private EventAccessor<GameActionDelegate> mOnStartWave = new .() ~ delete _;
	private EventAccessor<GameActionDelegate> mOnRestart = new .() ~ delete _;
	private EventAccessor<GameActionDelegate> mOnResume = new .() ~ delete _;
	private EventAccessor<GameActionDelegate> mOnMainMenu = new .() ~ delete _;
	private EventAccessor<GameActionDelegate> mOnSellTower = new .() ~ delete _;
	private EventAccessor<GameActionDelegate> mOnUpgradeTower = new .() ~ delete _;
	private EventAccessor<VolumeChangeDelegate> mOnMusicVolumeChanged = new .() ~ delete _;
	private EventAccessor<VolumeChangeDelegate> mOnSFXVolumeChanged = new .() ~ delete _;
	private EventAccessor<SpeedChangeDelegate> mOnSpeedChanged = new .() ~ delete _;

	public EventAccessor<TowerSelectedDelegate> OnTowerSelected => mOnTowerSelected;
	public EventAccessor<GameActionDelegate> OnStartWave => mOnStartWave;
	public EventAccessor<GameActionDelegate> OnRestart => mOnRestart;
	public EventAccessor<GameActionDelegate> OnResume => mOnResume;
	public EventAccessor<GameActionDelegate> OnMainMenu => mOnMainMenu;
	public EventAccessor<GameActionDelegate> OnSellTower => mOnSellTower;
	public EventAccessor<GameActionDelegate> OnUpgradeTower => mOnUpgradeTower;
	public EventAccessor<VolumeChangeDelegate> OnMusicVolumeChanged => mOnMusicVolumeChanged;
	public EventAccessor<VolumeChangeDelegate> OnSFXVolumeChanged => mOnSFXVolumeChanged;
	public EventAccessor<SpeedChangeDelegate> OnSpeedChanged => mOnSpeedChanged;

	/// Gets the root UI element.
	public UIElement RootElement => mRoot;

	/// Creates the game HUD.
	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		// Grid as root - allows full-screen overlays on top of HUD
		mRoot = new Grid();
		mRoot.Background = Color.Transparent;

		// DockPanel for HUD elements (stretches to fill Grid)
		mHudPanel = new DockPanel();
		mHudPanel.Background = Color.Transparent;
		mHudPanel.HorizontalAlignment = .Stretch;
		mHudPanel.VerticalAlignment = .Stretch;
		mHudPanel.LastChildFill = false;  // Don't fill center - just dock top/bottom
		mRoot.AddChild(mHudPanel);

		// === Top Bar (Money, Lives, Wave) ===
		let topBar = new Border();
		topBar.Background = Color(20, 25, 30, 220);
		topBar.Height = 50;
		topBar.Padding = Thickness(20, 10, 20, 10);
		mHudPanel.SetDock(topBar, .Top);

		let topBarContent = new StackPanel();
		topBarContent.Orientation = .Horizontal;
		topBarContent.Spacing = 40;
		topBarContent.VerticalAlignment = .Center;
		topBar.Child = topBarContent;

		// Money display
		{
			let moneyPanel = new StackPanel();
			moneyPanel.Orientation = .Horizontal;
			moneyPanel.Spacing = 8;

			let moneyIcon = new TextBlock();
			moneyIcon.Text = "$";
			moneyIcon.Foreground = Color(255, 215, 0);  // Gold
			moneyIcon.FontSize = 18;
			moneyPanel.AddChild(moneyIcon);

			mMoneyLabel = new TextBlock();
			mMoneyLabel.Text = "200";
			mMoneyLabel.Foreground = Color(255, 255, 255);
			mMoneyLabel.FontSize = 18;
			moneyPanel.AddChild(mMoneyLabel);

			topBarContent.AddChild(moneyPanel);
		}

		// Lives display
		{
			let livesPanel = new StackPanel();
			livesPanel.Orientation = .Horizontal;
			livesPanel.Spacing = 8;

			let livesIcon = new TextBlock();
			livesIcon.Text = "Lives:";
			livesIcon.Foreground = Color(255, 100, 100);  // Red
			livesIcon.FontSize = 18;
			livesPanel.AddChild(livesIcon);

			mLivesLabel = new TextBlock();
			mLivesLabel.Text = "20";
			mLivesLabel.Foreground = Color(255, 255, 255);
			mLivesLabel.FontSize = 18;
			livesPanel.AddChild(mLivesLabel);

			topBarContent.AddChild(livesPanel);
		}

		// Wave display
		{
			let wavePanel = new StackPanel();
			wavePanel.Orientation = .Horizontal;
			wavePanel.Spacing = 8;

			let waveIcon = new TextBlock();
			waveIcon.Text = "Wave:";
			waveIcon.Foreground = Color(100, 180, 255);  // Blue
			waveIcon.FontSize = 18;
			wavePanel.AddChild(waveIcon);

			mWaveLabel = new TextBlock();
			mWaveLabel.Text = "0/7";
			mWaveLabel.Foreground = Color(255, 255, 255);
			mWaveLabel.FontSize = 18;
			wavePanel.AddChild(mWaveLabel);

			topBarContent.AddChild(wavePanel);
		}

		// Start Wave button (right side of top bar)
		{
			mStartWaveButton = new Button();
			mStartWaveButton.ContentText = "Start Wave";
			mStartWaveButton.Padding = Thickness(15, 8, 15, 8);
			mStartWaveButton.Background = Color(50, 150, 50);
			mStartWaveButton.HorizontalAlignment = .Right;
			mStartWaveButton.Click.Subscribe(new (btn) => {
				mOnStartWave.[Friend]Invoke();
			});
			topBarContent.AddChild(mStartWaveButton);
		}

		// Speed control buttons
		{
			let speedPanel = new StackPanel();
			speedPanel.Orientation = .Horizontal;
			speedPanel.Spacing = 4;
			speedPanel.Margin = Thickness(20, 0, 0, 0);

			mSpeed1xButton = new Button();
			mSpeed1xButton.ContentText = "1x";
			mSpeed1xButton.Width = 40;
			mSpeed1xButton.Padding = Thickness(8, 6, 8, 6);
			mSpeed1xButton.Background = Color(80, 80, 80);
			mSpeed1xButton.BorderThickness = Thickness(2);  // Selected by default
			mSpeed1xButton.Click.Subscribe(new (btn) => { SetSpeed(1.0f); });
			speedPanel.AddChild(mSpeed1xButton);

			mSpeed2xButton = new Button();
			mSpeed2xButton.ContentText = "2x";
			mSpeed2xButton.Width = 40;
			mSpeed2xButton.Padding = Thickness(8, 6, 8, 6);
			mSpeed2xButton.Background = Color(80, 80, 80);
			mSpeed2xButton.Click.Subscribe(new (btn) => { SetSpeed(2.0f); });
			speedPanel.AddChild(mSpeed2xButton);

			mSpeed3xButton = new Button();
			mSpeed3xButton.ContentText = "3x";
			mSpeed3xButton.Width = 40;
			mSpeed3xButton.Padding = Thickness(8, 6, 8, 6);
			mSpeed3xButton.Background = Color(80, 80, 80);
			mSpeed3xButton.Click.Subscribe(new (btn) => { SetSpeed(3.0f); });
			speedPanel.AddChild(mSpeed3xButton);

			topBarContent.AddChild(speedPanel);
		}

		mHudPanel.AddChild(topBar);

		// === Bottom Tower Selection Panel ===
		let bottomPanel = new Border();
		bottomPanel.Background = Color(20, 25, 30, 220);
		bottomPanel.Height = 80;
		bottomPanel.Padding = Thickness(20, 10, 20, 10);
		mHudPanel.SetDock(bottomPanel, .Bottom);

		mTowerPanel = new StackPanel();
		mTowerPanel.Orientation = .Horizontal;
		mTowerPanel.Spacing = 10;
		mTowerPanel.HorizontalAlignment = .Center;
		mTowerPanel.VerticalAlignment = .Center;
		bottomPanel.Child = mTowerPanel;

		// Create tower buttons
		CreateTowerButton(0, "Cannon", "$100", Color(100, 100, 100));
		CreateTowerButton(1, "Archer", "$75", Color(139, 90, 43));
		CreateTowerButton(2, "Frost", "$150", Color(100, 200, 255));
		CreateTowerButton(3, "Mortar", "$200", Color(200, 80, 80));
		CreateTowerButton(4, "SAM", "$250", Color(80, 200, 80));

		mHudPanel.AddChild(bottomPanel);

		// === Overlays (added to root Grid for full-screen coverage) ===

		// === Game Over Overlay (hidden by default) ===
		mGameOverOverlay = new Border();
		mGameOverOverlay.Background = Color(0, 0, 0, 180);
		mGameOverOverlay.Visibility = .Collapsed;
		mGameOverOverlay.HorizontalAlignment = .Stretch;
		mGameOverOverlay.VerticalAlignment = .Stretch;

		let gameOverContent = new StackPanel();
		gameOverContent.Orientation = .Vertical;
		gameOverContent.Spacing = 20;
		gameOverContent.HorizontalAlignment = .Center;
		gameOverContent.VerticalAlignment = .Center;
		mGameOverOverlay.Child = gameOverContent;

		mGameOverText = new TextBlock();
		mGameOverText.Text = "GAME OVER";
		mGameOverText.Foreground = Color(255, 80, 80);
		mGameOverText.FontSize = 32;
		mGameOverText.HorizontalAlignment = .Center;
		gameOverContent.AddChild(mGameOverText);

		let gameOverRestartBtn = new Button();
		gameOverRestartBtn.ContentText = "Restart";
		gameOverRestartBtn.Padding = Thickness(30, 15, 30, 15);
		gameOverRestartBtn.HorizontalAlignment = .Center;
		gameOverRestartBtn.Click.Subscribe(new (btn) => {
			mOnRestart.[Friend]Invoke();
		});
		gameOverContent.AddChild(gameOverRestartBtn);

		let gameOverMenuBtn = new Button();
		gameOverMenuBtn.ContentText = "Main Menu";
		gameOverMenuBtn.Padding = Thickness(30, 15, 30, 15);
		gameOverMenuBtn.HorizontalAlignment = .Center;
		gameOverMenuBtn.Background = Color(80, 80, 100);
		gameOverMenuBtn.Click.Subscribe(new (btn) => {
			mOnMainMenu.[Friend]Invoke();
		});
		gameOverContent.AddChild(gameOverMenuBtn);

		mRoot.AddChild(mGameOverOverlay);

		// === Victory Overlay (hidden by default) ===
		mVictoryOverlay = new Border();
		mVictoryOverlay.Background = Color(0, 0, 0, 180);
		mVictoryOverlay.Visibility = .Collapsed;
		mVictoryOverlay.HorizontalAlignment = .Stretch;
		mVictoryOverlay.VerticalAlignment = .Stretch;

		let victoryContent = new StackPanel();
		victoryContent.Orientation = .Vertical;
		victoryContent.Spacing = 20;
		victoryContent.HorizontalAlignment = .Center;
		victoryContent.VerticalAlignment = .Center;
		mVictoryOverlay.Child = victoryContent;

		mVictoryText = new TextBlock();
		mVictoryText.Text = "VICTORY!";
		mVictoryText.Foreground = Color(80, 255, 80);
		mVictoryText.FontSize = 32;
		mVictoryText.HorizontalAlignment = .Center;
		victoryContent.AddChild(mVictoryText);

		let victoryRestartBtn = new Button();
		victoryRestartBtn.ContentText = "Play Again";
		victoryRestartBtn.Padding = Thickness(30, 15, 30, 15);
		victoryRestartBtn.HorizontalAlignment = .Center;
		victoryRestartBtn.Click.Subscribe(new (btn) => {
			mOnRestart.[Friend]Invoke();
		});
		victoryContent.AddChild(victoryRestartBtn);

		let victoryMenuBtn = new Button();
		victoryMenuBtn.ContentText = "Main Menu";
		victoryMenuBtn.Padding = Thickness(30, 15, 30, 15);
		victoryMenuBtn.HorizontalAlignment = .Center;
		victoryMenuBtn.Background = Color(80, 80, 100);
		victoryMenuBtn.Click.Subscribe(new (btn) => {
			mOnMainMenu.[Friend]Invoke();
		});
		victoryContent.AddChild(victoryMenuBtn);

		mRoot.AddChild(mVictoryOverlay);

		// === Pause Overlay (hidden by default) ===
		mPauseOverlay = new Border();
		mPauseOverlay.Background = Color(0, 0, 0, 180);
		mPauseOverlay.Visibility = .Collapsed;
		mPauseOverlay.HorizontalAlignment = .Stretch;
		mPauseOverlay.VerticalAlignment = .Stretch;

		let pauseContent = new StackPanel();
		pauseContent.Orientation = .Vertical;
		pauseContent.Spacing = 20;
		pauseContent.HorizontalAlignment = .Center;
		pauseContent.VerticalAlignment = .Center;
		mPauseOverlay.Child = pauseContent;

		let pauseText = new TextBlock();
		pauseText.Text = "PAUSED";
		pauseText.Foreground = Color(255, 255, 255);
		pauseText.FontSize = 32;
		pauseText.HorizontalAlignment = .Center;
		pauseContent.AddChild(pauseText);

		let pauseHint = new TextBlock();
		pauseHint.Text = "Press P or Escape to resume";
		pauseHint.Foreground = Color(180, 180, 180);
		pauseHint.FontSize = 16;
		pauseHint.HorizontalAlignment = .Center;
		pauseContent.AddChild(pauseHint);

		let resumeBtn = new Button();
		resumeBtn.ContentText = "Resume";
		resumeBtn.Padding = Thickness(30, 15, 30, 15);
		resumeBtn.HorizontalAlignment = .Center;
		resumeBtn.Click.Subscribe(new (btn) => {
			mOnResume.[Friend]Invoke();
		});
		pauseContent.AddChild(resumeBtn);

		// Volume controls section
		let volumeSection = new StackPanel();
		volumeSection.Orientation = .Vertical;
		volumeSection.Spacing = 10;
		volumeSection.HorizontalAlignment = .Center;
		volumeSection.Margin = Thickness(0, 20, 0, 0);
		pauseContent.AddChild(volumeSection);

		let volumeTitle = new TextBlock();
		volumeTitle.Text = "Volume";
		volumeTitle.Foreground = Color(200, 200, 200);
		volumeTitle.FontSize = 18;
		volumeTitle.HorizontalAlignment = .Center;
		volumeSection.AddChild(volumeTitle);

		// Music volume row
		let musicRow = new StackPanel();
		musicRow.Orientation = .Horizontal;
		musicRow.Spacing = 10;
		musicRow.HorizontalAlignment = .Center;
		volumeSection.AddChild(musicRow);

		let musicDownBtn = new Button();
		musicDownBtn.ContentText = "-";
		musicDownBtn.Width = 30;
		musicDownBtn.Height = 30;
		musicDownBtn.Click.Subscribe(new (btn) => {
			mMusicVolume = Math.Max(0.0f, mMusicVolume - 0.1f);
			UpdateVolumeLabels();
			mOnMusicVolumeChanged.[Friend]Invoke(mMusicVolume);
		});
		musicRow.AddChild(musicDownBtn);

		mMusicVolumeLabel = new TextBlock();
		mMusicVolumeLabel.Text = "Music: 50%";
		mMusicVolumeLabel.Foreground = Color.White;
		mMusicVolumeLabel.FontSize = 14;
		mMusicVolumeLabel.Width = 100;
		mMusicVolumeLabel.HorizontalAlignment = .Center;
		musicRow.AddChild(mMusicVolumeLabel);

		let musicUpBtn = new Button();
		musicUpBtn.ContentText = "+";
		musicUpBtn.Width = 30;
		musicUpBtn.Height = 30;
		musicUpBtn.Click.Subscribe(new (btn) => {
			mMusicVolume = Math.Min(1.0f, mMusicVolume + 0.1f);
			UpdateVolumeLabels();
			mOnMusicVolumeChanged.[Friend]Invoke(mMusicVolume);
		});
		musicRow.AddChild(musicUpBtn);

		// SFX volume row
		let sfxRow = new StackPanel();
		sfxRow.Orientation = .Horizontal;
		sfxRow.Spacing = 10;
		sfxRow.HorizontalAlignment = .Center;
		volumeSection.AddChild(sfxRow);

		let sfxDownBtn = new Button();
		sfxDownBtn.ContentText = "-";
		sfxDownBtn.Width = 30;
		sfxDownBtn.Height = 30;
		sfxDownBtn.Click.Subscribe(new (btn) => {
			mSFXVolume = Math.Max(0.0f, mSFXVolume - 0.1f);
			UpdateVolumeLabels();
			mOnSFXVolumeChanged.[Friend]Invoke(mSFXVolume);
		});
		sfxRow.AddChild(sfxDownBtn);

		mSFXVolumeLabel = new TextBlock();
		mSFXVolumeLabel.Text = "SFX: 70%";
		mSFXVolumeLabel.Foreground = Color.White;
		mSFXVolumeLabel.FontSize = 14;
		mSFXVolumeLabel.Width = 100;
		mSFXVolumeLabel.HorizontalAlignment = .Center;
		sfxRow.AddChild(mSFXVolumeLabel);

		let sfxUpBtn = new Button();
		sfxUpBtn.ContentText = "+";
		sfxUpBtn.Width = 30;
		sfxUpBtn.Height = 30;
		sfxUpBtn.Click.Subscribe(new (btn) => {
			mSFXVolume = Math.Min(1.0f, mSFXVolume + 0.1f);
			UpdateVolumeLabels();
			mOnSFXVolumeChanged.[Friend]Invoke(mSFXVolume);
		});
		sfxRow.AddChild(sfxUpBtn);

		// Main Menu button at bottom of pause screen
		let pauseMenuBtn = new Button();
		pauseMenuBtn.ContentText = "Main Menu";
		pauseMenuBtn.Padding = Thickness(30, 15, 30, 15);
		pauseMenuBtn.HorizontalAlignment = .Center;
		pauseMenuBtn.Margin = Thickness(0, 20, 0, 0);
		pauseMenuBtn.Background = Color(100, 60, 60);
		pauseMenuBtn.Click.Subscribe(new (btn) => {
			mOnMainMenu.[Friend]Invoke();
		});
		pauseContent.AddChild(pauseMenuBtn);

		mRoot.AddChild(mPauseOverlay);

		// === Tower Info Panel (hidden by default, shown on right side) ===
		mTowerInfoPanel = new Border();
		mTowerInfoPanel.Background = Color(20, 25, 30, 230);
		mTowerInfoPanel.Visibility = .Collapsed;
		mTowerInfoPanel.Width = 180;
		mTowerInfoPanel.HorizontalAlignment = .Right;
		mTowerInfoPanel.VerticalAlignment = .Center;
		mTowerInfoPanel.Padding = Thickness(15, 15, 15, 15);
		mTowerInfoPanel.Margin = Thickness(0, 0, 20, 0);

		let infoContent = new StackPanel();
		infoContent.Orientation = .Vertical;
		infoContent.Spacing = 8;
		mTowerInfoPanel.Child = infoContent;

		// Tower name
		mTowerInfoName = new TextBlock();
		mTowerInfoName.Text = "Tower Name";
		mTowerInfoName.Foreground = Color.White;
		mTowerInfoName.FontSize = 18;
		mTowerInfoName.HorizontalAlignment = .Center;
		infoContent.AddChild(mTowerInfoName);

		// Tower level
		mTowerInfoLevel = new TextBlock();
		mTowerInfoLevel.Text = "Level 1";
		mTowerInfoLevel.Foreground = Color(180, 180, 180);
		mTowerInfoLevel.FontSize = 14;
		mTowerInfoLevel.HorizontalAlignment = .Center;
		infoContent.AddChild(mTowerInfoLevel);

		// Separator
		let separator = new Border();
		separator.Background = Color(100, 100, 100);
		separator.Height = 1;
		separator.Margin = Thickness(0, 5, 0, 5);
		infoContent.AddChild(separator);

		// Damage
		mTowerInfoDamage = new TextBlock();
		mTowerInfoDamage.Text = "Damage: 0";
		mTowerInfoDamage.Foreground = Color(255, 200, 100);
		mTowerInfoDamage.FontSize = 14;
		infoContent.AddChild(mTowerInfoDamage);

		// Range
		mTowerInfoRange = new TextBlock();
		mTowerInfoRange.Text = "Range: 0";
		mTowerInfoRange.Foreground = Color(100, 200, 255);
		mTowerInfoRange.FontSize = 14;
		infoContent.AddChild(mTowerInfoRange);

		// Fire rate
		mTowerInfoFireRate = new TextBlock();
		mTowerInfoFireRate.Text = "Fire Rate: 0/s";
		mTowerInfoFireRate.Foreground = Color(200, 100, 255);
		mTowerInfoFireRate.FontSize = 14;
		infoContent.AddChild(mTowerInfoFireRate);

		// Separator before upgrade/sell
		let separator2 = new Border();
		separator2.Background = Color(100, 100, 100);
		separator2.Height = 1;
		separator2.Margin = Thickness(0, 5, 0, 5);
		infoContent.AddChild(separator2);

		// Upgrade button
		mUpgradeButton = new Button();
		mUpgradeButton.ContentText = "Upgrade $0";
		mUpgradeButton.Padding = Thickness(20, 10, 20, 10);
		mUpgradeButton.Background = Color(50, 150, 50);
		mUpgradeButton.HorizontalAlignment = .Center;
		mUpgradeButton.Click.Subscribe(new (btn) => {
			mOnUpgradeTower.[Friend]Invoke();
		});
		infoContent.AddChild(mUpgradeButton);

		// Sell price
		mTowerInfoSellPrice = new TextBlock();
		mTowerInfoSellPrice.Text = "Sell: $0";
		mTowerInfoSellPrice.Foreground = Color(255, 215, 0);
		mTowerInfoSellPrice.FontSize = 14;
		mTowerInfoSellPrice.HorizontalAlignment = .Center;
		infoContent.AddChild(mTowerInfoSellPrice);

		// Sell button
		mSellButton = new Button();
		mSellButton.ContentText = "Sell Tower";
		mSellButton.Padding = Thickness(20, 10, 20, 10);
		mSellButton.Background = Color(180, 50, 50);
		mSellButton.HorizontalAlignment = .Center;
		mSellButton.Click.Subscribe(new (btn) => {
			mOnSellTower.[Friend]Invoke();
		});
		infoContent.AddChild(mSellButton);

		mRoot.AddChild(mTowerInfoPanel);
	}

	private void CreateTowerButton(int32 index, StringView name, StringView cost, Color color)
	{
		let btn = new Button();
		btn.Width = 100;
		btn.Height = 60;
		btn.Background = color;

		let content = new StackPanel();
		content.Orientation = .Vertical;
		content.Spacing = 2;
		content.HorizontalAlignment = .Center;
		content.VerticalAlignment = .Center;

		let nameLabel = new TextBlock();
		nameLabel.Text = name;
		nameLabel.Foreground = Color.White;
		nameLabel.HorizontalAlignment = .Center;
		content.AddChild(nameLabel);

		let costLabel = new TextBlock();
		costLabel.Text = cost;
		costLabel.Foreground = Color(255, 215, 0);
		costLabel.HorizontalAlignment = .Center;
		content.AddChild(costLabel);

		btn.Content = content;

		btn.Click.Subscribe(new [=](sender) => {
			Console.WriteLine($"Tower button {index} CLICKED!");
			SelectTower(index);
		});

		mTowerButtons.Add(btn);
		mTowerPanel.AddChild(btn);
		Console.WriteLine($"Created tower button {index}: {name}");
	}

	private void SelectTower(int32 index)
	{
		Console.WriteLine($"GameHUD.SelectTower({index}) called");

		// Update visual selection
		for (int i = 0; i < mTowerButtons.Count; i++)
		{
			let btn = mTowerButtons[i];
			if (i == index)
				btn.BorderThickness = Thickness(3);
			else
				btn.BorderThickness = Thickness(0);
		}

		mSelectedTowerIndex = index;
		mOnTowerSelected.[Friend]Invoke(index);
	}

	/// Updates the money display.
	public void SetMoney(int32 money)
	{
		mMoneyLabel.Text = scope:: $"{money}";
	}

	/// Updates the lives display.
	public void SetLives(int32 lives)
	{
		mLivesLabel.Text = scope:: $"{lives}";

		// Change color based on lives
		if (lives <= 5)
			mLivesLabel.Foreground = Color(255, 80, 80);
		else if (lives <= 10)
			mLivesLabel.Foreground = Color(255, 200, 80);
		else
			mLivesLabel.Foreground = Color(255, 255, 255);
	}

	/// Updates the wave display.
	public void SetWave(int32 current, int32 total)
	{
		mWaveLabel.Text = scope:: $"{current}/{total}";
	}

	/// Sets whether the Start Wave button is enabled.
	public void SetStartWaveEnabled(bool enabled)
	{
		mStartWaveButton.IsEnabled = enabled;
		if (enabled)
			mStartWaveButton.Background = Color(50, 150, 50);
		else
			mStartWaveButton.Background = Color(80, 80, 80);
	}

	/// Sets the Start Wave button text.
	public void SetStartWaveText(StringView text)
	{
		mStartWaveButton.ContentText = text;
	}

	/// Shows the game over overlay.
	public void ShowGameOver(int32 wavesCompleted, int32 kills)
	{
		mGameOverText.Text = scope:: $"GAME OVER\nWaves: {wavesCompleted}  Kills: {kills}";
		mGameOverOverlay.Visibility = .Visible;
	}

	/// Shows the victory overlay.
	public void ShowVictory(int32 money, int32 kills)
	{
		mVictoryText.Text = scope:: $"VICTORY!\nMoney: ${money}  Kills: {kills}";
		mVictoryOverlay.Visibility = .Visible;
	}

	/// Shows the pause overlay.
	public void ShowPause()
	{
		mPauseOverlay.Visibility = .Visible;
	}

	/// Hides the pause overlay.
	public void HidePause()
	{
		mPauseOverlay.Visibility = .Collapsed;
	}

	/// Hides all overlays.
	public void HideOverlays()
	{
		mGameOverOverlay.Visibility = .Collapsed;
		mVictoryOverlay.Visibility = .Collapsed;
		mPauseOverlay.Visibility = .Collapsed;
	}

	/// Clears tower selection.
	public void ClearSelection()
	{
		mSelectedTowerIndex = -1;
		for (let btn in mTowerButtons)
			btn.BorderThickness = Thickness(0);
	}

	/// Shows the tower info panel with the given tower's stats.
	public void ShowTowerInfo(TowerData tower)
	{
		if (tower == null)
			return;

		let def = tower.Definition;
		mTowerInfoName.Text = scope:: $"{def.Name}";
		mTowerInfoLevel.Text = scope:: $"Level {tower.Level}";
		mTowerInfoDamage.Text = scope:: $"Damage: {tower.GetDamage():F0}";
		mTowerInfoRange.Text = scope:: $"Range: {tower.GetRange():F1}";
		mTowerInfoFireRate.Text = scope:: $"Fire Rate: {tower.GetFireRate():F1}/s";

		// Upgrade button
		if (tower.CanUpgrade)
		{
			mUpgradeButton.ContentText = scope:: $"Upgrade ${tower.GetUpgradeCost()}";
			mUpgradeButton.IsEnabled = true;
			mUpgradeButton.Background = Color(50, 150, 50);
			mUpgradeButton.Visibility = .Visible;
		}
		else
		{
			mUpgradeButton.ContentText = "MAX LEVEL";
			mUpgradeButton.IsEnabled = false;
			mUpgradeButton.Background = Color(80, 80, 80);
			mUpgradeButton.Visibility = .Visible;
		}

		// Sell price is 50% of total invested
		let sellPrice = tower.GetTotalInvested() / 2;
		mTowerInfoSellPrice.Text = scope:: $"Sell: ${sellPrice}";

		mTowerInfoPanel.Visibility = .Visible;
	}

	/// Hides the tower info panel.
	public void HideTowerInfo()
	{
		mTowerInfoPanel.Visibility = .Collapsed;
	}

	/// Updates volume display labels.
	private void UpdateVolumeLabels()
	{
		int32 musicPct = (int32)(mMusicVolume * 100 + 0.5f);
		int32 sfxPct = (int32)(mSFXVolume * 100 + 0.5f);
		mMusicVolumeLabel.Text = scope:: $"Music: {musicPct}%";
		mSFXVolumeLabel.Text = scope:: $"SFX: {sfxPct}%";
	}

	/// Sets current volume values (for syncing with GameAudio).
	public void SetVolumes(float musicVolume, float sfxVolume)
	{
		mMusicVolume = musicVolume;
		mSFXVolume = sfxVolume;
		UpdateVolumeLabels();
	}

	/// Sets the game speed and updates button visuals.
	private void SetSpeed(float speed)
	{
		mCurrentSpeed = speed;

		// Update button visuals (border indicates selection)
		mSpeed1xButton.BorderThickness = (speed == 1.0f) ? Thickness(2) : Thickness(0);
		mSpeed2xButton.BorderThickness = (speed == 2.0f) ? Thickness(2) : Thickness(0);
		mSpeed3xButton.BorderThickness = (speed == 3.0f) ? Thickness(2) : Thickness(0);

		mOnSpeedChanged.[Friend]Invoke(speed);
	}

	/// Resets speed to 1x (used when restarting game).
	public void ResetSpeed()
	{
		SetSpeed(1.0f);
	}
}
