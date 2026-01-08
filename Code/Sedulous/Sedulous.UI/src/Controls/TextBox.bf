using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Fonts;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// An editable text input control.
public class TextBox : Control
{
	private String mText ~ delete _;
	private String mPlaceholder ~ delete _;
	private int mCaretPosition = 0;
	private int mSelectionStart = -1;
	private int mSelectionLength = 0;
	private float mScrollOffset = 0;
	private bool mIsReadOnly = false;
	private int mMaxLength = int.MaxValue;

	// Text changed event
	private EventAccessor<delegate void(TextBox, StringView)> mTextChangedEvent = new .() ~ delete _;

	/// Event fired when the text changes.
	public EventAccessor<delegate void(TextBox, StringView)> TextChanged => mTextChangedEvent;

	/// The text content.
	public StringView Text
	{
		get => mText ?? "";
		set
		{
			if (mText == null)
				mText = new String();

			let newText = scope String(value);
			if (newText.Length > mMaxLength)
				newText.RemoveToEnd(mMaxLength);

			if (!mText.Equals(newText))
			{
				mText.Set(newText);
				mCaretPosition = Math.Min(mCaretPosition, mText.Length);
				ClearSelection();
				OnTextChanged();
				InvalidateVisual();
			}
		}
	}

	/// Placeholder text shown when empty.
	public StringView Placeholder
	{
		get => mPlaceholder ?? "";
		set
		{
			if (mPlaceholder == null)
				mPlaceholder = new String();
			mPlaceholder.Set(value);
			InvalidateVisual();
		}
	}

	/// The current caret position.
	public int CaretPosition
	{
		get => mCaretPosition;
		set
		{
			let textLen = mText?.Length ?? 0;
			mCaretPosition = Math.Clamp(value, 0, textLen);
			EnsureCaretVisible();
			InvalidateVisual();
		}
	}

	/// The start of the selection (-1 if no selection).
	public int SelectionStart
	{
		get => mSelectionStart;
		set { mSelectionStart = value; InvalidateVisual(); }
	}

	/// The length of the selection.
	public int SelectionLength
	{
		get => mSelectionLength;
		set { mSelectionLength = Math.Max(0, value); InvalidateVisual(); }
	}

	/// Whether the text box is read-only.
	public bool IsReadOnly
	{
		get => mIsReadOnly;
		set => mIsReadOnly = value;
	}

	/// Maximum number of characters allowed.
	public int MaxLength
	{
		get => mMaxLength;
		set => mMaxLength = Math.Max(1, value);
	}

	/// The selected text, if any.
	public StringView SelectedText
	{
		get
		{
			if (mSelectionStart < 0 || mSelectionLength <= 0 || mText == null)
				return "";
			let start = Math.Min(mSelectionStart, mText.Length);
			let len = Math.Min(mSelectionLength, mText.Length - start);
			return StringView(mText, start, len);
		}
	}

	public this()
	{
		Focusable = true;
		Background = Color.White;
		BorderBrush = Color.Gray;
		BorderThickness = .(1);
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		// Measure based on font
		let cachedFont = GetCachedFont();
		if (cachedFont != null)
		{
			let lineHeight = cachedFont.Font.Metrics.LineHeight;
			return .(constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : 100, lineHeight + 4);
		}

		// Fallback
		let fontSize = FontSize;
		return .(constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : 100, fontSize * 1.5f);
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		let bounds = ContentBounds;
		let foreground = Foreground ?? Color.Black;
		let hasText = mText != null && mText.Length > 0;

		// Try to render with actual font
		let fontService = GetFontService();
		let cachedFont = GetCachedFont();

		if (fontService != null && cachedFont != null)
		{
			let font = cachedFont.Font;
			let atlas = cachedFont.Atlas;
			let atlasTexture = fontService.GetAtlasTexture(cachedFont);

			if (atlas != null && atlasTexture != null)
			{
				// Draw selection highlight
				if (mSelectionStart >= 0 && mSelectionLength > 0 && IsFocused)
				{
					let selStart = Math.Min(mSelectionStart, mText?.Length ?? 0);
					let selEnd = Math.Min(mSelectionStart + mSelectionLength, mText?.Length ?? 0);

					if (mText != null && selStart < selEnd)
					{
						let textBefore = StringView(mText, 0, selStart);
						let textSelected = StringView(mText, selStart, selEnd - selStart);

						let startX = bounds.X - mScrollOffset + font.MeasureString(textBefore);
						let selWidth = font.MeasureString(textSelected);

						let selRect = RectangleF(startX, bounds.Y, selWidth, bounds.Height);
						drawContext.FillRect(selRect, Color(0, 120, 215, 128));
					}
				}

				// Draw text or placeholder
				if (hasText)
				{
					var textBounds = bounds;
					textBounds.X -= mScrollOffset;
					drawContext.DrawText(mText, font, atlas, atlasTexture, textBounds, .Left, .Middle, foreground);
				}
				else if (mPlaceholder != null && mPlaceholder.Length > 0)
				{
					let placeholderColor = Color(128, 128, 128);
					drawContext.DrawText(mPlaceholder, font, atlas, atlasTexture, bounds, .Left, .Middle, placeholderColor);
				}

				// Draw caret
				if (IsFocused && !mIsReadOnly)
				{
					let textBeforeCaret = (mText != null && mCaretPosition > 0) ?
						StringView(mText, 0, Math.Min(mCaretPosition, mText.Length)) : "";
					let caretX = bounds.X - mScrollOffset + font.MeasureString(textBeforeCaret);

					// Blink the caret (simple version - always visible when focused)
					let caretRect = RectangleF(caretX, bounds.Y + 2, 1, bounds.Height - 4);
					drawContext.FillRect(caretRect, foreground);
				}

				return;
			}
		}

		// Fallback rendering
		if (!hasText && mPlaceholder != null && mPlaceholder.Length > 0)
		{
			// Draw placeholder indicator
			let placeholderColor = Color(128, 128, 128, 128);
			drawContext.FillRect(.(bounds.X, bounds.Y + bounds.Height / 2 - 1, mPlaceholder.Length * FontSize * 0.3f, 2), placeholderColor);
		}
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		base.OnMouseDownRouted(args);

		if (args.Button == .Left && IsEnabled)
		{
			// Set caret position from click (use local coordinates directly)
			mCaretPosition = GetCharIndexAtPosition(args.LocalX);
			ClearSelection();
			Context?.CaptureMouse(this);
			mSelectionStart = mCaretPosition;
			InvalidateVisual();
			args.Handled = true;
		}
	}

	protected override void OnMouseMoveRouted(MouseEventArgs args)
	{
		base.OnMouseMoveRouted(args);

		// Extend selection while dragging
		if (Context?.CapturedElement == this && mSelectionStart >= 0)
		{
			let newPos = GetCharIndexAtPosition(args.LocalX);
			if (newPos != mCaretPosition)
			{
				mCaretPosition = newPos;
				if (mCaretPosition > mSelectionStart)
					mSelectionLength = mCaretPosition - mSelectionStart;
				else
				{
					mSelectionLength = mSelectionStart - mCaretPosition;
					mSelectionStart = mCaretPosition;
				}
				InvalidateVisual();
			}
		}
	}

	protected override void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		base.OnMouseUpRouted(args);

		if (args.Button == .Left)
		{
			Context?.ReleaseMouseCapture();
			if (mSelectionLength == 0)
				ClearSelection();
		}
	}

	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		base.OnKeyDownRouted(args);

		if (!IsEnabled)
			return;

		let ctrl = args.HasModifier(.Ctrl);
		let shift = args.HasModifier(.Shift);
		var handled = false;

		switch (args.KeyCode)
		{
		case 37: // Left
			if (ctrl)
				MoveToPreviousWord(shift);
			else
				MoveCaretLeft(shift);
			handled = true;

		case 39: // Right
			if (ctrl)
				MoveToNextWord(shift);
			else
				MoveCaretRight(shift);
			handled = true;

		case 36: // Home
			MoveToStart(shift);
			handled = true;

		case 35: // End
			MoveToEnd(shift);
			handled = true;

		case 8: // Backspace
			if (!mIsReadOnly)
			{
				if (mSelectionLength > 0)
					DeleteSelection();
				else if (mCaretPosition > 0)
				{
					mText.Remove(mCaretPosition - 1, 1);
					mCaretPosition--;
					OnTextChanged();
				}
				handled = true;
			}

		case 46: // Delete
			if (!mIsReadOnly)
			{
				if (mSelectionLength > 0)
					DeleteSelection();
				else if (mText != null && mCaretPosition < mText.Length)
				{
					mText.Remove(mCaretPosition, 1);
					OnTextChanged();
				}
				handled = true;
			}

		case 65: // A (Ctrl+A = Select All)
			if (ctrl && mText != null)
			{
				mSelectionStart = 0;
				mSelectionLength = mText.Length;
				mCaretPosition = mText.Length;
				handled = true;
			}

		case 67: // C (Ctrl+C = Copy)
			if (ctrl && mSelectionLength > 0)
			{
				CopyToClipboard();
				handled = true;
			}

		case 88: // X (Ctrl+X = Cut)
			if (ctrl && mSelectionLength > 0 && !mIsReadOnly)
			{
				CopyToClipboard();
				DeleteSelection();
				handled = true;
			}

		case 86: // V (Ctrl+V = Paste)
			if (ctrl && !mIsReadOnly)
			{
				PasteFromClipboard();
				handled = true;
			}
		}

		if (handled)
		{
			InvalidateVisual();
			args.Handled = true;
		}
	}

	protected override void OnTextInputRouted(TextInputEventArgs args)
	{
		base.OnTextInputRouted(args);

		if (!IsEnabled || mIsReadOnly)
			return;

		let c = args.Character;

		// Ignore control characters
		if ((uint32)c < 32 && c != '\t')
			return;

		// Delete selection if any
		if (mSelectionLength > 0)
			DeleteSelection();

		// Check max length
		if (mText != null && mText.Length >= mMaxLength)
			return;

		// Insert character
		if (mText == null)
			mText = new String();

		mText.Insert(mCaretPosition, c);
		mCaretPosition++;
		OnTextChanged();
		InvalidateVisual();
		args.Handled = true;
	}

	private void MoveCaretLeft(bool extend)
	{
		if (!extend && mSelectionLength > 0)
		{
			mCaretPosition = mSelectionStart;
			ClearSelection();
		}
		else if (mCaretPosition > 0)
		{
			if (extend && mSelectionStart < 0)
				mSelectionStart = mCaretPosition;

			mCaretPosition--;

			if (extend)
				UpdateSelectionFromCaret();
			else
				ClearSelection();
		}
		EnsureCaretVisible();
	}

	private void MoveCaretRight(bool extend)
	{
		let textLen = mText?.Length ?? 0;
		if (!extend && mSelectionLength > 0)
		{
			mCaretPosition = mSelectionStart + mSelectionLength;
			ClearSelection();
		}
		else if (mCaretPosition < textLen)
		{
			if (extend && mSelectionStart < 0)
				mSelectionStart = mCaretPosition;

			mCaretPosition++;

			if (extend)
				UpdateSelectionFromCaret();
			else
				ClearSelection();
		}
		EnsureCaretVisible();
	}

	private void MoveToStart(bool extend)
	{
		if (extend && mSelectionStart < 0)
			mSelectionStart = mCaretPosition;

		mCaretPosition = 0;

		if (extend)
			UpdateSelectionFromCaret();
		else
			ClearSelection();

		EnsureCaretVisible();
	}

	private void MoveToEnd(bool extend)
	{
		if (extend && mSelectionStart < 0)
			mSelectionStart = mCaretPosition;

		mCaretPosition = mText?.Length ?? 0;

		if (extend)
			UpdateSelectionFromCaret();
		else
			ClearSelection();

		EnsureCaretVisible();
	}

	private void MoveToPreviousWord(bool extend)
	{
		if (mText == null || mCaretPosition == 0)
			return;

		if (extend && mSelectionStart < 0)
			mSelectionStart = mCaretPosition;

		// Skip whitespace, then skip word characters
		var pos = mCaretPosition - 1;
		while (pos > 0 && mText[pos].IsWhiteSpace)
			pos--;
		while (pos > 0 && !mText[pos - 1].IsWhiteSpace)
			pos--;

		mCaretPosition = pos;

		if (extend)
			UpdateSelectionFromCaret();
		else
			ClearSelection();

		EnsureCaretVisible();
	}

	private void MoveToNextWord(bool extend)
	{
		if (mText == null || mCaretPosition >= mText.Length)
			return;

		if (extend && mSelectionStart < 0)
			mSelectionStart = mCaretPosition;

		// Skip word characters, then skip whitespace
		var pos = mCaretPosition;
		while (pos < mText.Length && !mText[pos].IsWhiteSpace)
			pos++;
		while (pos < mText.Length && mText[pos].IsWhiteSpace)
			pos++;

		mCaretPosition = pos;

		if (extend)
			UpdateSelectionFromCaret();
		else
			ClearSelection();

		EnsureCaretVisible();
	}

	private void UpdateSelectionFromCaret()
	{
		if (mSelectionStart < 0)
			return;

		if (mCaretPosition >= mSelectionStart)
		{
			mSelectionLength = mCaretPosition - mSelectionStart;
		}
		else
		{
			mSelectionLength = mSelectionStart - mCaretPosition;
			mSelectionStart = mCaretPosition;
		}
	}

	private void ClearSelection()
	{
		mSelectionStart = -1;
		mSelectionLength = 0;
	}

	private void DeleteSelection()
	{
		if (mSelectionStart < 0 || mSelectionLength <= 0 || mText == null)
			return;

		let start = Math.Min(mSelectionStart, mText.Length);
		let len = Math.Min(mSelectionLength, mText.Length - start);

		mText.Remove(start, len);
		mCaretPosition = start;
		ClearSelection();
		OnTextChanged();
	}

	private void CopyToClipboard()
	{
		if (mSelectionLength <= 0)
			return;

		let clipboard = Context?.Clipboard;
		if (clipboard != null)
		{
			clipboard.SetText(SelectedText);
		}
	}

	private void PasteFromClipboard()
	{
		let clipboard = Context?.Clipboard;
		if (clipboard == null)
			return;

		let pasteText = scope String();
		if (clipboard.GetText(pasteText) case .Ok)
		{
			if (mSelectionLength > 0)
				DeleteSelection();

			// Check max length
			var insertLen = pasteText.Length;
			let currentLen = mText?.Length ?? 0;
			if (currentLen + insertLen > mMaxLength)
				insertLen = mMaxLength - currentLen;

			if (insertLen > 0)
			{
				if (mText == null)
					mText = new String();

				if (insertLen < pasteText.Length)
					mText.Insert(mCaretPosition, StringView(pasteText, 0, insertLen));
				else
					mText.Insert(mCaretPosition, pasteText);

				mCaretPosition += insertLen;
				OnTextChanged();
			}
		}
	}

	private int GetCharIndexAtPosition(float x)
	{
		if (mText == null || mText.Length == 0)
			return 0;

		let bounds = ContentBounds;
		let localX = x - bounds.X + mScrollOffset;

		// Use font if available
		let cachedFont = GetCachedFont();
		if (cachedFont != null)
		{
			let font = cachedFont.Font;
			float currentX = 0;

			for (int i = 0; i < mText.Length; i++)
			{
				let charWidth = font.MeasureString(StringView(mText, i, 1));
				if (localX < currentX + charWidth / 2)
					return i;
				currentX += charWidth;
			}
			return mText.Length;
		}

		// Fallback
		let charWidth = FontSize * 0.6f;
		let index = (int)(localX / charWidth);
		return Math.Clamp(index, 0, mText.Length);
	}

	private void EnsureCaretVisible()
	{
		// Scroll to keep caret visible
		let bounds = ContentBounds;
		let cachedFont = GetCachedFont();

		float caretX = 0;
		if (cachedFont != null && mText != null && mCaretPosition > 0)
		{
			let textBeforeCaret = StringView(mText, 0, Math.Min(mCaretPosition, mText.Length));
			caretX = cachedFont.Font.MeasureString(textBeforeCaret);
		}
		else if (mText != null)
		{
			caretX = Math.Min(mCaretPosition, mText.Length) * FontSize * 0.6f;
		}

		// Scroll if caret is outside visible area
		if (caretX - mScrollOffset < 0)
			mScrollOffset = caretX;
		else if (caretX - mScrollOffset > bounds.Width - 2)
			mScrollOffset = caretX - bounds.Width + 2;

		mScrollOffset = Math.Max(0, mScrollOffset);
	}

	/// Gets the font service from the context.
	private IFontService GetFontService()
	{
		let context = Context;
		if (context != null)
		{
			if (context.GetService<IFontService>() case .Ok(let service))
				return service;
		}
		return null;
	}

	/// Gets the cached font for this control's font settings.
	private CachedFont GetCachedFont()
	{
		let fontService = GetFontService();
		if (fontService == null)
			return null;

		return fontService.GetFont(FontFamily, FontSize);
	}

	protected virtual void OnTextChanged()
	{
		mTextChangedEvent.[Friend]Invoke(this, Text);
		InvalidateMeasure();
	}
}
