namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Numeric input control with optional spinner (up/down) buttons.
/// Wraps an EditText with numeric validation.
public class NumberField : ViewGroup
{
	private EditText mEditText;
	private float mValue;
	private float mMin = -1000000;
	private float mMax = 1000000;
	private float mStep = 1;
	private int mDecimalPlaces = 2;
	private bool mShowSpinners = true;
	private float mSpinnerWidth = 20;
	private bool mAllowMouseWheel = true;
	private bool mSyncing; // Prevent re-entrancy during sync

	private EventAccessor<delegate void(NumberField, float)> mOnValueChanged = new .() ~ delete _;
	private EventAccessor<delegate void(NumberField)> mOnEditBegin = new .() ~ delete _;
	private EventAccessor<delegate void(NumberField)> mOnEditEnd = new .() ~ delete _;
	private EventAccessor<delegate void(NumberField)> mOnEditCancelled = new .() ~ delete _;
	private bool mIsEditing;
	private float mPreEditValue; // Value before current edit gesture started

	public float Value
	{
		get => mValue;
		set
		{
			float clamped = Math.Clamp(value, mMin, mMax);
			if (mValue != clamped)
			{
				mValue = clamped;
				SyncTextToValue();
				mOnValueChanged.[Friend]Invoke(this, clamped);
			}
		}
	}

	public float Min
	{
		get => mMin;
		set { mMin = value; if (mMax < mMin) mMax = mMin; Value = mValue; }
	}

	public float Max
	{
		get => mMax;
		set { mMax = value; if (mMin > mMax) mMin = mMax; Value = mValue; }
	}

	public float Step
	{
		get => mStep;
		set { mStep = Math.Max(0.001f, value); }
	}

	public int DecimalPlaces
	{
		get => mDecimalPlaces;
		set { mDecimalPlaces = Math.Clamp(value, 0, 10); SyncTextToValue(); }
	}

	public bool ShowSpinners
	{
		get => mShowSpinners;
		set { mShowSpinners = value; InvalidateLayout(); }
	}

	/// Whether mouse wheel adjusts the value.
	public bool AllowMouseWheel
	{
		get => mAllowMouseWheel;
		set { mAllowMouseWheel = value; }
	}

	/// Subscribe to value change events.
	public EventAccessor<delegate void(NumberField, float)> OnValueChanged => mOnValueChanged;

	/// Fired when an edit gesture begins (text field focused, drag started).
	public EventAccessor<delegate void(NumberField)> OnEditBegin => mOnEditBegin;

	/// Fired when an edit gesture ends (Enter pressed, focus lost, drag ended).
	public EventAccessor<delegate void(NumberField)> OnEditEnd => mOnEditEnd;

	/// Fired when an edit gesture is cancelled (Escape pressed).
	public EventAccessor<delegate void(NumberField)> OnEditCancelled => mOnEditCancelled;

	/// Whether an edit gesture is in progress.
	public bool IsEditing => mIsEditing;

	public this()
	{
		mEditText = new EditText();
		AddView(mEditText);

		mEditText.OnSubmit.Subscribe(new => OnEditSubmit);
		mEditText.OnTextChanged.Subscribe(new => OnEditTextChanged);

		SyncTextToValue();
	}

	public this(float initialValue, float min, float max) : this()
	{
		mMin = min;
		mMax = max;
		mValue = Math.Clamp(initialValue, min, max);
		SyncTextToValue();
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(100, MinWidth, MaxWidth);
		float editW = mShowSpinners ? w - mSpinnerWidth : w;
		if (editW < 0) editW = 0;

		mEditText.Measure(MeasureSpec.MakeExactly(editW), heightSpec);

		SetMeasuredDimension(
			widthSpec.Resolve(w, MinWidth, MaxWidth),
			heightSpec.Resolve(mEditText.MeasuredHeight, MinHeight, MaxHeight)
		);
	}

	protected override void OnLayout(float width, float height)
	{
		float editW = mShowSpinners ? width - mSpinnerWidth : width;
		if (editW < 0) editW = 0;
		mEditText.Layout(0, 0, editW, height);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		// Draw the EditText child
		mEditText.Draw(ctx);

		// Draw spinner buttons if enabled
		if (mShowSpinners)
		{
			let theme = Context?.Theme;
			let palette = theme?.Palette ?? Palette.Dark;

			float editW = Width - mSpinnerWidth;
			float halfH = Height * 0.5f;

			// Spinner background
			let spinnerBgColor = theme?.GetColor("NumberField", "spinnerBackground") ?? Palette.Darken(palette.Surface, 0.05f);
			let spinnerBorder = theme?.GetColor("NumberField", "spinnerBorder") ?? palette.Border;

			// Check for drawable icons
			let upIconDrawable = theme?.GetDrawable("NumberField", "spinnerUpIcon");
			let downIconDrawable = theme?.GetDrawable("NumberField", "spinnerDownIcon");

			// Up button (top half)
			ctx.FillRect(.(editW, 0, mSpinnerWidth, halfH), spinnerBgColor);
			ctx.DrawBorderRect(.(editW, 0, mSpinnerWidth, halfH), spinnerBorder, 1);

			if (upIconDrawable != null)
			{
				let sz = upIconDrawable.IntrinsicSize;
				float iw = (sz.Width > 0) ? sz.Width : 10;
				float ih = (sz.Height > 0) ? sz.Height : 5;
				float ix = editW + (mSpinnerWidth - iw) * 0.5f;
				float iy = (halfH - ih) * 0.5f;
				upIconDrawable.Draw(ctx, .(ix, iy, iw, ih));
			}
			else
			{
				let arrowColor = theme?.GetColor("NumberField", "spinnerArrow") ?? palette.Text;
				float upCX = editW + mSpinnerWidth * 0.5f;
				float upCY = halfH * 0.5f;
				float arrowSize = 3;
				Vector2[3] upArrow = .(
					.(upCX, upCY - arrowSize),
					.(upCX - arrowSize, upCY + arrowSize * 0.5f),
					.(upCX + arrowSize, upCY + arrowSize * 0.5f)
				);
				ctx.FillPolygon(upArrow, arrowColor);
			}

			// Down button (bottom half)
			ctx.FillRect(.(editW, halfH, mSpinnerWidth, Height - halfH), spinnerBgColor);
			ctx.DrawBorderRect(.(editW, halfH, mSpinnerWidth, Height - halfH), spinnerBorder, 1);

			if (downIconDrawable != null)
			{
				let sz = downIconDrawable.IntrinsicSize;
				float iw = (sz.Width > 0) ? sz.Width : 10;
				float ih = (sz.Height > 0) ? sz.Height : 5;
				float ix = editW + (mSpinnerWidth - iw) * 0.5f;
				float iy = halfH + (halfH - ih) * 0.5f;
				downIconDrawable.Draw(ctx, .(ix, iy, iw, ih));
			}
			else
			{
				let arrowColor = theme?.GetColor("NumberField", "spinnerArrow") ?? palette.Text;
				float downCX = editW + mSpinnerWidth * 0.5f;
				float downCY = halfH + (Height - halfH) * 0.5f;
				float arrowSize = 3;
				Vector2[3] downArrow = .(
					.(downCX - arrowSize, downCY - arrowSize * 0.5f),
					.(downCX + arrowSize, downCY - arrowSize * 0.5f),
					.(downCX, downCY + arrowSize)
				);
				ctx.FillPolygon(downArrow, arrowColor);
			}
		}
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		if (mShowSpinners)
		{
			float editW = Width - mSpinnerWidth;
			if (e.LocalX >= editW)
			{
				FireBeginEdit();
				float halfH = Height * 0.5f;
				if (e.LocalY < halfH)
					Value = mValue + mStep; // Up
				else
					Value = mValue - mStep; // Down
				FireEndEdit();
				e.Handled = true;
				return;
			}
		}
	}

	public override void OnMouseWheel(MouseWheelEventArgs e)
	{
		if (!Enabled || !mAllowMouseWheel)
			return;

		if (e.DeltaY != 0)
		{
			FireBeginEdit();
		if (e.DeltaY > 0)
			Value = mValue + mStep;
			else
			Value = mValue - mStep;
			FireEndEdit();
			e.Handled = true;
	}
	}

	private void SyncTextToValue()
	{
		if (mSyncing) return;
		mSyncing = true;

		let formatted = scope String();
		if (mDecimalPlaces == 0)
			formatted.AppendF("{}", (int)Math.Round(mValue));
		else
			formatted.AppendF("{:F}", mValue);

		// Trim to decimal places
		if (mDecimalPlaces > 0)
		{
			// Find decimal point
			int dotIndex = formatted.IndexOf('.');
			if (dotIndex >= 0)
			{
				int maxLen = dotIndex + 1 + mDecimalPlaces;
				if (formatted.Length > maxLen)
					formatted.RemoveToEnd(maxLen);
			}
		}

		mEditText.Text = formatted;
		mSyncing = false;
	}

	private void SyncValueFromText()
	{
		if (mSyncing) return;
		mSyncing = true;

		let text = scope String(mEditText.Text);
		switch (float.Parse(text))
		{
		case .Ok(let parsed):
			float clamped = Math.Clamp(parsed, mMin, mMax);
			if (mValue != clamped)
			{
				mValue = clamped;
				mOnValueChanged.[Friend]Invoke(this, clamped);
			}
		case .Err:
			// Invalid text — revert to current value
			break;
		}

		// Always sync display back (in case of clamping or revert)
		mSyncing = false;
		SyncTextToValue();
	}

	private void OnEditSubmit(EditText editText)
	{
		SyncValueFromText();
		FireEndEdit();
	}

	private void OnEditTextChanged(EditText editText)
	{
		// Don't parse on every keystroke — wait for submit (Enter)
	}

	public override void OnFocusGained(FocusEventArgs e)
	{
		FireBeginEdit();
	}

	public override void OnFocusLost(FocusEventArgs e)
	{
		if (mIsEditing)
		{
			SyncValueFromText();
			FireEndEdit();
		}
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled)
			return;

		if (e.Key == .Up)
		{
			FireBeginEdit();
			Value = mValue + mStep;
			FireEndEdit();
			e.Handled = true;
		}
		else if (e.Key == .Down)
		{
			FireBeginEdit();
			Value = mValue - mStep;
			FireEndEdit();
			e.Handled = true;
		}
		else if (e.Key == .Escape && mIsEditing)
		{
			// Revert to pre-edit value
			mValue = mPreEditValue;
			SyncTextToValue();
			FireCancelEdit();
			e.Handled = true;
		}
	}

	private void FireBeginEdit()
	{
		if (!mIsEditing)
		{
			mIsEditing = true;
			mPreEditValue = mValue;
			mOnEditBegin.[Friend]Invoke(this);
		}
	}

	private void FireEndEdit()
	{
		if (mIsEditing)
		{
			mIsEditing = false;
			mOnEditEnd.[Friend]Invoke(this);
		}
	}

	private void FireCancelEdit()
	{
		if (mIsEditing)
		{
			mIsEditing = false;
			mOnEditCancelled.[Friend]Invoke(this);
		}
	}
}
