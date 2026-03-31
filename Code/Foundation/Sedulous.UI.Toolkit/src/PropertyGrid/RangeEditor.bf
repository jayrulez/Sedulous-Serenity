namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;

/// Property editor for ranged float values. Uses a Slider + NumberField side by side.
public class RangeEditor : PropertyEditor
{
	private float mValue;
	private float mMin;
	private float mMax;
	private float mStep;
	private Slider mSlider;
	private NumberField mField;
	private bool mSyncing;

	public float Value
	{
		get => mValue;
		set
		{
			mValue = value;
			if (!mSyncing) RefreshView();
			NotifyValueChanged();
		}
	}

	public float Min { get => mMin; set { mMin = value; } }
	public float Max { get => mMax; set { mMax = value; } }
	public float Step { get => mStep; set { mStep = value; } }

	public this(StringView name, float value, float min = 0, float max = 1, float step = 0.01f, StringView category = "")
		: base(name, category)
	{
		mValue = value;
		mMin = min;
		mMax = max;
		mStep = step;
	}

	protected override View CreateEditorView()
	{
		let row = new LinearLayout();
		row.Orientation = .Horizontal;
		row.Spacing = 6;

		// Slider
		mSlider = new Slider();
		mSlider.Min = mMin;
		mSlider.Max = mMax;
		mSlider.Step = mStep;
		mSlider.Value = mValue;
		mSlider.OnValueChanged.Subscribe(new (sl, val) =>
		{
			if (!mSyncing)
			{
				mSyncing = true;
				mValue = val;
				if (mField != null) mField.Value = val;
				NotifyValueChanged();
				mSyncing = false;
			}
		});
		row.AddView(mSlider, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		// Number field showing current value
		mField = new NumberField(mValue, mMin, mMax);
		mField.Step = mStep;
		mField.DecimalPlaces = 2;
		mField.ShowSpinners = false;
		mField.OnValueChanged.Subscribe(new (nf, val) =>
		{
			if (!mSyncing)
			{
				mSyncing = true;
				mValue = val;
				if (mSlider != null) mSlider.Value = val;
				NotifyValueChanged();
				mSyncing = false;
			}
		});
		mField.OnEditBegin.Subscribe(new (nf) => BeginEdit());
		mField.OnEditEnd.Subscribe(new (nf) => EndEdit());
		mField.OnEditCancelled.Subscribe(new (nf) =>
		{
			mValue = nf.[Friend]mPreEditValue;
			if (mSlider != null) mSlider.Value = mValue;
			CancelEdit();
		});
		row.AddView(mField, new LinearLayout.LayoutParams(60, LayoutParams.MatchParent));

		return row;
	}

	public override void RefreshView()
	{
		if (mSlider != null && !mSyncing)
		{
			mSyncing = true;
			mSlider.Value = mValue;
			if (mField != null) mField.Value = mValue;
			mSyncing = false;
		}
	}

	public override void GetDisplayValue(String outValue)
	{
		outValue.AppendF("{:F2}", mValue);
	}
}
