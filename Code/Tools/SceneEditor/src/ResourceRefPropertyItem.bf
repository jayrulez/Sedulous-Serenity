namespace SceneEditor;

using System;
using System.IO;
using Sedulous.GUI;
using Sedulous.Foundation.Mathematics;

/// PropertyItem for ResourceRef fields with browse and clear buttons.
class ResourceRefPropertyItem : PropertyItem
{
	public delegate void(String outPath) PathGetter ~ delete _;
	public delegate void() OnBrowse ~ delete _;
	public delegate void() OnClear ~ delete _;

	private TextBlock mPathLabel;
	private bool mUpdating = false;

	public this(StringView name,
		delegate void(String outPath) pathGetter,
		delegate void() onBrowse,
		delegate void() onClear) : base(name, .String)
	{
		PathGetter = pathGetter;
		OnBrowse = onBrowse;
		OnClear = onClear;
	}

	public override UIElement CreateEditorControl()
	{
		let grid = new Grid();
		grid.ColumnDefinitions.Add(new .() { Width = .Star });     // path label
		grid.ColumnDefinitions.Add(new .() { Width = .Pixels(24) }); // browse button
		grid.ColumnDefinitions.Add(new .() { Width = .Pixels(20) }); // clear button
		grid.RowDefinitions.Add(new .() { Height = .Star });

		// Path label
		mPathLabel = new TextBlock("(none)");
		mPathLabel.FontSize = 11;
		mPathLabel.Foreground = Color(200, 200, 220, 255);
		mPathLabel.VerticalAlignment = .Center;
		mPathLabel.TextTrimming = .CharacterEllipsis;
		GridProperties.SetColumn(mPathLabel, 0);
		grid.AddChild(mPathLabel);

		// Browse button
		let browseBtn = new Button();
		browseBtn.Content = new TextBlock("...");
		browseBtn.Margin = .(1, 0, 1, 0);
		browseBtn.Click.Subscribe(new (btn) => OnBrowseClicked());
		GridProperties.SetColumn(browseBtn, 1);
		grid.AddChild(browseBtn);

		// Clear button
		let clearBtn = new Button();
		clearBtn.Content = new TextBlock("X");
		clearBtn.Margin = .(1, 0, 0, 0);
		clearBtn.Click.Subscribe(new (btn) => OnClearClicked());
		GridProperties.SetColumn(clearBtn, 2);
		grid.AddChild(clearBtn);

		// Initialize display
		UpdateLabel();

		return grid;
	}

	public override void RefreshEditorControl()
	{
		if (mUpdating) return;
		UpdateLabel();
	}

	private void UpdateLabel()
	{
		if (PathGetter == null || mPathLabel == null) return;

		let pathStr = scope String();
		PathGetter(pathStr);

		if (pathStr.IsEmpty || pathStr == "(none)")
		{
			mPathLabel.Text = "(none)";
			return;
		}

		// Show just the filename
		let filename = Path.GetFileName(pathStr, .. scope .());
		mPathLabel.Text = filename;
	}

	private void OnBrowseClicked()
	{
		if (OnBrowse == null) return;
		OnBrowse();

		// Refresh display after browse completes (dialog is async, refresh will happen via RefreshEditorControl)
	}

	private void OnClearClicked()
	{
		if (OnClear == null) return;
		OnClear();

		mUpdating = true;
		UpdateLabel();
		mUpdating = false;
		OwnerGrid?.NotifyPropertyChanged(this);
	}

	/// Called externally after the async browse dialog completes and the ref is set.
	public void NotifyRefChanged()
	{
		mUpdating = true;
		UpdateLabel();
		mUpdating = false;
		OwnerGrid?.NotifyPropertyChanged(this);
	}
}
