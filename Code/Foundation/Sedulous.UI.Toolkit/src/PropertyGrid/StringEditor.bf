namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;

/// Property editor for string values. Uses an EditText.
public class StringEditor : PropertyEditor
{
	private String mValue = new .() ~ delete _;
	private EditText mEditText;
	private bool mSyncing;

	public StringView Value
	{
		get => mValue;
		set
		{
			mValue.Set(value);
			if (!mSyncing) RefreshView();
			NotifyValueChanged();
		}
	}

	public this(StringView name, StringView value = "", StringView category = "")
		: base(name, category)
	{
		mValue.Set(value);
	}

	private String mPreEditValue = new .() ~ delete _;

	protected override View CreateEditorView()
	{
		let editText = new StringEditorEditText(this);
		mEditText = editText;
		mEditText.Text = mValue;
		mEditText.OnSubmit.Subscribe(new (et) =>
		{
			if (!mSyncing) { mSyncing = true; mValue.Set(et.Text); NotifyValueChanged(); mSyncing = false; }
			EndEdit();
		});
		return mEditText;
	}

	/// EditText subclass that notifies the StringEditor on focus changes.
	private class StringEditorEditText : EditText
	{
		private StringEditor mEditor;

		public this(StringEditor editor) { mEditor = editor; }

		public override void OnFocusGained(FocusEventArgs e)
		{
			base.OnFocusGained(e);
			mEditor.mPreEditValue.Set(mEditor.mValue);
			mEditor.BeginEdit();
		}

		public override void OnFocusLost(FocusEventArgs e)
		{
			base.OnFocusLost(e);
			if (mEditor.IsEditing)
			{
				mEditor.mSyncing = true;
				mEditor.mValue.Set(Text);
				mEditor.NotifyValueChanged();
				mEditor.mSyncing = false;
				mEditor.EndEdit();
			}
		}

		public override void OnKeyDown(KeyEventArgs e)
		{
			if (e.Key == .Escape && mEditor.IsEditing)
			{
				mEditor.mValue.Set(mEditor.mPreEditValue);
				Text = mEditor.mPreEditValue;
				mEditor.CancelEdit();
				e.Handled = true;
				return;
			}
			base.OnKeyDown(e);
		}
	}

	public override void RefreshView()
	{
		if (mEditText != null && !mSyncing) { mSyncing = true; mEditText.Text = mValue; mSyncing = false; }
	}

	public override void GetDisplayValue(String outValue)
	{
		outValue.Append(mValue);
	}
}
