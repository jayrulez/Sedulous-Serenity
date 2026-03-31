namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

/// Property editor for Vector2 values. Uses two NumberFields (X, Y) side by side.
public class Vector2Editor : PropertyEditor
{
	private Vector2 mValue;
	private float mMin;
	private float mMax;
	private float mStep;
	private NumberField mXField;
	private NumberField mYField;
	private bool mSyncing;

	public Vector2 Value
	{
		get => mValue;
		set
		{
			mValue = value;
			if (!mSyncing) RefreshView();
			NotifyValueChanged();
		}
	}

	public this(StringView name, Vector2 value, float min = -100000, float max = 100000, float step = 0.1f, StringView category = "")
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
		row.Spacing = 4;

		// X label + field
		let xLabel = new Label("X");
		xLabel.FontSize = 11;
		xLabel.VerticalAlignment = .Middle;
		xLabel.MinWidth = 12;
		row.AddView(xLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		mXField = new NumberField(mValue.X, mMin, mMax);
		mXField.Step = mStep;
		mXField.DecimalPlaces = 2;
		mXField.OnValueChanged.Subscribe(new (nf, val) =>
		{
			if (!mSyncing) { mSyncing = true; mValue.X = val; NotifyValueChanged(); mSyncing = false; }
		});
		WireFieldEditEvents(mXField);
		row.AddView(mXField, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		// Y label + field
		let yLabel = new Label("Y");
		yLabel.FontSize = 11;
		yLabel.VerticalAlignment = .Middle;
		yLabel.MinWidth = 12;
		row.AddView(yLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		mYField = new NumberField(mValue.Y, mMin, mMax);
		mYField.Step = mStep;
		mYField.DecimalPlaces = 2;
		mYField.OnValueChanged.Subscribe(new (nf, val) =>
		{
			if (!mSyncing) { mSyncing = true; mValue.Y = val; NotifyValueChanged(); mSyncing = false; }
		});
		WireFieldEditEvents(mYField);
		row.AddView(mYField, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		return row;
	}

	private void WireFieldEditEvents(NumberField field)
	{
		field.OnEditBegin.Subscribe(new (nf) => BeginEdit());
		field.OnEditEnd.Subscribe(new (nf) => EndEdit());
		field.OnEditCancelled.Subscribe(new (nf) =>
		{
			// Revert whichever component was being edited
			if (nf == mXField) mValue.X = nf.[Friend]mPreEditValue;
			else if (nf == mYField) mValue.Y = nf.[Friend]mPreEditValue;
			RefreshView();
			CancelEdit();
		});
	}

	public override void RefreshView()
	{
		if (mXField != null && !mSyncing)
		{
			mSyncing = true;
			mXField.Value = mValue.X;
			mYField.Value = mValue.Y;
			mSyncing = false;
		}
	}

	public override void GetDisplayValue(String outValue)
	{
		outValue.AppendF("({:F2}, {:F2})", mValue.X, mValue.Y);
	}
}
