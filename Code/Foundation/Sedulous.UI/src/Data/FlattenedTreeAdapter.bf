namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Wraps an ITreeAdapter as an IListAdapter for use with ListView.
/// Applies indentation via left padding based on node depth.
/// Supports both text symbols and drawable icons for expand/collapse indicators.
public class FlattenedTreeAdapter : IListAdapter, IAdapterObserver
{
	private ITreeAdapter mTreeAdapter;
	private float mIndentPerDepth;
	private List<IAdapterObserver> mObservers = new .() ~ delete _;

	/// Symbol prepended to expanded nodes (e.g. "- "). Owned.
	private String mExpandedSymbol ~ delete _;

	/// Symbol prepended to collapsed nodes with children (e.g. "+ "). Owned.
	private String mCollapsedSymbol ~ delete _;

	/// Prefix for leaf nodes to align with symbols (e.g. "  "). Owned.
	private String mLeafPrefix ~ delete _;

	/// Icon drawable for expanded nodes. Non-owning (theme owns these).
	private Drawable mExpandedIcon;

	/// Icon drawable for collapsed nodes. Non-owning.
	private Drawable mCollapsedIcon;

	/// Size to draw icons at. 0 = use intrinsic size.
	private float mIconSize = 0;

	public this(ITreeAdapter treeAdapter, float indentPerDepth = 20)
	{
		mTreeAdapter = treeAdapter;
		mIndentPerDepth = indentPerDepth;
		mTreeAdapter.RegisterObserver(this);
	}

	public ~this()
	{
		mTreeAdapter.UnregisterObserver(this);
	}

	public int ItemCount => mTreeAdapter.ItemCount;

	public int32 GetItemViewType(int position) => mTreeAdapter.GetItemViewType(position);

	public bool HasIcons => mExpandedIcon != null && mCollapsedIcon != null;

	public View CreateView(int32 viewType)
	{
		let contentView = mTreeAdapter.CreateView(viewType);

		if (HasIcons)
		{
			let row = new LinearLayout();
			row.Orientation = .Horizontal;

			let icon = new IconView();
			let iconSz = GetIconSize();
			row.AddView(icon, new LinearLayout.LayoutParams((int32)iconSz, LayoutParams.MatchParent));

			let contentLp = new LinearLayout.LayoutParams(0, LayoutParams.MatchParent);
			contentLp.Weight = 1;
			row.AddView(contentView, contentLp);

			return row;
		}

		return contentView;
	}

	public void BindView(View view, int position)
	{
		int depth = mTreeAdapter.GetDepth(position);
		float indent = depth * mIndentPerDepth;

		if (HasIcons)
		{
			if (let row = view as LinearLayout)
			{
				// Set indentation on the row
				var padding = row.Padding;
				padding.Left = indent + 4;
				row.Padding = padding;

				// Set icon
				if (let iconView = row.GetChildAt(0) as IconView)
				{
					if (mTreeAdapter.HasChildren(position))
						iconView.Icon = mTreeAdapter.IsExpanded(position) ? mExpandedIcon : mCollapsedIcon;
					else
						iconView.Icon = null; // leaf: no icon
				}

				// Bind content
				if (row.ChildCount > 1)
					mTreeAdapter.BindView(row.GetChildAt(1), position);
			}
		}
		else
		{
			mTreeAdapter.BindView(view, position);

			// Apply indentation via left padding
			var padding = view.Padding;
			padding.Left = indent + 4;
			view.Padding = padding;

			// Prepend expand/collapse symbol
			if (let label = view as Label)
			{
				StringView symbol;
				if (mTreeAdapter.HasChildren(position))
					symbol = mTreeAdapter.IsExpanded(position) ? ExpandedSymbol : CollapsedSymbol;
				else
					symbol = LeafPrefix;

				let prefixed = scope:: String(symbol.Length + label.Text.Length);
				prefixed.Append(symbol);
				prefixed.Append(label.Text);
				label.Text = prefixed;
			}
		}
	}

	public void RegisterObserver(IAdapterObserver observer)
	{
		if (!mObservers.Contains(observer))
			mObservers.Add(observer);
	}

	public void UnregisterObserver(IAdapterObserver observer)
	{
		mObservers.Remove(observer);
	}

	/// Forward data changes from ITreeAdapter.
	public void OnDataChanged()
	{
		for (let obs in mObservers)
			obs.OnDataChanged();
	}

	/// Access to underlying tree adapter.
	public ITreeAdapter TreeAdapter => mTreeAdapter;

	/// Indent per depth level.
	public float IndentPerDepth
	{
		get => mIndentPerDepth;
		set { mIndentPerDepth = value; }
	}

	/// Set the text symbols used for expand/collapse indicators.
	public void SetSymbols(StringView expanded, StringView collapsed, StringView leaf)
	{
		delete mExpandedSymbol;
		mExpandedSymbol = new String(expanded);

		delete mCollapsedSymbol;
		mCollapsedSymbol = new String(collapsed);

		delete mLeafPrefix;
		mLeafPrefix = new String(leaf);
	}

	/// Set drawable icons for expand/collapse. Non-owning references.
	/// When set, icons take priority over text symbols.
	public void SetIcons(Drawable expanded, Drawable collapsed, float iconSize = 0)
	{
		mExpandedIcon = expanded;
		mCollapsedIcon = collapsed;
		mIconSize = iconSize;
	}

	public StringView ExpandedSymbol => (mExpandedSymbol != null) ? mExpandedSymbol : "- ";
	public StringView CollapsedSymbol => (mCollapsedSymbol != null) ? mCollapsedSymbol : "+ ";
	public StringView LeafPrefix => (mLeafPrefix != null) ? mLeafPrefix : "  ";

	private float GetIconSize()
	{
		if (mIconSize > 0) return mIconSize;
		let sz = mExpandedIcon.IntrinsicSize;
		return Math.Max(sz.Width, sz.Height);
	}

	/// A lightweight view that draws a Drawable without owning it.
	private class IconView : View
	{
		public Drawable Icon;

		protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
		{
			float w = 0, h = 0;
			if (Icon != null)
			{
				let sz = Icon.IntrinsicSize;
				w = sz.Width;
				h = sz.Height;
			}
			SetMeasuredDimension(
				widthSpec.Resolve(w + Padding.Horizontal, MinWidth, MaxWidth),
				heightSpec.Resolve(h + Padding.Vertical, MinHeight, MaxHeight)
			);
		}

		protected override void OnDraw(DrawContext ctx)
		{
			if (Icon == null) return;

			let content = ContentBounds;
			let sz = Icon.IntrinsicSize;
			// Center icon in content area
			float ix = content.X + (content.Width - sz.Width) * 0.5f;
			float iy = content.Y + (content.Height - sz.Height) * 0.5f;
			Icon.Draw(ctx, .(ix, iy, sz.Width, sz.Height));
		}
	}
}
