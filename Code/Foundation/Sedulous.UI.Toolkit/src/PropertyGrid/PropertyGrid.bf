namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// A property editor grid that organizes PropertyEditor instances into
/// categorized, scrollable rows with label + editor columns.
public class PropertyGrid : ViewGroup
{
	private List<PropertyEditor> mEditors = new .() ~ { for (var e in _) delete e; delete _; };
	private ScrollView mScrollView;
	private LinearLayout mContent;
	private float mLabelWidthRatio = 0.4f;
	private float mRowHeight = 26;
	private bool mNeedsRebuild;

	/// Ratio of the label column width relative to total width (0.0-1.0).
	public float LabelWidthRatio
	{
		get => mLabelWidthRatio;
		set { mLabelWidthRatio = Math.Clamp(value, 0.1f, 0.9f); mNeedsRebuild = true; }
	}

	public float RowHeight
	{
		get => mRowHeight;
		set { mRowHeight = Math.Max(16, value); mNeedsRebuild = true; }
	}

	public this()
	{
		ClipToBounds = true;

		mScrollView = new ScrollView();
		mScrollView.AllowVerticalScroll = true;
		mScrollView.AllowHorizontalScroll = false;
		AddView(mScrollView);

		mContent = new LinearLayout();
		mContent.Orientation = .Vertical;
		mContent.Spacing = 0;
		mScrollView.SetContent(mContent);
	}

	/// Add a property editor to the grid.
	public void AddProperty(PropertyEditor editor)
	{
		mEditors.Add(editor);
		mNeedsRebuild = true;
		InvalidateLayout();
	}

	/// Remove a property editor by name.
	public void RemoveProperty(StringView name)
	{
		for (int i = 0; i < mEditors.Count; i++)
		{
			if (mEditors[i].PropertyName == name)
			{
				delete mEditors[i];
				mEditors.RemoveAt(i);
				mNeedsRebuild = true;
				InvalidateLayout();
				return;
			}
		}
	}

	/// Get a property editor by name.
	public PropertyEditor GetProperty(StringView name)
	{
		for (let editor in mEditors)
		{
			if (editor.PropertyName == name)
				return editor;
		}
		return null;
	}

	/// Clear all property editors.
	public void Clear()
	{
		for (var e in mEditors)
			delete e;
		mEditors.Clear();
		mNeedsRebuild = true;
		InvalidateLayout();
	}

	/// Rebuild the view tree from the current editors.
	public void RebuildLayout()
	{
		// Detach editor views from their row parents before clearing,
		// so RemoveAllViews won't delete them (PropertyEditor owns them via mView).
		for (let editor in mEditors)
		{
			let view = editor.EditorView;
			if (view != null && view.Parent != null)
			{
				if (let parentGroup = view.Parent as ViewGroup)
					parentGroup.DetachView(view);
			}
		}

		mContent.RemoveAllViews();

		// Group editors by category
		let categories = scope Dictionary<StringView, List<PropertyEditor>>();
		let categoryOrder = scope List<StringView>();
		let uncategorized = scope List<PropertyEditor>();

		for (let editor in mEditors)
		{
			if (editor.Category.Length > 0)
			{
				if (!categories.ContainsKey(editor.Category))
				{
					categories[editor.Category] = scope:: List<PropertyEditor>();
					categoryOrder.Add(editor.Category);
				}
				categories[editor.Category].Add(editor);
			}
			else
			{
				uncategorized.Add(editor);
			}
		}

		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Add uncategorized editors first
		for (let editor in uncategorized)
			AddEditorRow(editor, palette);

		// Add categorized editors in Expanders
		for (let cat in categoryOrder)
		{
			let expander = new Expander(cat);
			expander.IsExpanded = true;
			mContent.AddView(expander, new LinearLayout.LayoutParams(-1, -2));

			let catLayout = new LinearLayout();
			catLayout.Orientation = .Vertical;
			catLayout.Spacing = 0;
			expander.SetContent(catLayout);

			for (let editor in categories[cat])
				AddEditorRow(editor, palette, catLayout);
		}

		mNeedsRebuild = false;
	}

	private void AddEditorRow(PropertyEditor editor, Palette palette, LinearLayout target = null)
	{
		let container = target ?? mContent;

		let row = new LinearLayout();
		row.Orientation = .Horizontal;
		row.Spacing = 4;
		row.Padding = .(4, 2, 4, 2);
		container.AddView(row, new LinearLayout.LayoutParams(-1, (int32)mRowHeight));

		// Label
		let label = new Label(editor.PropertyName);
		label.FontSize = 12;
		label.VerticalAlignment = .Middle;
		let labelLp = new LinearLayout.LayoutParams(0, -1);
		labelLp.Weight = mLabelWidthRatio;
		row.AddView(label, labelLp);

		// Editor view
		let editorView = editor.GetOrCreateView();
		if (editorView != null)
		{
			let editorLp = new LinearLayout.LayoutParams(0, -1);
			editorLp.Weight = 1.0f - mLabelWidthRatio;
			row.AddView(editorView, editorLp);
		}
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		if (mNeedsRebuild)
			RebuildLayout();

		float w = widthSpec.Resolve(200, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(200, MinHeight, MaxHeight);
		mScrollView.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(h));
		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		mScrollView.Layout(0, 0, width, height);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		let bgColor = theme?.GetColor("PropertyGrid", "background") ?? palette.Surface;
		ctx.FillRect(.(0, 0, Width, Height), bgColor);

		mScrollView.Draw(ctx);
	}

	public override void OnThemeChanged()
	{
		base.OnThemeChanged();
		mNeedsRebuild = true;
	}
}
