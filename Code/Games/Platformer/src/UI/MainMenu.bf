namespace Platformer.UI;

using System;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;
using Sedulous.Core.Core;

delegate void MenuActionDelegate();

/// Main menu screen with title and Play/Quit buttons.
class MainMenu
{
	private Border mRoot ~ delete _;

	// Events
	private EventAccessor<MenuActionDelegate> mOnPlay = new .() ~ delete _;
	private EventAccessor<MenuActionDelegate> mOnQuit = new .() ~ delete _;

	public EventAccessor<MenuActionDelegate> OnPlay => mOnPlay;
	public EventAccessor<MenuActionDelegate> OnQuit => mOnQuit;

	public UIElement RootElement => mRoot;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		// Full-screen background
		mRoot = new Border();
		mRoot.Background = Color(20, 30, 50, 255);
		mRoot.HorizontalAlignment = .Stretch;
		mRoot.VerticalAlignment = .Stretch;

		// Center content
		let centerPanel = new StackPanel();
		centerPanel.Orientation = .Vertical;
		centerPanel.Spacing = 24;
		centerPanel.HorizontalAlignment = .Center;
		centerPanel.VerticalAlignment = .Center;
		mRoot.Child = centerPanel;

		// Title
		let title = new TextBlock();
		title.Text = "PLATFORMER";
		title.Foreground = Color(255, 200, 50, 255);
		title.FontSize = 48;
		title.HorizontalAlignment = .Center;
		centerPanel.AddChild(title);

		// Subtitle
		let subtitle = new TextBlock();
		subtitle.Text = "A Sedulous Engine Game";
		subtitle.Foreground = Color(150, 170, 200, 255);
		subtitle.FontSize = 16;
		subtitle.HorizontalAlignment = .Center;
		centerPanel.AddChild(subtitle);

		// Spacer
		let spacer = new Border();
		spacer.Height = .Fixed(20);
		spacer.Background = Color.Transparent;
		centerPanel.AddChild(spacer);

		// Play button
		let playBtn = new Button("PLAY");
		playBtn.Width = .Fixed(200);
		playBtn.Height = .Fixed(50);
		if (let tb = playBtn.Content as TextBlock) tb.FontSize = 20;
		playBtn.Background = Color(50, 160, 60, 255);
		playBtn.Foreground = Color(255, 255, 255, 255);
		playBtn.BorderThickness = 2;
		playBtn.BorderColor = Color(80, 200, 90, 200);
		playBtn.CornerRadius = 10;
		playBtn.HorizontalAlignment = .Center;
		playBtn.Click.Subscribe(new (btn) => {
			mOnPlay.[Friend]Invoke();
		});
		centerPanel.AddChild(playBtn);

		// Quit button
		let quitBtn = new Button("QUIT");
		quitBtn.Width = .Fixed(200);
		quitBtn.Height = .Fixed(50);
		if (let tb = quitBtn.Content as TextBlock) tb.FontSize = 20;
		quitBtn.Background = Color(160, 50, 50, 255);
		quitBtn.Foreground = Color(255, 255, 255, 255);
		quitBtn.BorderThickness = 2;
		quitBtn.BorderColor = Color(200, 80, 80, 200);
		quitBtn.CornerRadius = 10;
		quitBtn.HorizontalAlignment = .Center;
		quitBtn.Click.Subscribe(new (btn) => {
			mOnQuit.[Friend]Invoke();
		});
		centerPanel.AddChild(quitBtn);

		// Controls hint
		let hint = new TextBlock();
		hint.Text = "WASD/Arrows + Space to Jump | Gamepad supported";
		hint.Foreground = Color(100, 120, 150, 255);
		hint.FontSize = 12;
		hint.HorizontalAlignment = .Center;
		centerPanel.AddChild(hint);
	}
}
