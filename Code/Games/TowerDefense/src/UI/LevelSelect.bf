namespace TowerDefense.UI;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;

/// Delegate for level selection events.
delegate void LevelSelectedDelegate(int32 levelIndex);

/// Level selection screen for Tower Defense.
class LevelSelect
{
	// Root UI element
	private Border mRoot ~ delete _;

	// Events
	private EventAccessor<LevelSelectedDelegate> mOnLevelSelected = new .() ~ delete _;
	private EventAccessor<MenuActionDelegate> mOnBack = new .() ~ delete _;

	public EventAccessor<LevelSelectedDelegate> OnLevelSelected => mOnLevelSelected;
	public EventAccessor<MenuActionDelegate> OnBack => mOnBack;

	/// Gets the root UI element.
	public UIElement RootElement => mRoot;

	/// Creates the level select screen.
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
		let titleText = new TextBlock();
		titleText.Text = "SELECT LEVEL";
		titleText.Foreground = Color(100, 200, 100);
		titleText.FontSize = 36;
		titleText.HorizontalAlignment = .Center;
		centerPanel.AddChild(titleText);

		// Spacer
		let spacer = new Border();
		spacer.Height = 30;
		spacer.Background = Color.Transparent;
		centerPanel.AddChild(spacer);

		// Level buttons panel
		let levelPanel = new StackPanel();
		levelPanel.Orientation = .Vertical;
		levelPanel.Spacing = 15;
		levelPanel.HorizontalAlignment = .Center;
		centerPanel.AddChild(levelPanel);

		// Level 1: Grasslands
		CreateLevelButton(levelPanel, 0, "Grasslands", "Easy - Learn the basics", Color(80, 150, 80));

		// Level 2: Desert Canyon
		CreateLevelButton(levelPanel, 1, "Desert Canyon", "Medium - Longer path, fewer lives", Color(180, 140, 80));

		// Level 3: Fortress
		CreateLevelButton(levelPanel, 2, "Fortress", "Hard - 8 waves, moat surrounds", Color(150, 80, 80));

		// Spacer before back button
		let spacer2 = new Border();
		spacer2.Height = 30;
		spacer2.Background = Color.Transparent;
		centerPanel.AddChild(spacer2);

		// Back button
		let backButton = new Button();
		backButton.Width = 150;
		backButton.Height = 40;
		backButton.Background = Color(100, 60, 60);
		backButton.ContentText = "BACK";
		backButton.Click.Subscribe(new (btn) => {
			mOnBack.[Friend]Invoke();
		});
		centerPanel.AddChild(backButton);
	}

	private void CreateLevelButton(StackPanel parent, int32 levelIndex, StringView name, StringView description, Color color, bool enabled = true)
	{
		let button = new Button();
		button.Width = 300;
		button.Height = 70;
		button.Background = color;
		button.IsEnabled = enabled;

		if (!enabled)
			button.Background = Color(60, 60, 60);

		let content = new StackPanel();
		content.Orientation = .Vertical;
		content.Spacing = 4;
		content.HorizontalAlignment = .Center;
		content.VerticalAlignment = .Center;

		let nameLabel = new TextBlock();
		nameLabel.Text = name;
		nameLabel.Foreground = enabled ? Color.White : Color(120, 120, 120);
		nameLabel.FontSize = 18;
		nameLabel.HorizontalAlignment = .Center;
		content.AddChild(nameLabel);

		let descLabel = new TextBlock();
		descLabel.Text = description;
		descLabel.Foreground = enabled ? Color(200, 200, 200) : Color(100, 100, 100);
		descLabel.FontSize = 12;
		descLabel.HorizontalAlignment = .Center;
		content.AddChild(descLabel);

		button.Content = content;

		if (enabled)
		{
			button.Click.Subscribe(new [=](btn) => {
				mOnLevelSelected.[Friend]Invoke(levelIndex);
			});
		}

		parent.AddChild(button);
	}
}
