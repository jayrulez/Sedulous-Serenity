namespace Sedulous.Editor.App;

using System;
using Sedulous.GUI;
using Sedulous.Foundation.Mathematics;
using Sedulous.Shell;
using Sedulous.Foundation.Core;

/// Dialog for creating a new project.
public class NewProjectDialog : Border
{
	private TextBox mProjectNameInput;
	private TextBox mFolderPathInput;
	private Button mBrowseBtn;
	private Button mCreateBtn;
	private Button mCancelBtn;
	private TextBlock mNameErrorLabel;
	private TextBlock mFolderErrorLabel;
	private IShell mShell;

	// Events
	private EventAccessor<delegate void(StringView name, StringView folder)> mProjectCreated = new .() ~ delete _;
	private EventAccessor<delegate void()> mCancelled = new .() ~ delete _;

	/// Event fired when user clicks Create with valid inputs.
	public EventAccessor<delegate void(StringView name, StringView folder)> ProjectCreated => mProjectCreated;

	/// Event fired when user cancels the dialog.
	public EventAccessor<delegate void()> Cancelled => mCancelled;

	public this(IShell shell)
	{
		mShell = shell;
		BuildUI();
	}

	private void BuildUI()
	{
		// Dialog container
		Background = Color(45, 45, 48);
		CornerRadius = 8;
		Padding = .(24);
		Width = .Fixed(450);
		HorizontalAlignment = .Center;
		VerticalAlignment = .Center;
		ClipToBounds = true;

		let mainPanel = new StackPanel();
		mainPanel.Orientation = .Vertical;
		mainPanel.Spacing = 16;
		mainPanel.Width = .Fill;

		// Title
		let title = new TextBlock();
		title.Text = "New Project";
		title.Foreground = Color(240, 240, 240);
		title.Margin = .(0, 0, 0, 8);
		mainPanel.AddChild(title);

		// Project name field
		let nameSection = new StackPanel();
		nameSection.Orientation = .Vertical;
		nameSection.Spacing = 4;
		nameSection.Width = .Fill;

		let nameLabel = new TextBlock();
		nameLabel.Text = "Project Name";
		nameLabel.Foreground = Color(180, 180, 180);
		nameSection.AddChild(nameLabel);

		mProjectNameInput = new TextBox();
		mProjectNameInput.Placeholder = "MyProject";
		mProjectNameInput.Width = .Fill;
		mProjectNameInput.Padding = .(8, 6, 8, 6);
		nameSection.AddChild(mProjectNameInput);

		mNameErrorLabel = new TextBlock();
		mNameErrorLabel.Text = "";
		mNameErrorLabel.Foreground = Color(255, 100, 100);
		mNameErrorLabel.Visibility = .Collapsed;
		nameSection.AddChild(mNameErrorLabel);

		mainPanel.AddChild(nameSection);

		// Folder path field
		let folderSection = new StackPanel();
		folderSection.Orientation = .Vertical;
		folderSection.Spacing = 4;
		folderSection.Width = .Fill;

		let folderLabel = new TextBlock();
		folderLabel.Text = "Location";
		folderLabel.Foreground = Color(180, 180, 180);
		folderSection.AddChild(folderLabel);

		let folderRow = new DockPanel();
		folderRow.Width = .Fill;

		mBrowseBtn = new Button("Browse...");
		mBrowseBtn.Padding = .(12, 6, 12, 6);
		mBrowseBtn.Click.Subscribe(new (sender) => OnBrowseClicked());
		DockPanelProperties.SetDock(mBrowseBtn, .Right);
		folderRow.AddChild(mBrowseBtn);

		mFolderPathInput = new TextBox();
		mFolderPathInput.Placeholder = "Select a folder...";
		mFolderPathInput.Width = .Fill;
		mFolderPathInput.Padding = .(8, 6, 8, 6);
		mFolderPathInput.Margin = .(0, 0, 8, 0);
		folderRow.AddChild(mFolderPathInput);

		folderSection.AddChild(folderRow);

		mFolderErrorLabel = new TextBlock();
		mFolderErrorLabel.Text = "";
		mFolderErrorLabel.Foreground = Color(255, 100, 100);
		mFolderErrorLabel.Visibility = .Collapsed;
		folderSection.AddChild(mFolderErrorLabel);

		mainPanel.AddChild(folderSection);

		// Buttons - use DockPanel for proper right alignment
		let buttonRow = new DockPanel();
		buttonRow.Width = .Fill;
		buttonRow.Margin = .(0, 12, 0, 0);

		// Right-aligned buttons container
		let buttonsContainer = new StackPanel();
		buttonsContainer.Orientation = .Horizontal;
		buttonsContainer.Spacing = 10;
		DockPanelProperties.SetDock(buttonsContainer, .Right);

		mCancelBtn = new Button("Cancel");
		mCancelBtn.Padding = .(16, 8, 16, 8);
		mCancelBtn.Click.Subscribe(new (sender) => OnCancelClicked());
		buttonsContainer.AddChild(mCancelBtn);

		mCreateBtn = new Button("Create");
		mCreateBtn.Padding = .(16, 8, 16, 8);
		mCreateBtn.Click.Subscribe(new (sender) => OnCreateClicked());
		buttonsContainer.AddChild(mCreateBtn);

		buttonRow.AddChild(buttonsContainer);
		mainPanel.AddChild(buttonRow);

		Child = mainPanel;
	}

	private void OnBrowseClicked()
	{
		let currentPath = scope String(mFolderPathInput.Text);

		mShell.Dialogs.ShowFolderDialog(new (paths) => {
			if (paths.Length > 0)
			{
				mFolderPathInput.Text = paths[0];
				// Clear folder error when a folder is selected
				ClearError(mFolderErrorLabel);
			}
		}, currentPath);
	}

	private void OnCreateClicked()
	{
		let name = scope String(mProjectNameInput.Text);
		name.Trim();

		let folder = scope String(mFolderPathInput.Text);
		folder.Trim();

		// Clear previous errors
		ClearError(mNameErrorLabel);
		ClearError(mFolderErrorLabel);

		// Validate
		var hasErrors = false;

		if (name.IsEmpty)
		{
			ShowError(mNameErrorLabel, "Project name is required");
			hasErrors = true;
		}

		if (folder.IsEmpty)
		{
			ShowError(mFolderErrorLabel, "Location is required");
			hasErrors = true;
		}

		if (hasErrors)
			return;

		mProjectCreated.[Friend]Invoke(name, folder);
	}

	private void OnCancelClicked()
	{
		mCancelled.[Friend]Invoke();
	}

	private void ShowError(TextBlock label, StringView message)
	{
		label.Text = message;
		label.Visibility = .Visible;
	}

	private void ClearError(TextBlock label)
	{
		label.Text = "";
		label.Visibility = .Collapsed;
	}

	/// Clears all input fields and errors.
	public void Reset()
	{
		mProjectNameInput.Text = "";
		mFolderPathInput.Text = "";
		ClearError(mNameErrorLabel);
		ClearError(mFolderErrorLabel);
	}

	/// Get the project name input for focus management.
	public TextBox NameInput => mProjectNameInput;
}
