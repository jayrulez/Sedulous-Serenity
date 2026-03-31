namespace Sedulous.UI;

using System;

/// Text input that masks characters for password entry.
/// Copy and cut are disabled by default to prevent leaking passwords.
public class PasswordBox : EditText
{
	private char32 mMaskChar = '*';

	public char32 MaskChar
	{
		get => mMaskChar;
		set { mMaskChar = value; Invalidate(); }
	}

	public this() : base()
	{
		mBehavior.AllowClipboardCopy = false;
	}

	public this(StringView hint) : base(hint)
	{
		mBehavior.AllowClipboardCopy = false;
	}

	protected override void GetDisplayText(String outText)
	{
		outText.Clear();
		for (let c in Text.DecodedChars)
		{
			outText.Append(mMaskChar);
		}
	}
}
