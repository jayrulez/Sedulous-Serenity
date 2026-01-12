namespace TowerDefense.UI;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;

/// Delegate for menu action events.
delegate void MenuActionDelegate();

/// Main menu screen for Tower Defense.
class MainMenu
{
	// Root UI element
	private Border mRoot ~ delete _;

	// Menu elements
	private TextBlock mTitleText;
	private TextBlock mSubtitleText;
	private Button mPlayButton;
	private Button mQuitButton;

	// Events
	private EventAccessor<MenuActionDelegate> mOnPlay = new .() ~ delete _;
	private EventAccessor<MenuActionDelegate> mOnQuit = new .() ~ delete _;

	public EventAccessor<MenuActionDelegate> OnPlay => mOnPlay;
	public EventAccessor<MenuActionDelegate> OnQuit => mOnQuit;

	/// Gets the root UI element.
	public UIElement RootElement => mRoot;

	/// Creates the main menu.
	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		// Full-screen dark background
		mRoot = new Border();
		mRoot.Background = Color(15, 20, 15, 255);
		mRoot.HorizontalAlignment = .Stretch;
		mRoot.VerticalAlignment = .Stretch;

		// Center content panel
		let centerPanel = new StackPanel();
		centerPanel.Orientation = .Vertical;
		centerPanel.Spacing = 20;
		centerPanel.HorizontalAlignment = .Center;
		centerPanel.VerticalAlignment = .Center;
		mRoot.Child = centerPanel;

		// Title
		mTitleText = new TextBlock();
		mTitleText.Text = "TOWER DEFENSE";
		mTitleText.Foreground = Color(100, 200, 100);
		mTitleText.FontSize = 48;
		mTitleText.HorizontalAlignment = .Center;
		centerPanel.AddChild(mTitleText);

		// Subtitle
		mSubtitleText = new TextBlock();
		mSubtitleText.Text = "Defend against the enemy waves!";
		mSubtitleText.Foreground = Color(180, 180, 180);
		mSubtitleText.FontSize = 16;
		mSubtitleText.HorizontalAlignment = .Center;
		centerPanel.AddChild(mSubtitleText);

		// Spacer
		let spacer = new Border();
		spacer.Height = 40;
		spacer.Background = Color.Transparent;
		centerPanel.AddChild(spacer);

		// Button panel
		let buttonPanel = new StackPanel();
		buttonPanel.Orientation = .Vertical;
		buttonPanel.Spacing = 15;
		buttonPanel.HorizontalAlignment = .Center;
		centerPanel.AddChild(buttonPanel);

		// Play button
		mPlayButton = new Button();
		mPlayButton.Width = 200;
		mPlayButton.Height = 50;
		mPlayButton.Background = Color(50, 150, 50);
		mPlayButton.ContentText = "PLAY";
		mPlayButton.Click.Subscribe(new (btn) => {
			mOnPlay.[Friend]Invoke();
		});
		buttonPanel.AddChild(mPlayButton);

		// Quit button
		mQuitButton = new Button();
		mQuitButton.Width = 200;
		mQuitButton.Height = 50;
		mQuitButton.Background = Color(150, 50, 50);
		mQuitButton.ContentText = "QUIT";
		mQuitButton.Click.Subscribe(new (btn) => {
			mOnQuit.[Friend]Invoke();
		});
		buttonPanel.AddChild(mQuitButton);

		// Instructions at bottom
		let instructionsPanel = new StackPanel();
		instructionsPanel.Orientation = .Vertical;
		instructionsPanel.Spacing = 5;
		instructionsPanel.HorizontalAlignment = .Center;
		instructionsPanel.Margin = Thickness(0, 60, 0, 0);
		centerPanel.AddChild(instructionsPanel);

		AddInstructionLine(instructionsPanel, "Controls:");
		AddInstructionLine(instructionsPanel, "WASD = Pan camera, Q/E = Zoom");
		AddInstructionLine(instructionsPanel, "F1-F5 or Click = Select tower");
		AddInstructionLine(instructionsPanel, "Left Click = Place tower");
		AddInstructionLine(instructionsPanel, "Space = Start wave");
	}

	private void AddInstructionLine(StackPanel panel, StringView text)
	{
		let line = new TextBlock();
		line.Text = text;
		line.Foreground = Color(120, 120, 120);
		line.FontSize = 12;
		line.HorizontalAlignment = .Center;
		panel.AddChild(line);
	}

	/// Shows the menu.
	public void Show()
	{
		mRoot.Visibility = .Visible;
	}

	/// Hides the menu.
	public void Hide()
	{
		mRoot.Visibility = .Collapsed;
	}
}
