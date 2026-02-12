namespace Platformer.UI;

using System;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;
using Platformer.Data;

delegate void CharacterSelectedDelegate(CharacterType character);

/// Character selection screen with 5 character panels.
class CharacterSelect
{
	private Border mRoot ~ delete _;
	private Button[5] mCharacterButtons;
	private Button mSelectBtn;
	private CharacterType mSelectedCharacter = .Oopi; // Default to teal

	// Events
	private EventAccessor<CharacterSelectedDelegate> mOnCharacterSelected = new .() ~ delete _;
	private EventAccessor<MenuActionDelegate> mOnBack = new .() ~ delete _;

	public EventAccessor<CharacterSelectedDelegate> OnCharacterSelected => mOnCharacterSelected;
	public EventAccessor<MenuActionDelegate> OnBack => mOnBack;

	public UIElement RootElement => mRoot;
	public CharacterType SelectedCharacter => mSelectedCharacter;

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
		title.Text = "CHOOSE YOUR CHARACTER";
		title.Foreground = Color(255, 200, 50, 255);
		title.FontSize = 32;
		title.HorizontalAlignment = .Center;
		centerPanel.AddChild(title);

		// Character panels in a horizontal row
		let panelRow = new StackPanel();
		panelRow.Orientation = .Horizontal;
		panelRow.Spacing = 12;
		panelRow.HorizontalAlignment = .Center;
		centerPanel.AddChild(panelRow);

		// Character color theme (border accent colors)
		Color[5] characterColors = .(
			Color(140, 80, 190, 255),  // Oobi - Purple
			Color(220, 100, 150, 255), // Oodi - Pink
			Color(230, 160, 60, 255),  // Ooli - Orange
			Color(60, 190, 190, 255),  // Oopi - Teal
			Color(160, 110, 60, 255)   // Oozi - Brown
		);

		for (int32 i = 0; i < 5; i++)
		{
			let def = CharacterDefinition.All[i];
			let charColor = characterColors[i];
			let charType = (CharacterType)i;

			// Button with custom StackPanel content
			let btn = new Button();
			btn.Width = .Fixed(130);
			btn.Height = .Fixed(160);
			btn.CornerRadius = 10;
			btn.BorderThickness = 3;

			// Build inner content
			let content = new StackPanel();
			content.Orientation = .Vertical;
			content.Spacing = 4;
			content.HorizontalAlignment = .Center;
			content.VerticalAlignment = .Center;
			btn.Content = content;

			// Character name
			let nameText = new TextBlock();
			nameText.Text = def.Name;
			nameText.FontSize = 20;
			nameText.Foreground = charColor;
			nameText.HorizontalAlignment = .Center;
			content.AddChild(nameText);

			// Skill name
			let skillText = new TextBlock();
			skillText.Text = def.SkillName;
			skillText.FontSize = 16;
			skillText.Foreground = Color(255, 220, 100, 255);
			skillText.HorizontalAlignment = .Center;
			content.AddChild(skillText);

			// Skill description
			let descText = new TextBlock();
			descText.Text = def.SkillDescription;
			descText.FontSize = 11;
			descText.Foreground = Color(180, 190, 210, 255);
			descText.HorizontalAlignment = .Center;
			content.AddChild(descText);

			btn.Click.Subscribe(new [=](b) => {
				SelectCharacter(charType);
			});

			mCharacterButtons[i] = btn;
			panelRow.AddChild(btn);
		}

		// Button row
		let buttonRow = new StackPanel();
		buttonRow.Orientation = .Horizontal;
		buttonRow.Spacing = 20;
		buttonRow.HorizontalAlignment = .Center;
		centerPanel.AddChild(buttonRow);

		// Back button
		let backBtn = new Button("BACK");
		backBtn.Width = .Fixed(140);
		backBtn.Height = .Fixed(44);
		if (let tb = backBtn.Content as TextBlock) tb.FontSize = 18;
		backBtn.Background = Color(100, 100, 110, 255);
		backBtn.Foreground = Color(255, 255, 255, 255);
		backBtn.CornerRadius = 8;
		backBtn.Click.Subscribe(new (btn) => {
			mOnBack.[Friend]Invoke();
		});
		buttonRow.AddChild(backBtn);

		// Select button
		mSelectBtn = new Button("SELECT");
		mSelectBtn.Width = .Fixed(140);
		mSelectBtn.Height = .Fixed(44);
		if (let tb = mSelectBtn.Content as TextBlock) tb.FontSize = 18;
		mSelectBtn.Background = Color(50, 160, 60, 255);
		mSelectBtn.Foreground = Color(255, 255, 255, 255);
		mSelectBtn.BorderThickness = 2;
		mSelectBtn.BorderColor = Color(80, 200, 90, 200);
		mSelectBtn.CornerRadius = 8;
		mSelectBtn.Click.Subscribe(new (btn) => {
			mOnCharacterSelected.[Friend]Invoke(mSelectedCharacter);
		});
		buttonRow.AddChild(mSelectBtn);

		UpdateSelection();
	}

	/// Selects a character by clicking on their panel.
	public void SelectCharacter(CharacterType type)
	{
		mSelectedCharacter = type;
		UpdateSelection();
	}

	/// Handles keyboard/gamepad input for character selection.
	public void HandleInput(bool left, bool right, bool confirm)
	{
		if (left)
		{
			int32 idx = (int32)mSelectedCharacter;
			idx = (idx - 1 + 5) % 5;
			mSelectedCharacter = (CharacterType)idx;
			UpdateSelection();
		}
		else if (right)
		{
			int32 idx = (int32)mSelectedCharacter;
			idx = (idx + 1) % 5;
			mSelectedCharacter = (CharacterType)idx;
			UpdateSelection();
		}

		if (confirm)
			mOnCharacterSelected.[Friend]Invoke(mSelectedCharacter);
	}

	private void UpdateSelection()
	{
		Color[5] characterColors = .(
			Color(140, 80, 190, 255),  // Oobi - Purple
			Color(220, 100, 150, 255), // Oodi - Pink
			Color(230, 160, 60, 255),  // Ooli - Orange
			Color(60, 190, 190, 255),  // Oopi - Teal
			Color(160, 110, 60, 255)   // Oozi - Brown
		);

		for (int32 i = 0; i < 5; i++)
		{
			let btn = mCharacterButtons[i];
			if (btn == null) continue;

			bool selected = i == (int32)mSelectedCharacter;
			let charColor = characterColors[i];

			if (selected)
			{
				btn.Background = Color(40, 50, 80, 255);
				btn.BorderColor = charColor;
			}
			else
			{
				btn.Background = Color(30, 35, 55, 255);
				btn.BorderColor = Color(60, 65, 85, 200);
			}
		}
	}
}
