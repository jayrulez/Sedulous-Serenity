namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;

/// Property editor for enumeration values. Uses a ComboBox with string items.
public class EnumEditor : PropertyEditor
{
	private int mValue;
	private List<String> mItems = new .() ~ { for (var s in _) delete s; delete _; };
	private ComboBox mComboBox;
	private bool mSyncing;

	public int Value
	{
		get => mValue;
		set
		{
			mValue = value;
			if (!mSyncing) RefreshView();
			NotifyValueChanged();
		}
	}

	public this(StringView name, int value, Span<StringView> items, StringView category = "")
		: base(name, category)
	{
		mValue = value;
		for (let item in items)
			mItems.Add(new String(item));
	}

	protected override View CreateEditorView()
	{
		mComboBox = new ComboBox();
		for (let item in mItems)
			mComboBox.AddItem(item);
		mComboBox.SelectedIndex = mValue;
		mComboBox.OnSelectionChanged.Subscribe(new (cb, idx) =>
		{
			if (!mSyncing) { mSyncing = true; BeginEdit(); mValue = idx; NotifyValueChanged(); EndEdit(); mSyncing = false; }
		});
		return mComboBox;
	}

	public override void RefreshView()
	{
		if (mComboBox != null && !mSyncing)
		{
			mSyncing = true;
			mComboBox.SelectedIndex = mValue;
			mSyncing = false;
		}
	}

	public override void GetDisplayValue(String outValue)
	{
		if (mValue >= 0 && mValue < mItems.Count)
			outValue.Append(mItems[mValue]);
		else
			outValue.AppendF("{}", mValue);
	}
}
