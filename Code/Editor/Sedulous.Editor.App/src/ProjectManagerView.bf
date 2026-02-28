namespace Sedulous.Editor.App;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;
using Sedulous.Editor.Core;
using Sedulous.Core.Core;

/// Initial view for managing projects - shown before a project is opened.
public class ProjectManagerView : Border
{
	private RecentProjectsManager mRecentProjects;
	private StackPanel mProjectList;
	private Button mNewProjectBtn;
	private Button mOpenProjectBtn;

	// Events
	private EventAccessor<delegate void(RecentProject)> mProjectSelected = new .() ~ delete _;
	private EventAccessor<delegate void()> mNewProjectRequested = new .() ~ delete _;
	private EventAccessor<delegate void()> mOpenProjectRequested = new .() ~ delete _;

	/// Event fired when a recent project is selected.
	public EventAccessor<delegate void(RecentProject)> ProjectSelected => mProjectSelected;

	/// Event fired when new project is requested.
	public EventAccessor<delegate void()> NewProjectRequested => mNewProjectRequested;

	/// Event fired when open project dialog is requested.
	public EventAccessor<delegate void()> OpenProjectRequested => mOpenProjectRequested;

	public this(RecentProjectsManager recentProjects)
	{
		mRecentProjects = recentProjects;
		BuildUI();
	}

	private void BuildUI()
	{
		// Main container with dark background
		Background = Color(30, 30, 30);
		Padding = .(40);

		let mainPanel = new StackPanel();
		mainPanel.Orientation = .Vertical;
		mainPanel.HorizontalAlignment = .Center;
		mainPanel.VerticalAlignment = .Center;
		mainPanel.Spacing = 30;

		// Header
		let header = new StackPanel();
		header.Orientation = .Vertical;
		header.Spacing = 8;
		header.HorizontalAlignment = .Center;

		let title = new TextBlock();
		title.Text = "Sedulous Editor";
		title.Foreground = Color(240, 240, 240);
		title.HorizontalAlignment = .Center;
		header.AddChild(title);

		let subtitle = new TextBlock();
		subtitle.Text = "Create or open a project to get started";
		subtitle.Foreground = Color(150, 150, 150);
		subtitle.HorizontalAlignment = .Center;
		header.AddChild(subtitle);

		mainPanel.AddChild(header);

		// Action buttons
		let buttonRow = new StackPanel();
		buttonRow.Orientation = .Horizontal;
		buttonRow.Spacing = 15;
		buttonRow.HorizontalAlignment = .Center;

		mNewProjectBtn = new Button("New Project");
		mNewProjectBtn.Padding = .(20, 12, 20, 12);
		mNewProjectBtn.Click.Subscribe(new (sender) => {
			mNewProjectRequested.[Friend]Invoke();
		});
		buttonRow.AddChild(mNewProjectBtn);

		mOpenProjectBtn = new Button("Open Project");
		mOpenProjectBtn.Padding = .(20, 12, 20, 12);
		mOpenProjectBtn.Click.Subscribe(new (sender) => {
			mOpenProjectRequested.[Friend]Invoke();
		});
		buttonRow.AddChild(mOpenProjectBtn);

		mainPanel.AddChild(buttonRow);

		// Recent projects section
		if (mRecentProjects.Count > 0)
		{
			let recentSection = new StackPanel();
			recentSection.Orientation = .Vertical;
			recentSection.Spacing = 12;

			let recentLabel = new TextBlock();
			recentLabel.Text = "Recent Projects";
			recentLabel.Foreground = Color(180, 180, 180);
			recentSection.AddChild(recentLabel);

			// Project list container with border
			let listContainer = new Border();
			listContainer.Background = Color(40, 40, 45);
			listContainer.CornerRadius = 6;
			listContainer.Padding = .(8);
			listContainer.Width = .Fixed(500);

			mProjectList = new StackPanel();
			mProjectList.Orientation = .Vertical;
			mProjectList.Spacing = 4;

			RefreshProjectList();

			listContainer.Child = mProjectList;
			recentSection.AddChild(listContainer);

			mainPanel.AddChild(recentSection);
		}

		Child = mainPanel;
	}

	/// Refresh the project list from the manager.
	public void RefreshProjectList()
	{
		if (mProjectList == null)
			return;

		// Clear existing items
		mProjectList.ClearChildren();

		// Add project items
		for (let project in mRecentProjects.Projects)
		{
			let item = new ProjectListItem(project);
			item.Selected.Subscribe(new [&](proj) => {
				mProjectSelected.[Friend]Invoke(proj);
			});
			item.RemoveRequested.Subscribe(new [&](proj) => {
				mRecentProjects.RemoveProject(proj.Path);
				RefreshProjectList();
			});
			mProjectList.AddChild(item);
		}
	}
}

/// A single item in the recent projects list.
class ProjectListItem : Border
{
	private RecentProject mProject;

	private EventAccessor<delegate void(RecentProject)> mSelected = new .() ~ delete _;
	private EventAccessor<delegate void(RecentProject)> mRemoveRequested = new .() ~ delete _;

	public EventAccessor<delegate void(RecentProject)> Selected => mSelected;
	public EventAccessor<delegate void(RecentProject)> RemoveRequested => mRemoveRequested;

	public this(RecentProject project)
	{
		mProject = project;
		BuildUI();
	}

	private void BuildUI()
	{
		Background = Color(50, 50, 55);
		CornerRadius = 4;
		Padding = .(12, 8, 12, 8);
		Cursor = .Pointer;

		let content = new DockPanel();

		// Project info (left side)
		let info = new StackPanel();
		info.Orientation = .Vertical;
		info.Spacing = 2;

		let nameLabel = new TextBlock();
		nameLabel.Text = mProject.Name;
		nameLabel.Foreground = Color(230, 230, 230);
		info.AddChild(nameLabel);

		let pathLabel = new TextBlock();
		pathLabel.Text = mProject.Path;
		pathLabel.Foreground = Color(120, 120, 120);
		info.AddChild(pathLabel);

		content.AddChild(info);

		// Remove button (right side)
		let removeBtn = new Button("X");
		removeBtn.Padding = .(8, 4, 8, 4);
		removeBtn.Click.Subscribe(new (sender) => {
			mRemoveRequested.[Friend]Invoke(mProject);
		});
		DockPanelProperties.SetDock(removeBtn, .Right);
		content.AddChild(removeBtn);

		Child = content;
	}

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		base.OnMouseDown(e);

		// Left click selects the project (if not on remove button)
		if (e.Button == .Left && !e.Handled)
		{
			mSelected.[Friend]Invoke(mProject);
			e.Handled = true;
		}
	}

	protected override void OnMouseEnter(MouseEventArgs e)
	{
		base.OnMouseEnter(e);
		Background = Color(60, 60, 70);
	}

	protected override void OnMouseLeave(MouseEventArgs e)
	{
		base.OnMouseLeave(e);
		Background = Color(50, 50, 55);
	}
}
