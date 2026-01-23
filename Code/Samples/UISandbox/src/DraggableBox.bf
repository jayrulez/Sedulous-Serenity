using Sedulous.UI;
using System;
using Sedulous.Mathematics;
namespace UISandbox;

/// Draggable box that can be dragged to drop targets.
class DraggableBox : Border, IDragSource
{
	private UIContext mUIContext;
	private String mLabel ~ delete _;
	private Color mColor;
	private bool mDragging = false;
	private ColorBox mColorBox ~ delete _; // Owned for DragData lifetime

	public this(UIContext context, StringView label, Color color)
	{
		mUIContext = context;
		mLabel = new String(label);
		mColor = color;
		mColorBox = new ColorBox(color);
		Background = color;
		CornerRadius = 4;

		// Add label
		let text = new TextBlock();
		text.Text = label;
		text.Foreground = Color.White;
		text.HorizontalAlignment = .Center;
		text.VerticalAlignment = .Center;
		AddChild(text);
	}

	public DragData OnDragStart(float x, float y)
	{
		let data = new DragData();
		data.SetData("color", mColorBox);
		data.SetData("label", mLabel);
		return data;
	}

	public DragDropEffects GetAllowedEffects()
	{
		return .Copy | .Move;
	}

	public void OnDragComplete(DragDropEffects effect)
	{
		mDragging = false;
		Console.WriteLine(scope $"Drag completed: {mLabel} with effect {effect}");
	}

	public void OnDragCancelled()
	{
		mDragging = false;
		Console.WriteLine(scope $"Drag cancelled: {mLabel}");
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		if (args.Button == .Left)
		{
			// Start drag operation
			mDragging = true;
			mUIContext.DragDrop.StartDrag(this, args.ScreenX, args.ScreenY);
			args.Handled = true;
		}
		base.OnMouseDownRouted(args);
	}
}