namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;

/// Property editor for floating-point values. Uses a NumberField.
public class FloatEditor : PropertyEditor
{
	private float mValue;
	private float mMin;
	private float mMax;
	private float mStep;
	private int mDecimalPlaces = 2;
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
	public int DecimalPlaces { get => mDecimalPlaces; set { mDecimalPlaces = value; } }

	public this(StringView name, float value, float min = -1000000, float max = 1000000, float step = 0.1f, StringView category = "")
		: base(name, category)
	{
		mValue = value;
		mMin = min;
		mMax = max;
		mStep = step;
	}

	protected override View CreateEditorView()
	{
		mField = new NumberField(mValue, mMin, mMax);
		mField.Step = mStep;
		mField.DecimalPlaces = mDecimalPlaces;
		mField.OnValueChanged.Subscribe(new (nf, val) =>
		{
			if (!mSyncing) { mSyncing = true; mValue = val; NotifyValueChanged(); mSyncing = false; }
		});
		mField.OnEditBegin.Subscribe(new (nf) => BeginEdit());
		mField.OnEditEnd.Subscribe(new (nf) => EndEdit());
		mField.OnEditCancelled.Subscribe(new (nf) =>
		{
			mValue = nf.[Friend]mPreEditValue;
			CancelEdit();
		});
		return mField;
	}

	public override void RefreshView()
	{
		if (mField != null && !mSyncing) { mSyncing = true; mField.Value = mValue; mSyncing = false; }
	}

	public override void GetDisplayValue(String outValue)
	{
		outValue.AppendF("{:F}", mValue);
	}
}
