namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;

/// Property editor for boolean values. Uses a CheckBox.
public class BoolEditor : PropertyEditor
{
	private bool mValue;
	private CheckBox mCheckBox;
	private bool mSyncing;

	public bool Value
	{
		get => mValue;
		set
		{
			mValue = value;
			if (!mSyncing) RefreshView();
			NotifyValueChanged();
		}
	}

	public this(StringView name, bool value, StringView category = "")
		: base(name, category)
	{
		mValue = value;
	}

	protected override View CreateEditorView()
	{
		mCheckBox = new CheckBox("");
		mCheckBox.IsChecked = mValue;
		mCheckBox.OnCheckedChanged.Subscribe(new (cb, isChecked) =>
		{
			if (!mSyncing) { mSyncing = true; BeginEdit(); mValue = isChecked; NotifyValueChanged(); EndEdit(); mSyncing = false; }
		});
		return mCheckBox;
	}

	public override void RefreshView()
	{
		if (mCheckBox != null && !mSyncing) { mSyncing = true; mCheckBox.IsChecked = mValue; mSyncing = false; }
	}

	public override void GetDisplayValue(String outValue)
	{
		outValue.Append(mValue ? "True" : "False");
	}
}
