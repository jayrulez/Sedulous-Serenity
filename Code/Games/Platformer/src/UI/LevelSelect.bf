namespace Platformer.UI;

using System;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;

delegate void LevelSelectedDelegate(int32 levelIndex);

/// Level selection screen with 5 level buttons.
class LevelSelect
{
	private Border mRoot ~ delete _;
	private Button[5] mLevelButtons;

	// Events
	private EventAccessor<LevelSelectedDelegate> mOnLevelSelected = new .() ~ delete _;
	private EventAccessor<MenuActionDelegate> mOnBack = new .() ~ delete _;

	public EventAccessor<LevelSelectedDelegate> OnLevelSelected => mOnLevelSelected;
	public EventAccessor<MenuActionDelegate> OnBack => mOnBack;

	public UIElement RootElement => mRoot;

	/// Number of levels unlocked (1-5).
	private int32 mUnlockedLevels = 1;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		mRoot = new Border();
		mRoot.Background = Color(20, 30, 50, 255);
		mRoot.HorizontalAlignment = .Stretch;
		mRoot.VerticalAlignment = .Stretch;

		let centerPanel = new StackPanel();
		centerPanel.Orientation = .Vertical;
		centerPanel.Spacing = 24;
		centerPanel.HorizontalAlignment = .Center;
		centerPanel.VerticalAlignment = .Center;
		mRoot.Child = centerPanel;

		// Title
		let title = new TextBlock();
		title.Text = "SELECT LEVEL";
		title.Foreground = Color(255, 200, 50, 255);
		title.FontSize = 32;
		title.HorizontalAlignment = .Center;
		centerPanel.AddChild(title);

		// Level buttons in a horizontal row
		let buttonRow = new StackPanel();
		buttonRow.Orientation = .Horizontal;
		buttonRow.Spacing = 16;
		buttonRow.HorizontalAlignment = .Center;
		centerPanel.AddChild(buttonRow);

		String[5] levelNames = .("1", "2", "3", "4", "5");
		for (int32 i = 0; i < 5; i++)
		{
			let btn = new Button(levelNames[i]);
			btn.Width = .Fixed(70);
			btn.Height = .Fixed(70);
			if (let tb = btn.Content as TextBlock) tb.FontSize = 24;
			btn.CornerRadius = 8;
			btn.BorderThickness = 2;

			let levelIdx = i;
			btn.Click.Subscribe(new [=](b) => {
				mOnLevelSelected.[Friend]Invoke(levelIdx);
			});

			mLevelButtons[i] = btn;
			buttonRow.AddChild(btn);
		}

		// Back button
		let backBtn = new Button("BACK");
		backBtn.Width = .Fixed(160);
		backBtn.Height = .Fixed(44);
		if (let tb = backBtn.Content as TextBlock) tb.FontSize = 18;
		backBtn.Background = Color(100, 100, 110, 255);
		backBtn.Foreground = Color(255, 255, 255, 255);
		backBtn.CornerRadius = 8;
		backBtn.HorizontalAlignment = .Center;
		backBtn.Click.Subscribe(new (btn) => {
			mOnBack.[Friend]Invoke();
		});
		centerPanel.AddChild(backBtn);

		UpdateLevelButtons();
	}

	/// Sets the number of unlocked levels and updates button states.
	public void SetUnlockedLevels(int32 count)
	{
		mUnlockedLevels = Math.Clamp(count, 1, 5);
		UpdateLevelButtons();
	}

	private void UpdateLevelButtons()
	{
		for (int32 i = 0; i < 5; i++)
		{
			let btn = mLevelButtons[i];
			if (btn == null) continue;

			bool unlocked = i < mUnlockedLevels;
			btn.IsEnabled = unlocked;

			if (unlocked)
			{
				btn.Background = Color(50, 140, 200, 255);
				btn.BorderColor = Color(80, 180, 240, 200);
				btn.Foreground = Color(255, 255, 255, 255);
			}
			else
			{
				btn.Background = Color(60, 60, 70, 255);
				btn.BorderColor = Color(80, 80, 90, 200);
				btn.Foreground = Color(120, 120, 130, 255);
			}
		}
	}
}
