namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;

/// Property editor for integer values. Uses a NumberField with DecimalPlaces=0.
public class IntEditor : PropertyEditor
{
	private int mValue;
	private int mMin;
	private int mMax;
	private int mStep;
	private NumberField mField;
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

	public int Min { get => mMin; set { mMin = value; } }
	public int Max { get => mMax; set { mMax = value; } }
	public int Step { get => mStep; set { mStep = value; } }

	public this(StringView name, int value, int min = -1000000, int max = 1000000, int step = 1, StringView category = "")
		: base(name, category)
	{
		mValue = value;
		mMin = min;
		mMax = max;
		mStep = step;
	}

	protected override View CreateEditorView()
	{
		mField = new NumberField((float)mValue, (float)mMin, (float)mMax);
		mField.Step = (float)mStep;
		mField.DecimalPlaces = 0;
		mField.OnValueChanged.Subscribe(new (nf, val) =>
		{
			if (!mSyncing) { mSyncing = true; mValue = (int)Math.Round(val); NotifyValueChanged(); mSyncing = false; }
		});
		mField.OnEditBegin.Subscribe(new (nf) => BeginEdit());
		mField.OnEditEnd.Subscribe(new (nf) => EndEdit());
		mField.OnEditCancelled.Subscribe(new (nf) =>
		{
			mValue = (int)Math.Round(nf.[Friend]mPreEditValue);
			CancelEdit();
		});
		return mField;
	}

	public override void RefreshView()
	{
		if (mField != null && !mSyncing) { mSyncing = true; mField.Value = (float)mValue; mSyncing = false; }
	}

	public override void GetDisplayValue(String outValue)
	{
		outValue.AppendF("{}", mValue);
	}
}
