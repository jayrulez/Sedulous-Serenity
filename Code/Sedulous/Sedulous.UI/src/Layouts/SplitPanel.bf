using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// A container that divides its space between two panels with a draggable splitter.
public class SplitPanel : Control
{
	private UIElement mPanel1;
	private UIElement mPanel2;
	private Splitter mSplitter; // Owned by parent as child - don't auto-delete
	private float mSplitterPosition = 200;
	private float mPanel1MinSize = 50;
	private float mPanel2MinSize = 50;

	/// The orientation of the split.
	/// Horizontal splits left/right, Vertical splits top/bottom.
	public Orientation Orientation
	{
		get => mSplitter.Orientation;
		set
		{
			if (mSplitter.Orientation != value)
			{
				mSplitter.Orientation = value;
				InvalidateMeasure();
			}
		}
	}

	/// The position of the splitter in pixels from the start edge.
	public float SplitterPosition
	{
		get => mSplitterPosition;
		set
		{
			let clamped = ClampSplitterPosition(value);
			if (mSplitterPosition != clamped)
			{
				mSplitterPosition = clamped;
				InvalidateArrange();
			}
		}
	}

	/// The thickness of the splitter bar.
	public float SplitterThickness
	{
		get => mSplitter.SplitterThickness;
		set => mSplitter.SplitterThickness = value;
	}

	/// Minimum size for the first panel.
	public float Panel1MinSize
	{
		get => mPanel1MinSize;
		set
		{
			mPanel1MinSize = Math.Max(0, value);
			SplitterPosition = mSplitterPosition; // Re-clamp
		}
	}

	/// Minimum size for the second panel.
	public float Panel2MinSize
	{
		get => mPanel2MinSize;
		set
		{
			mPanel2MinSize = Math.Max(0, value);
			SplitterPosition = mSplitterPosition; // Re-clamp
		}
	}

	/// The first panel (left or top depending on orientation).
	public UIElement Panel1
	{
		get => mPanel1;
		set
		{
			if (mPanel1 != value)
			{
				if (mPanel1 != null)
					RemoveChild(mPanel1);

				mPanel1 = value;

				if (mPanel1 != null)
					AddChild(mPanel1);

				InvalidateMeasure();
			}
		}
	}

	/// The second panel (right or bottom depending on orientation).
	public UIElement Panel2
	{
		get => mPanel2;
		set
		{
			if (mPanel2 != value)
			{
				if (mPanel2 != null)
					RemoveChild(mPanel2);

				mPanel2 = value;

				if (mPanel2 != null)
					AddChild(mPanel2);

				InvalidateMeasure();
			}
		}
	}

	public this()
	{
		mSplitter = new Splitter();
		mSplitter.Orientation = .Horizontal;
		mSplitter.SplitterMoved.Subscribe(new => OnSplitterMoved);
		AddChild(mSplitter);
	}

	private void OnSplitterMoved(Splitter splitter, float delta)
	{
		SplitterPosition = mSplitterPosition + delta;
	}

	private float ClampSplitterPosition(float position)
	{
		let totalSize = Orientation == .Horizontal ? Bounds.Width : Bounds.Height;
		let splitterSize = mSplitter.SplitterThickness;
		let maxPosition = totalSize - splitterSize - mPanel2MinSize;
		return Math.Clamp(position, mPanel1MinSize, Math.Max(mPanel1MinSize, maxPosition));
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		let splitterSize = mSplitter.SplitterThickness;

		// Measure splitter
		mSplitter.Measure(constraints);

		// Calculate sizes for panels
		if (Orientation == .Horizontal)
		{
			// Split horizontally (left | right)
			let panel1Width = mSplitterPosition;
			let panel2Width = constraints.MaxWidth != SizeConstraints.Infinity
				? Math.Max(0, constraints.MaxWidth - mSplitterPosition - splitterSize)
				: mPanel2MinSize;

			if (mPanel1 != null)
			{
				let panel1Constraints = SizeConstraints.FromMaximum(panel1Width, constraints.MaxHeight);
				mPanel1.Measure(panel1Constraints);
			}

			if (mPanel2 != null)
			{
				let panel2Constraints = SizeConstraints.FromMaximum(panel2Width, constraints.MaxHeight);
				mPanel2.Measure(panel2Constraints);
			}

			var width = mSplitterPosition + splitterSize + mPanel2MinSize;
			var height = 0f;

			if (mPanel1 != null)
				height = Math.Max(height, mPanel1.DesiredSize.Height);
			if (mPanel2 != null)
				height = Math.Max(height, mPanel2.DesiredSize.Height);

			return .(width, height);
		}
		else
		{
			// Split vertically (top | bottom)
			let panel1Height = mSplitterPosition;
			let panel2Height = constraints.MaxHeight != SizeConstraints.Infinity
				? Math.Max(0, constraints.MaxHeight - mSplitterPosition - splitterSize)
				: mPanel2MinSize;

			if (mPanel1 != null)
			{
				let panel1Constraints = SizeConstraints.FromMaximum(constraints.MaxWidth, panel1Height);
				mPanel1.Measure(panel1Constraints);
			}

			if (mPanel2 != null)
			{
				let panel2Constraints = SizeConstraints.FromMaximum(constraints.MaxWidth, panel2Height);
				mPanel2.Measure(panel2Constraints);
			}

			var width = 0f;
			var height = mSplitterPosition + splitterSize + mPanel2MinSize;

			if (mPanel1 != null)
				width = Math.Max(width, mPanel1.DesiredSize.Width);
			if (mPanel2 != null)
				width = Math.Max(width, mPanel2.DesiredSize.Width);

			return .(width, height);
		}
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		let splitterSize = mSplitter.SplitterThickness;

		// Re-clamp splitter position based on actual bounds
		let totalSize = Orientation == .Horizontal ? contentBounds.Width : contentBounds.Height;
		let maxPosition = totalSize - splitterSize - mPanel2MinSize;
		mSplitterPosition = Math.Clamp(mSplitterPosition, mPanel1MinSize, Math.Max(mPanel1MinSize, maxPosition));

		if (Orientation == .Horizontal)
		{
			// Panel 1 on left
			if (mPanel1 != null)
			{
				let panel1Bounds = RectangleF(contentBounds.X, contentBounds.Y, mSplitterPosition, contentBounds.Height);
				mPanel1.Arrange(panel1Bounds);
			}

			// Splitter in middle
			let splitterBounds = RectangleF(contentBounds.X + mSplitterPosition, contentBounds.Y, splitterSize, contentBounds.Height);
			mSplitter.Arrange(splitterBounds);

			// Panel 2 on right
			if (mPanel2 != null)
			{
				let panel2X = contentBounds.X + mSplitterPosition + splitterSize;
				let panel2Width = contentBounds.Right - panel2X;
				let panel2Bounds = RectangleF(panel2X, contentBounds.Y, panel2Width, contentBounds.Height);
				mPanel2.Arrange(panel2Bounds);
			}
		}
		else
		{
			// Panel 1 on top
			if (mPanel1 != null)
			{
				let panel1Bounds = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, mSplitterPosition);
				mPanel1.Arrange(panel1Bounds);
			}

			// Splitter in middle
			let splitterBounds = RectangleF(contentBounds.X, contentBounds.Y + mSplitterPosition, contentBounds.Width, splitterSize);
			mSplitter.Arrange(splitterBounds);

			// Panel 2 on bottom
			if (mPanel2 != null)
			{
				let panel2Y = contentBounds.Y + mSplitterPosition + splitterSize;
				let panel2Height = contentBounds.Bottom - panel2Y;
				let panel2Bounds = RectangleF(contentBounds.X, panel2Y, contentBounds.Width, panel2Height);
				mPanel2.Arrange(panel2Bounds);
			}
		}
	}
}
