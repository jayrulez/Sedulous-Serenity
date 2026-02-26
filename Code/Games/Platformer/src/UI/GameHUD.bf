namespace Platformer.UI;

using System;
using Sedulous.GUI;
using Sedulous.Foundation.Core;
using Sedulous.Foundation.Mathematics;

delegate void HUDActionDelegate();

/// In-game HUD with health, coins, keys, and overlays for pause/win/lose.
class GameHUD
{
	private Grid mRoot ~ delete _;

	// HUD elements
	private TextBlock mHealthText;
	private TextBlock mCoinText;
	private TextBlock mKeyText;
	private TextBlock mLevelNameText;
	private float mLevelNameTimer;

	// Overlays
	private Border mPauseOverlay;
	private Border mLevelCompleteOverlay;
	private Border mGameOverOverlay;
	private TextBlock mLevelCompleteStats;
	private TextBlock mGameOverWave;

	// Events
	private EventAccessor<HUDActionDelegate> mOnResume = new .() ~ delete _;
	private EventAccessor<HUDActionDelegate> mOnRestart = new .() ~ delete _;
	private EventAccessor<HUDActionDelegate> mOnMainMenu = new .() ~ delete _;
	private EventAccessor<HUDActionDelegate> mOnNextLevel = new .() ~ delete _;

	public EventAccessor<HUDActionDelegate> OnResume => mOnResume;
	public EventAccessor<HUDActionDelegate> OnRestart => mOnRestart;
	public EventAccessor<HUDActionDelegate> OnMainMenu => mOnMainMenu;
	public EventAccessor<HUDActionDelegate> OnNextLevel => mOnNextLevel;

	public UIElement RootElement => mRoot;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		// Grid root allows overlays on top
		mRoot = new Grid();
		mRoot.Background = Color.Transparent;
		mRoot.RowDefinitions.Add(new .() { Height = .Star });
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });

		// HUD layer
		let hud = new DockPanel();
		hud.Background = Color.Transparent;
		hud.LastChildFill = false;
		mRoot.AddChild(hud);

		// Top bar
		let topBar = new Border();
		topBar.Background = Color(0, 0, 0, 150);
		topBar.Height = .Fixed(44);
		topBar.Padding = Thickness(16, 6, 16, 6);
		DockPanelProperties.SetDock(topBar, .Top);

		let topContent = new StackPanel();
		topContent.Orientation = .Horizontal;
		topContent.Spacing = 40;
		topContent.VerticalAlignment = .Center;
		topBar.Child = topContent;

		// Health display
		mHealthText = new TextBlock();
		mHealthText.Text = "HP: 3";
		mHealthText.Foreground = Color(255, 80, 80, 255);
		mHealthText.FontSize = 20;
		topContent.AddChild(mHealthText);

		// Coin display
		mCoinText = new TextBlock();
		mCoinText.Text = "Coins: 0";
		mCoinText.Foreground = Color(255, 200, 50, 255);
		mCoinText.FontSize = 20;
		topContent.AddChild(mCoinText);

		// Key display
		mKeyText = new TextBlock();
		mKeyText.Text = "";
		mKeyText.Foreground = Color(200, 200, 255, 255);
		mKeyText.FontSize = 20;
		topContent.AddChild(mKeyText);

		hud.AddChild(topBar);

		// Level name (bottom center, fades)
		let bottomBar = new Border();
		bottomBar.Background = Color.Transparent;
		bottomBar.Height = .Fixed(40);
		DockPanelProperties.SetDock(bottomBar, .Bottom);

		mLevelNameText = new TextBlock();
		mLevelNameText.Text = "";
		mLevelNameText.Foreground = Color(255, 255, 255, 200);
		mLevelNameText.FontSize = 18;
		mLevelNameText.HorizontalAlignment = .Center;
		mLevelNameText.VerticalAlignment = .Center;
		bottomBar.Child = mLevelNameText;

		hud.AddChild(bottomBar);

		// Create overlays
		CreatePauseOverlay();
		CreateLevelCompleteOverlay();
		CreateGameOverOverlay();
	}

	private void CreatePauseOverlay()
	{
		mPauseOverlay = new Border();
		mPauseOverlay.Background = Color(0, 0, 0, 180);
		mPauseOverlay.HorizontalAlignment = .Stretch;
		mPauseOverlay.VerticalAlignment = .Stretch;
		mPauseOverlay.Visibility = .Collapsed;

		let panel = new StackPanel();
		panel.Orientation = .Vertical;
		panel.Spacing = 16;
		panel.HorizontalAlignment = .Center;
		panel.VerticalAlignment = .Center;
		mPauseOverlay.Child = panel;

		let title = new TextBlock();
		title.Text = "PAUSED";
		title.Foreground = Color(255, 255, 255, 255);
		title.FontSize = 36;
		title.HorizontalAlignment = .Center;
		panel.AddChild(title);

		AddOverlayButton(panel, "RESUME", new (btn) => { mOnResume.[Friend]Invoke(); });
		AddOverlayButton(panel, "RESTART", new (btn) => { mOnRestart.[Friend]Invoke(); });
		AddOverlayButton(panel, "MAIN MENU", new (btn) => { mOnMainMenu.[Friend]Invoke(); });

		mRoot.AddChild(mPauseOverlay);
	}

	private void CreateLevelCompleteOverlay()
	{
		mLevelCompleteOverlay = new Border();
		mLevelCompleteOverlay.Background = Color(0, 0, 0, 180);
		mLevelCompleteOverlay.HorizontalAlignment = .Stretch;
		mLevelCompleteOverlay.VerticalAlignment = .Stretch;
		mLevelCompleteOverlay.Visibility = .Collapsed;

		let panel = new StackPanel();
		panel.Orientation = .Vertical;
		panel.Spacing = 16;
		panel.HorizontalAlignment = .Center;
		panel.VerticalAlignment = .Center;
		mLevelCompleteOverlay.Child = panel;

		let title = new TextBlock();
		title.Text = "LEVEL COMPLETE!";
		title.Foreground = Color(255, 200, 50, 255);
		title.FontSize = 36;
		title.HorizontalAlignment = .Center;
		panel.AddChild(title);

		mLevelCompleteStats = new TextBlock();
		mLevelCompleteStats.Text = "";
		mLevelCompleteStats.Foreground = Color(200, 210, 230, 255);
		mLevelCompleteStats.FontSize = 18;
		mLevelCompleteStats.HorizontalAlignment = .Center;
		panel.AddChild(mLevelCompleteStats);

		AddOverlayButton(panel, "NEXT LEVEL", new (btn) => { mOnNextLevel.[Friend]Invoke(); });
		AddOverlayButton(panel, "MAIN MENU", new (btn) => { mOnMainMenu.[Friend]Invoke(); });

		mRoot.AddChild(mLevelCompleteOverlay);
	}

	private void CreateGameOverOverlay()
	{
		mGameOverOverlay = new Border();
		mGameOverOverlay.Background = Color(0, 0, 0, 200);
		mGameOverOverlay.HorizontalAlignment = .Stretch;
		mGameOverOverlay.VerticalAlignment = .Stretch;
		mGameOverOverlay.Visibility = .Collapsed;

		let panel = new StackPanel();
		panel.Orientation = .Vertical;
		panel.Spacing = 16;
		panel.HorizontalAlignment = .Center;
		panel.VerticalAlignment = .Center;
		mGameOverOverlay.Child = panel;

		let title = new TextBlock();
		title.Text = "GAME OVER";
		title.Foreground = Color(220, 60, 60, 255);
		title.FontSize = 36;
		title.HorizontalAlignment = .Center;
		panel.AddChild(title);

		mGameOverWave = new TextBlock();
		mGameOverWave.Text = "";
		mGameOverWave.Foreground = Color(180, 180, 200, 255);
		mGameOverWave.FontSize = 18;
		mGameOverWave.HorizontalAlignment = .Center;
		panel.AddChild(mGameOverWave);

		AddOverlayButton(panel, "RETRY", new (btn) => { mOnRestart.[Friend]Invoke(); });
		AddOverlayButton(panel, "MAIN MENU", new (btn) => { mOnMainMenu.[Friend]Invoke(); });

		mRoot.AddChild(mGameOverOverlay);
	}

	private void AddOverlayButton(StackPanel panel, StringView text, delegate void(Button) onClick)
	{
		let btn = new Button(scope String(text));
		btn.Width = .Fixed(200);
		btn.Height = .Fixed(44);
		if (let tb = btn.Content as TextBlock) tb.FontSize = 18;
		btn.Background = Color(60, 80, 120, 255);
		btn.Foreground = Color(255, 255, 255, 255);
		btn.BorderThickness = 1;
		btn.BorderColor = Color(100, 130, 180, 200);
		btn.CornerRadius = 8;
		btn.HorizontalAlignment = .Center;
		btn.Click.Subscribe(onClick);
		panel.AddChild(btn);
	}

	// === Update methods ===

	public void SetHealth(int32 health)
	{
		// Build heart display string
		let str = scope String();
		for (int32 i = 0; i < 3; i++)
		{
			if (i < health)
				str.Append("[ ] "); // filled heart placeholder
			else
				str.Append("[  ] "); // empty
		}
		mHealthText?.Set(scope $"HP: {health}");
	}

	public void SetCoins(int32 coins)
	{
		mCoinText?.Set(scope $"Coins: {coins}");
	}

	public void SetKeys(int32 keys)
	{
		if (keys > 0)
			mKeyText?.Set(scope $"Keys: {keys}");
		else
			mKeyText?.Set("");
	}

	public void ShowLevelName(StringView name)
	{
		mLevelNameText?.Set(scope String(name));
		mLevelNameTimer = 3.0f;
	}

	public void UpdateLevelNameFade(float dt)
	{
		if (mLevelNameTimer > 0)
		{
			mLevelNameTimer -= dt;
			if (mLevelNameTimer <= 0)
				mLevelNameText?.Set("");
		}
	}

	// === Overlay control ===

	public void HideOverlays()
	{
		mPauseOverlay.Visibility = .Collapsed;
		mLevelCompleteOverlay.Visibility = .Collapsed;
		mGameOverOverlay.Visibility = .Collapsed;
	}

	public void ShowPause()
	{
		HideOverlays();
		mPauseOverlay.Visibility = .Visible;
	}

	public void ShowLevelComplete(int32 coins)
	{
		HideOverlays();
		mLevelCompleteStats?.Set(scope $"Coins collected: {coins}");
		mLevelCompleteOverlay.Visibility = .Visible;
	}

	public void ShowGameOver()
	{
		HideOverlays();
		mGameOverWave?.Set("Better luck next time!");
		mGameOverOverlay.Visibility = .Visible;
	}
}
