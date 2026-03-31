namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Log severity level.
public enum LogLevel
{
	Debug,
	Info,
	Warning,
	Error
}

/// Scrollable log view with level-based filtering and auto-scroll.
/// Contains a ListView internally with a custom adapter for log entries.
public class LogView : ViewGroup
{
	public struct LogEntry
	{
		public String Message;
		public LogLevel Level;
		public float Timestamp;
	}

	private List<LogEntry> mEntries = new .() ~ { for (var e in _) delete e.Message; delete _; };
	private List<int> mFilteredIndices = new .() ~ delete _;
	private int mMaxEntries = 10000;
	private bool mShowDebug = true;
	private bool mShowInfo = true;
	private bool mShowWarning = true;
	private bool mShowError = true;
	private bool mAutoScroll = true;

	private ListView mListView;
	private LogAdapter mAdapter;
	public float mFontSize = 12;
	private float mItemHeight = 18;

	public float FontSize
	{
		get => mFontSize;
		set { mFontSize = Math.Max(1, value); }
	}

	public float ItemHeight
	{
		get => mItemHeight;
		set { mItemHeight = Math.Max(8, value); mListView.FixedItemHeight = mItemHeight; }
	}

	public bool AutoScroll { get => mAutoScroll; set { mAutoScroll = value; } }

	public bool ShowDebug
	{
		get => mShowDebug;
		set { if (mShowDebug != value) { mShowDebug = value; RebuildFilteredList(); } }
	}

	public bool ShowInfo
	{
		get => mShowInfo;
		set { if (mShowInfo != value) { mShowInfo = value; RebuildFilteredList(); } }
	}

	public bool ShowWarning
	{
		get => mShowWarning;
		set { if (mShowWarning != value) { mShowWarning = value; RebuildFilteredList(); } }
	}

	public bool ShowError
	{
		get => mShowError;
		set { if (mShowError != value) { mShowError = value; RebuildFilteredList(); } }
	}

	public int MaxEntries
	{
		get => mMaxEntries;
		set { mMaxEntries = Math.Max(1, value); TrimEntries(); }
	}

	public int EntryCount => mEntries.Count;
	public int VisibleEntryCount => mFilteredIndices.Count;

	public int FilteredCount => mFilteredIndices.Count;

	public this()
	{
		mAdapter = new LogAdapter(this);

		mListView = new ListView();
		mListView.FixedItemHeight = mItemHeight;
		mListView.SetAdapter(mAdapter);
		AddView(mListView);
	}

	public ~this()
	{
		// Detach adapter before it gets deleted — mListView is still alive here
		mListView.SetAdapter(null);
		delete mAdapter;
	}

	/// Add a log entry with the given level and message.
	public void AddEntry(LogLevel level, StringView message)
	{
		LogEntry entry;
		entry.Message = new String(message);
		entry.Level = level;
		entry.Timestamp = (Context != null) ? Context.TotalTime : 0;
		mEntries.Add(entry);

		TrimEntries();

		if (PassesFilter(level))
		{
			mFilteredIndices.Add(mEntries.Count - 1);
			mAdapter.NotifyDataChanged();

			if (mAutoScroll)
				mListView.ScrollToBottom();
		}
	}

	/// Clear all entries.
	public void Clear()
	{
		for (var e in mEntries)
			delete e.Message;
		mEntries.Clear();
		mFilteredIndices.Clear();
		mAdapter.NotifyDataChanged();
	}

	public LogEntry GetFilteredEntry(int filteredIndex)
	{
		if (filteredIndex >= 0 && filteredIndex < mFilteredIndices.Count)
		{
			int actualIndex = mFilteredIndices[filteredIndex];
			if (actualIndex >= 0 && actualIndex < mEntries.Count)
				return mEntries[actualIndex];
		}
		LogEntry empty;
		empty.Message = null;
		empty.Level = .Info;
		empty.Timestamp = 0;
		return empty;
	}

	public Color GetLevelColor(LogLevel level)
	{
		let theme = Context?.Theme;
		switch (level)
		{
		case .Debug: return theme?.GetColor("LogView", "debugColor") ?? Color(0.6f, 0.6f, 0.6f, 1.0f);
		case .Info: return theme?.GetColor("LogView", "infoColor") ?? Color(0.3f, 0.7f, 1.0f, 1.0f);
		case .Warning: return theme?.GetColor("LogView", "warningColor") ?? Color(1.0f, 0.8f, 0.2f, 1.0f);
		case .Error: return theme?.GetColor("LogView", "errorColor") ?? Color(1.0f, 0.3f, 0.3f, 1.0f);
		}
	}

	private bool PassesFilter(LogLevel level)
	{
		switch (level)
		{
		case .Debug: return mShowDebug;
		case .Info: return mShowInfo;
		case .Warning: return mShowWarning;
		case .Error: return mShowError;
		}
	}

	private void RebuildFilteredList()
	{
		mFilteredIndices.Clear();
		for (int i = 0; i < mEntries.Count; i++)
		{
			if (PassesFilter(mEntries[i].Level))
				mFilteredIndices.Add(i);
		}
		mAdapter.NotifyDataChanged();
	}

	private void TrimEntries()
	{
		if (mEntries.Count <= mMaxEntries)
			return;

		int removeCount = mEntries.Count - mMaxEntries;
		for (int i = 0; i < removeCount; i++)
			delete mEntries[i].Message;
		mEntries.RemoveRange(0, removeCount);

		// Rebuild filter indices since indices shifted
		RebuildFilteredList();
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(200, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(100, MinHeight, MaxHeight);
		mListView.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(h));
		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		mListView.Layout(0, 0, width, height);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		let bgColor = theme?.GetColor("LogView", "background") ?? Palette.Darken(palette.Surface, 0.1f);
		ctx.FillRect(.(0, 0, Width, Height), bgColor);

		mListView.Draw(ctx);
	}

	/// Private adapter for the LogView's ListView.
	private class LogAdapter : ListAdapter
	{
		private LogView mOwner;

		public this(LogView owner) { mOwner = owner; }

		public override int ItemCount => mOwner.FilteredCount;

		public override View CreateView(int32 viewType)
		{
			let row = new LinearLayout();
			row.Orientation = .Horizontal;
			row.Spacing = 4;

			let indicator = new Panel();
			indicator.CornerRadius = 0;
			row.AddView(indicator, new LinearLayout.LayoutParams(4, LayoutParams.MatchParent));

			let label = new Label();
			label.FontSize = mOwner.mFontSize;
			label.VerticalAlignment = .Middle;
			label.Padding = .(4, 0, 4, 0);
			row.AddView(label, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

			return row;
		}

		public override void BindView(View view, int position)
		{
			if (let row = view as LinearLayout)
			{
				let entry = mOwner.GetFilteredEntry(position);

				if (row.ChildCount >= 2)
				{
					if (let indicator = row.GetChildAt(0) as Panel)
						indicator.FillColor = mOwner.GetLevelColor(entry.Level);

					if (let label = row.GetChildAt(1) as Label)
					{
						if (entry.Message != null)
							label.Text = entry.Message;
						else
							label.Text = "";
					}
				}
			}
		}
	}
}
