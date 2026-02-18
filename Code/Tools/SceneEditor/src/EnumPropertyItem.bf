namespace SceneEditor;

using System;
using System.Collections;
using Sedulous.GUI;

/// PropertyItem for enum fields with a ComboBox dropdown editor.
class EnumPropertyItem : PropertyItem
{
	public delegate String() ValueGetter ~ delete _;
	public delegate void(StringView) ValueSetter ~ delete _;

	private ComboBox mComboBox;
	private bool mUpdating = false;

	public this(StringView name, Span<StringView> options, delegate String() getter, delegate void(StringView) setter) : base(name, .Enum)
	{
		ValueGetter = getter;
		ValueSetter = setter;

		// Store options for refresh lookups
		EnumValues = new List<String>();
		for (let opt in options)
			EnumValues.Add(new String(opt));
	}

	public override UIElement CreateEditorControl()
	{
		mComboBox = new ComboBox();

		for (let opt in EnumValues)
			mComboBox.AddText(opt);

		// Set initial selection
		if (ValueGetter != null)
		{
			let current = ValueGetter();
			SelectByText(current);
			delete current;
		}

		mComboBox.SelectionChanged.Subscribe(new (cb) => OnSelectionChanged());

		return mComboBox;
	}

	public override void RefreshEditorControl()
	{
		if (ValueGetter == null || mComboBox == null) return;
		mUpdating = true;
		let current = ValueGetter();
		SelectByText(current);
		delete current;
		mUpdating = false;
	}

	private void SelectByText(StringView text)
	{
		for (int i = 0; i < mComboBox.ItemCount; i++)
		{
			let item = mComboBox.GetItem(i);
			if (let str = item as String)
			{
				if (StringView(str) == text)
				{
					mComboBox.SelectedIndex = i;
					return;
				}
			}
		}
		mComboBox.SelectedIndex = -1;
	}

	private void OnSelectionChanged()
	{
		if (mUpdating) return;
		if (ValueSetter == null) return;

		let selected = mComboBox.SelectedItem;
		if (let str = selected as String)
		{
			ValueSetter(str);
			OwnerGrid?.NotifyPropertyChanged(this);
		}
	}
}
