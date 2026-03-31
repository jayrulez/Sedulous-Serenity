namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Fonts;
using Sedulous.Core;

/// Single-line or multiline text input control.
public class EditText : View, ITextEditHost
{
	// --- Text State ---
	private String mText = new .() ~ delete _;
	private String mHintText = new .() ~ delete _;
	private float mFontSize = 16;
	private Color mTextColor = default;
	private Color mHintColor = default;
	private bool mReadOnly = false;
	private bool mMultiline = false;
	private int32 mMaxLength = 0;

	// --- Glyph Cache ---
	private List<GlyphPosition> mGlyphPositions = new .() ~ delete _;
	private bool mGlyphsDirty = true;
	private float mTextWidth;
	private float mTextHeight;

	// --- Scroll ---
	private float mScrollOffsetX = 0;
	private float mScrollOffsetY = 0;

	// --- Cursor Blink ---
	private float mCursorBlinkResetTime = 0;

	// --- Selection dragging ---
	private bool mIsDragging = false;

	// --- Behavior ---
	protected TextEditingBehavior mBehavior ~ delete _;

	// --- Events ---
	private EventAccessor<delegate void(EditText)> mOnTextChanged = new .() ~ delete _;
	private EventAccessor<delegate void(EditText)> mOnSubmit = new .() ~ delete _;

	// ==========================================================================
	// Properties
	// ==========================================================================

	public StringView Text
	{
		get => mText;
		set
		{
			mText.Set(value);
			mGlyphsDirty = true;
			mBehavior.Reset();
			InvalidateLayout();
		}
	}

	public StringView HintText
	{
		get => mHintText;
		set { mHintText.Set(value); Invalidate(); }
	}

	public float FontSize
	{
		get => mFontSize;
		set { mFontSize = Math.Max(1, value); mGlyphsDirty = true; InvalidateLayout(); }
	}

	public Color TextColor
	{
		get => mTextColor;
		set { mTextColor = value; Invalidate(); }
	}

	public Color HintColor
	{
		get => mHintColor;
		set { mHintColor = value; Invalidate(); }
	}

	public bool ReadOnly
	{
		get => mReadOnly;
		set => mReadOnly = value;
	}

	public bool Multiline
	{
		get => mMultiline;
		set { mMultiline = value; mGlyphsDirty = true; InvalidateLayout(); }
	}

	public int32 MaxLength
	{
		get => mMaxLength;
		set => mMaxLength = value;
	}

	public InputFilter Filter
	{
		get => mBehavior.Filter;
		set => mBehavior.Filter = value;
	}

	public EventAccessor<delegate void(EditText)> OnTextChanged => mOnTextChanged;
	public EventAccessor<delegate void(EditText)> OnSubmit => mOnSubmit;

	public int32 CursorPosition => mBehavior.CursorPosition;
	public int32 SelectionStart => mBehavior.SelectionStart;
	public int32 SelectionEnd => mBehavior.SelectionEnd;

	public override float GetBaseline()
	{
		if (Context == null || Context.FontService == null)
			return -1;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null)
			return -1;

		float lineH = font.Font.Metrics.LineHeight;
		float ascent = font.Font.Metrics.Ascent;
		Context.FontService.ReleaseFont(font);

		// Match the centered text position used in OnDraw
		float contentH = MeasuredHeight - Padding.Vertical;
		float textTop = Padding.Top + (contentH - lineH) * 0.5f;
		return textTop + ascent;
	}

	// ==========================================================================
	// Constructor
	// ==========================================================================

	public this()
	{
		Focusable = true;
		CursorType = .Text;
		ClipToBounds = true;
		Padding = .(8, 6, 8, 6);
		mBehavior = new TextEditingBehavior(this);
	}

	public this(StringView hint) : this()
	{
		mHintText.Set(hint);
	}

	// ==========================================================================
	// ITextEditHost Implementation
	// ==========================================================================

	StringView ITextEditHost.Text => mText;
	int32 ITextEditHost.MaxLength => mMaxLength;
	bool ITextEditHost.IsReadOnly => mReadOnly;
	bool ITextEditHost.IsMultiline => mMultiline;
	IClipboard ITextEditHost.Clipboard => Context?.Clipboard;
	float ITextEditHost.CurrentTime => Context?.TotalTime ?? 0;

	int32 ITextEditHost.TextCharCount
	{
		get
		{
			int32 count = 0;
			for (let c in mText.DecodedChars)
				count++;
			return count;
		}
	}

	void ITextEditHost.ReplaceText(int32 charStart, int32 charLength, StringView replacement)
	{
		// Convert character indices to byte offsets
		int32 byteStart = CharToByteOffset(mText, charStart);
		int32 byteEnd = CharToByteOffset(mText, charStart + charLength);
		int32 byteLength = byteEnd - byteStart;

		mText.Remove(byteStart, byteLength);
		mText.Insert(byteStart, replacement);
		mGlyphsDirty = true;
	}

	void ITextEditHost.OnTextModified()
	{
		mGlyphsDirty = true;
		mCursorBlinkResetTime = Context?.TotalTime ?? 0;
		Invalidate();
		mOnTextChanged.[Friend]Invoke(this);
	}

	int32 ITextEditHost.HitTestPosition(float localX, float localY)
	{
		EnsureGlyphsValid();

		if (Context == null || Context.FontService == null)
			return 0;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null || font.Shaper == null)
			return 0;

		let content = ContentBounds;
		float hitX = localX - content.X + mScrollOffsetX;
		float hitY = localY - content.Y + mScrollOffsetY;

		HitTestResult result;
		if (mMultiline)
			result = font.Shaper.HitTestWrapped(font.Font, mGlyphPositions, hitX, hitY, font.Font.Metrics.LineHeight);
		else
			result = font.Shaper.HitTest(font.Font, mGlyphPositions, hitX, hitY);

		Context.FontService.ReleaseFont(font);
		return result.InsertionIndex;
	}

	float ITextEditHost.GetCursorXPosition(int32 charIndex)
	{
		EnsureGlyphsValid();

		if (Context == null || Context.FontService == null)
			return 0;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null || font.Shaper == null)
			return 0;

		let x = font.Shaper.GetCursorPosition(font.Font, mGlyphPositions, charIndex);
		Context.FontService.ReleaseFont(font);
		return x;
	}

	// ==========================================================================
	// Display text (virtual for PasswordBox)
	// ==========================================================================

	/// Get the text to display. Override in PasswordBox for masking.
	protected virtual void GetDisplayText(String outText)
	{
		outText.Set(mText);
	}

	// ==========================================================================
	// Glyph shaping
	// ==========================================================================

	private void EnsureGlyphsValid()
	{
		if (!mGlyphsDirty)
			return;

		mGlyphsDirty = false;
		mGlyphPositions.Clear();
		mTextWidth = 0;
		mTextHeight = 0;

		if (Context == null || Context.FontService == null)
			return;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null)
			return;

		let displayText = scope String();
		GetDisplayText(displayText);

		if (!displayText.IsEmpty)
		{
			if (mMultiline && font.Shaper != null)
			{
				float totalHeight = 0;
				let contentWidth = ContentBounds.Width;
				if (font.Shaper.ShapeTextWrapped(font.Font, displayText, contentWidth, mGlyphPositions, out totalHeight) case .Ok)
				{
					mTextHeight = totalHeight;
					// Compute width from glyph positions
					for (let gp in mGlyphPositions)
					{
						let right = gp.X + gp.Advance;
						if (right > mTextWidth)
							mTextWidth = right;
					}
				}
			}
			else
			{
				mTextWidth = font.Font.MeasureString(displayText, mGlyphPositions);
				mTextHeight = font.Font.Metrics.LineHeight;
			}
		}

		Context.FontService.ReleaseFont(font);
	}

	// ==========================================================================
	// Scroll management
	// ==========================================================================

	private void EnsureCursorVisible()
	{
		if (Context == null || Context.FontService == null)
			return;

		EnsureGlyphsValid();

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null || font.Shaper == null)
			return;

		let cursorX = font.Shaper.GetCursorPosition(font.Font, mGlyphPositions, mBehavior.CursorPosition);
		let contentWidth = ContentBounds.Width;

		// Scroll left if cursor is before visible area
		if (cursorX - mScrollOffsetX < 0)
			mScrollOffsetX = cursorX;
		// Scroll right if cursor is past visible area
		else if (cursorX - mScrollOffsetX > contentWidth)
			mScrollOffsetX = cursorX - contentWidth;

		// Clamp scroll offset
		let maxScroll = Math.Max(0, mTextWidth - contentWidth);
		mScrollOffsetX = Math.Clamp(mScrollOffsetX, 0, maxScroll);

		Context.FontService.ReleaseFont(font);
	}

	// ==========================================================================
	// View overrides
	// ==========================================================================

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float desiredH = Padding.Vertical;

		if (Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				desiredH += font.Font.Metrics.LineHeight;
				if (mMultiline)
					desiredH += font.Font.Metrics.LineHeight; // At least 2 lines for multiline
				Context.FontService.ReleaseFont(font);
			}
		}
		else
		{
			desiredH += mFontSize;
		}

		SetMeasuredDimension(
			widthSpec.Resolve(0, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;
		let content = ContentBounds;

		// 1. Background
		let bgDrawable = theme?.GetDrawable("EditText", "background");
		if (bgDrawable != null)
		{
			bgDrawable.Draw(ctx, .(0, 0, Width, Height), GetControlState());
		}
		else
		{
			let bgColor = theme?.GetColor("EditText", "background") ?? .(0.12f, 0.12f, 0.15f, 1.0f);
			let cornerRadius = theme?.GetDimension("EditText", "cornerRadius") ?? 4;
			ctx.FillRoundedRect(.(0, 0, Width, Height), cornerRadius, bgColor);
		}

		// 2. Border
		if (bgDrawable == null)
		{
			let borderColor = IsFocused
				? (theme?.GetColor("EditText", "focusBorder") ?? palette.Accent)
				: (theme?.GetColor("EditText", "border") ?? palette.Border);
			let cornerRadius = theme?.GetDimension("EditText", "cornerRadius") ?? 4;
			let borderWidth = IsFocused ? 2.0f : 1.0f;
			ctx.DrawBorderRoundedRect(.(0, 0, Width, Height), cornerRadius, borderColor, borderWidth);
		}
		else if (IsFocused)
		{
			let cornerRadius = theme?.GetDimension("EditText", "cornerRadius") ?? 4;
			DrawFocusIndicator(ctx, .(0, 0, Width, Height), cornerRadius);
		}

		// 3. Ensure glyphs are valid
		EnsureGlyphsValid();

		if (Context == null || Context.FontService == null)
			return;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null)
			return;

		let atlasTexture = Context.FontService.GetAtlasTexture(font);
		if (atlasTexture == null)
		{
			Context.FontService.ReleaseFont(font);
			return;
		}

		// 4. Clip to content area
		ctx.PushClipRect(content);

		float textOffsetX = content.X - mScrollOffsetX;
		float textOffsetY = content.Y + (content.Height - font.Font.Metrics.LineHeight) * 0.5f - mScrollOffsetY;

		if (mText.IsEmpty && !IsFocused && !mHintText.IsEmpty)
		{
			// 5. Draw hint text
			let hintColor = (mHintColor.A > 0) ? mHintColor
				: (theme?.GetColor("EditText", "hint") ?? Palette.Desaturate(palette.Text, 0.5f));
			ctx.DrawText(mHintText, font.Font, font.Atlas, atlasTexture, content, .Left, .Middle, hintColor);
		}
		else
		{
			// 6. Draw selection highlight (if focused and has selection)
			if (IsFocused && mBehavior.IsSelecting && font.Shaper != null)
			{
				let selColor = theme?.GetColor("EditText", "selection") ?? .(0.3f, 0.5f, 0.9f, 0.4f);
				let selRange = SelectionRange.FromAnchorActive(mBehavior.AnchorPosition, mBehavior.CursorPosition);
				let rects = scope List<Sedulous.Fonts.Rect>();
				font.Shaper.GetSelectionRects(font.Font, mGlyphPositions, selRange, font.Font.Metrics.LineHeight, rects);
				for (let r in rects)
				{
					ctx.FillRect(.(textOffsetX + r.X, textOffsetY + r.Y, r.Width, r.Height), selColor);
				}
			}

			// 7. Draw text glyphs
			if (mGlyphPositions.Count > 0)
			{
				let textColor = (mTextColor.A > 0) ? mTextColor : GetStateForeground();
				ctx.DrawPositionedGlyphs(mGlyphPositions, font.Atlas, atlasTexture, textOffsetX, textOffsetY + font.Font.Metrics.Ascent, textColor);
			}
		}

		// 8. Draw cursor (blinking)
		if (IsFocused && font.Shaper != null)
		{
			float elapsed = (Context?.TotalTime ?? 0) - mCursorBlinkResetTime;
			bool cursorVisible = ((int)(elapsed / 0.5f) % 2) == 0;
			if (cursorVisible)
			{
				float cursorX = font.Shaper.GetCursorPosition(font.Font, mGlyphPositions, mBehavior.CursorPosition);
				let cursorColor = theme?.GetColor("EditText", "cursor") ?? palette.Text;
				ctx.FillRect(.(textOffsetX + cursorX - 1, textOffsetY, 2, font.Font.Metrics.LineHeight), cursorColor);
			}
		}

		ctx.PopClip();
		Context.FontService.ReleaseFont(font);
	}

	// ==========================================================================
	// Input handlers
	// ==========================================================================

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		e.Handled = true;
		mIsDragging = true;
		Context?.FocusManager.SetCapture(this);

		mBehavior.HandleMouseDown(e.LocalX, e.LocalY, (int32)e.ClickCount, e.Modifiers);
		ResetBlink();
		EnsureCursorVisible();
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		if (mIsDragging)
		{
			mBehavior.HandleMouseMove(e.LocalX, e.LocalY);
			ResetBlink();
			EnsureCursorVisible();
		}
	}

	public override void OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return;

		if (mIsDragging)
		{
			mIsDragging = false;
			Context?.FocusManager.ReleaseCapture();
			e.Handled = true;
		}
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled)
			return;

		// Handle Enter/Return for single-line submit
		if (e.Key == .Return && !mMultiline)
		{
			mOnSubmit.[Friend]Invoke(this);
			e.Handled = true;
			return;
		}

		mBehavior.HandleKeyDown(e.Key, e.Modifiers);
		ResetBlink();
		EnsureCursorVisible();
		e.Handled = true;
	}

	public override void OnTextInput(TextInputEventArgs e)
	{
		if (!Enabled)
			return;

		mBehavior.HandleTextInput(e.Character);
		ResetBlink();
		EnsureCursorVisible();
		e.Handled = true;
	}

	public override void OnFocusGained(FocusEventArgs e)
	{
		ResetBlink();
		Invalidate();
	}

	public override void OnFocusLost(FocusEventArgs e)
	{
		mIsDragging = false;
		Invalidate();
	}

	// ==========================================================================
	// Helpers
	// ==========================================================================

	private void ResetBlink()
	{
		mCursorBlinkResetTime = Context?.TotalTime ?? 0;
	}

	/// Convert a character index to a byte offset in a UTF-8 string.
	private static int32 CharToByteOffset(StringView text, int32 charIndex)
	{
		int32 charCount = 0;
		int32 byteOffset = 0;

		for (let c in text.DecodedChars)
		{
			if (charCount >= charIndex)
				break;
			charCount++;
			byteOffset = (int32)@c.NextIndex;
		}

		if (charCount < charIndex)
			return (int32)text.Length;

		return byteOffset;
	}
}
