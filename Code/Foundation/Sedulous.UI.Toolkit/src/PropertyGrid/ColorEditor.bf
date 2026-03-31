namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Property editor for Color values. Shows a color swatch with an editable hex field.
public class ColorEditor : PropertyEditor
{
	private Color mValue;
	private Panel mSwatch;
	private EditText mHexEdit;
	private bool mSyncing;

	public Color Value
	{
		get => mValue;
		set
		{
			mValue = value;
			if (!mSyncing) RefreshView();
			NotifyValueChanged();
		}
	}

	public this(StringView name, Color value, StringView category = "")
		: base(name, category)
	{
		mValue = value;
	}

	protected override View CreateEditorView()
	{
		let row = new LinearLayout();
		row.Orientation = .Horizontal;
		row.Spacing = 4;

		// Color swatch
		mSwatch = new Panel();
		mSwatch.FillColor = mValue;
		mSwatch.CornerRadius = 3;
		mSwatch.BorderWidth = 1;
		row.AddView(mSwatch, new LinearLayout.LayoutParams(32, -1));

		// Hex input field
		mHexEdit = new EditText();
		mHexEdit.MaxLength = 7;
		SyncHexText();
		mHexEdit.OnSubmit.Subscribe(new (et) =>
		{
			if (!mSyncing)
				ParseHexInput();
		});
		row.AddView(mHexEdit, new LinearLayout.LayoutParams(0, -1, 1));

		return row;
	}

	private void ParseHexInput()
	{
		let text = scope String(mHexEdit.Text);
		if (text.StartsWith('#'))
			text.Remove(0, 1);

		if (text.Length == 6)
		{
			if (uint32.Parse(text, .HexNumber) case .Ok(let hexVal))
			{
				uint8 r = (uint8)((hexVal >> 16) & 0xFF);
				uint8 g = (uint8)((hexVal >> 8) & 0xFF);
				uint8 b = (uint8)(hexVal & 0xFF);

				mSyncing = true;
				BeginEdit();
				mValue = Color(r / 255.0f, g / 255.0f, b / 255.0f, mValue.A / 255.0f);
				if (mSwatch != null)
					mSwatch.FillColor = mValue;
				NotifyValueChanged();
				EndEdit();
				mSyncing = false;
			}
		}
	}

	private void SyncHexText()
	{
		if (mHexEdit == null) return;
		let hex = scope String();
		hex.AppendF("#{0:X2}{1:X2}{2:X2}", (int)mValue.R, (int)mValue.G, (int)mValue.B);
		mHexEdit.Text = hex;
	}

	public override void RefreshView()
	{
		if (mSwatch != null && !mSyncing)
		{
			mSyncing = true;
			mSwatch.FillColor = mValue;
			SyncHexText();
			mSyncing = false;
		}
	}

	public override void GetDisplayValue(String outValue)
	{
		outValue.AppendF("#{0:X2}{1:X2}{2:X2}", (int)mValue.R, (int)mValue.G, (int)mValue.B);
	}
}
