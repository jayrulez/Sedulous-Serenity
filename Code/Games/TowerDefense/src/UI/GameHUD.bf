namespace TowerDefense.UI;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;
using TowerDefense.Data;

/// Delegate for tower selection events.
delegate void TowerSelectedDelegate(int32 towerIndex);

/// Delegate for game action events.
delegate void GameActionDelegate();

/// Main game HUD for Tower Defense.
/// Displays money, lives, wave info, tower selection, and game state overlays.
class GameHUD
{
	// Root UI element
	private DockPanel mRoot ~ delete _;

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

	// Game state overlays
	private Border mGameOverOverlay;
	private Border mVictoryOverlay;
	private Border mPauseOverlay;
	private TextBlock mGameOverText;
	private TextBlock mVictoryText;

	// Events
	private EventAccessor<TowerSelectedDelegate> mOnTowerSelected = new .() ~ delete _;
	private EventAccessor<GameActionDelegate> mOnStartWave = new .() ~ delete _;
	private EventAccessor<GameActionDelegate> mOnRestart = new .() ~ delete _;
	private EventAccessor<GameActionDelegate> mOnResume = new .() ~ delete _;

	public EventAccessor<TowerSelectedDelegate> OnTowerSelected => mOnTowerSelected;
	public EventAccessor<GameActionDelegate> OnStartWave => mOnStartWave;
	public EventAccessor<GameActionDelegate> OnRestart => mOnRestart;
	public EventAccessor<GameActionDelegate> OnResume => mOnResume;

	/// Gets the root UI element.
	public UIElement RootElement => mRoot;

	/// Creates the game HUD.
	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		mRoot = new DockPanel();
		mRoot.Background = Color.Transparent;
		// LastChildFill = true (default) - last child fills remaining center

		// === Top Bar (Money, Lives, Wave) ===
		let topBar = new Border();
		topBar.Background = Color(20, 25, 30, 220);
		topBar.Height = 50;
		topBar.Padding = Thickness(20, 10, 20, 10);
		mRoot.SetDock(topBar, .Top);

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

		mRoot.AddChild(topBar);

		// === Bottom Tower Selection Panel ===
		let bottomPanel = new Border();
		bottomPanel.Background = Color(20, 25, 30, 220);
		bottomPanel.Height = 80;
		bottomPanel.Padding = Thickness(20, 10, 20, 10);
		mRoot.SetDock(bottomPanel, .Bottom);

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

		mRoot.AddChild(bottomPanel);

		// === Overlay Container (Grid allows overlays to stack) ===
		// This is the last child of DockPanel, so it fills the center area
		let overlayContainer = new Grid();
		overlayContainer.Background = Color.Transparent;

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

		overlayContainer.AddChild(mGameOverOverlay);

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

		overlayContainer.AddChild(mVictoryOverlay);

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

		overlayContainer.AddChild(mPauseOverlay);

		// Add overlay container as last child (fills center via LastChildFill)
		mRoot.AddChild(overlayContainer);
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
		Console.WriteLine("GameHUD.ShowPause() called");
		mPauseOverlay.Visibility = .Visible;

		// Force layout recalculation since element was measured while Collapsed
		mPauseOverlay.InvalidateMeasure();
		mRoot.InvalidateMeasure();

		Console.WriteLine($"Pause overlay visibility: {mPauseOverlay.Visibility}");
		Console.WriteLine($"Pause overlay Bounds: {mPauseOverlay.Bounds}");
		Console.WriteLine($"Pause overlay DesiredSize: {mPauseOverlay.DesiredSize}");
		Console.WriteLine($"Pause overlay HAlign: {mPauseOverlay.HorizontalAlignment}, VAlign: {mPauseOverlay.VerticalAlignment}");
		Console.WriteLine($"Pause overlay Parent: {mPauseOverlay.Parent}");
		if (mPauseOverlay.Parent != null)
		{
			Console.WriteLine($"Parent Bounds: {mPauseOverlay.Parent.Bounds}");
			Console.WriteLine($"Parent DesiredSize: {mPauseOverlay.Parent.DesiredSize}");
		}
		Console.WriteLine($"Root Bounds: {mRoot.Bounds}");
		Console.WriteLine($"Root DesiredSize: {mRoot.DesiredSize}");
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
}
