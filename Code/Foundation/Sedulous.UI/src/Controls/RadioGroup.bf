namespace Sedulous.UI;

using System;
using Sedulous.Core;

/// LinearLayout subclass that manages mutual exclusion of RadioButton children.
/// When one RadioButton is checked, all others are unchecked.
public class RadioGroup : LinearLayout
{
	private RadioButton mCheckedButton;
	private bool mUpdating;

	private EventAccessor<delegate void(RadioGroup, RadioButton)> mOnSelectionChanged = new .() ~ delete _;

	/// The currently checked RadioButton, or null.
	public RadioButton CheckedButton => mCheckedButton;

	/// Subscribe to selection change events.
	public EventAccessor<delegate void(RadioGroup, RadioButton)> OnSelectionChanged => mOnSelectionChanged;

	public this()
	{
		Orientation = .Vertical;
		Spacing = 4;
	}

	/// Add a RadioButton child and subscribe to its checked events.
	public void AddRadioButton(RadioButton radio)
	{
		base.AddView(radio);
		radio.OnCheckedChanged.Subscribe(new => OnRadioCheckedChanged);
	}

	/// Add a RadioButton child with LayoutParams.
	public void AddRadioButton(RadioButton radio, Sedulous.UI.LayoutParams lp)
	{
		base.AddView(radio, lp);
		radio.OnCheckedChanged.Subscribe(new => OnRadioCheckedChanged);
	}

	private void OnRadioCheckedChanged(RadioButton button, bool isChecked)
	{
		if (mUpdating)
			return;

		if (!isChecked)
			return;

		mUpdating = true;

		// Uncheck all other RadioButtons
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (let radio = child as RadioButton)
			{
				if (radio != button && radio.IsChecked)
					radio.IsChecked = false;
			}
		}

		mCheckedButton = button;
		mUpdating = false;

		mOnSelectionChanged.[Friend]Invoke(this, button);
	}

	/// Programmatically select a RadioButton by index.
	public void CheckAt(int index)
	{
		let child = GetChildAt(index);
		if (let radio = child as RadioButton)
			radio.IsChecked = true;
	}

	/// Clear the selection.
	public void ClearCheck()
	{
		mUpdating = true;
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (let radio = child as RadioButton)
				radio.IsChecked = false;
		}
		mCheckedButton = null;
		mUpdating = false;
	}
}
