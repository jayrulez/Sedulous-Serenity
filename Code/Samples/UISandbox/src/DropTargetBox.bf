using Sedulous.UI;
using System;
using Sedulous.Mathematics;
namespace UISandbox;

/// Drop target that accepts dragged items.
class DropTargetBox : Border, IDropTarget
{
	private String mDroppedLabel ~ delete _;
	private Color mDroppedColor = Color(60, 60, 70);
	private bool mIsHighlighted = false;
	private TextBlock mLabel;

	public this()
	{
		Background = Color(60, 60, 70);
		BorderBrush = Color(100, 100, 110);
		BorderThickness = Thickness(2);
		CornerRadius = 4;
		mDroppedLabel = new String("Drop items here");

		mLabel = new TextBlock();
		mLabel.Text = mDroppedLabel;
		mLabel.Foreground = Color(150, 150, 150);
		mLabel.HorizontalAlignment = .Center;
		mLabel.VerticalAlignment = .Center;
		AddChild(mLabel);
	}

	public void OnDragEnter(DragEventArgs args)
	{
		// Check if we accept this data
		if (args.Data.HasData("color"))
		{
			args.Effect = .Copy;
			mIsHighlighted = true;
			BorderBrush = Color(100, 200, 100);
			InvalidateVisual();
		}
	}

	public void OnDragOver(DragEventArgs args)
	{
		if (args.Data.HasData("color"))
		{
			args.Effect = .Copy;
		}
	}

	public void OnDragLeave(DragEventArgs args)
	{
		mIsHighlighted = false;
		BorderBrush = Color(100, 100, 110);
		InvalidateVisual();
	}

	public void OnDrop(DragEventArgs args)
	{
		mIsHighlighted = false;
		BorderBrush = Color(100, 100, 110);

		if (args.Data.HasData("label"))
		{
			let label = args.Data.GetData("label") as String;
			if (label != null)
			{
				mDroppedLabel.Set(scope $"Dropped: {label}");
				mLabel.Text = mDroppedLabel;
			}
		}

		if (args.Data.HasData("color"))
		{
			let colorBox = args.Data.GetData("color") as ColorBox;
			if (colorBox != null)
			{
				Background = colorBox.Value;
			}
		}

		args.Effect = .Copy;
		args.Handled = true;
		InvalidateVisual();
	}
}