# Sedulous Font Library

The Sedulous font library provides text rendering capabilities for games and UI frameworks, built on stb_truetype for TrueType font support.

## Architecture

The font system is split into two projects:

- **Sedulous.Fonts** - Core interfaces and types (font-format agnostic)
- **Sedulous.Fonts.TTF** - TrueType implementation using stb_truetype

## Quick Start

```beef
// Initialize TrueType support
TrueTypeFonts.Initialize();
defer TrueTypeFonts.Shutdown();

// Load a font
FontLoadOptions options = .Default;
options.PixelHeight = 32;

if (FontLoaderFactory.LoadFont("path/to/font.ttf", options) case .Ok(let font))
{
    defer delete (Object)font;

    // Measure text
    float width = font.MeasureString("Hello World");

    // Create atlas for rendering
    if (FontLoaderFactory.CreateAtlas(font, options) case .Ok(let atlas))
    {
        defer delete (Object)atlas;
        // Use atlas for GPU rendering...
    }
}
```

## Core Types

### IFont

The main font interface providing metrics and glyph information.

```beef
public interface IFont
{
    float PixelHeight { get; }
    FontMetrics Metrics { get; }

    GlyphInfo GetGlyphInfo(int32 codepoint);
    float GetKerning(int32 first, int32 second);
    float MeasureString(StringView text);
    bool HasGlyph(int32 codepoint);
}
```

### FontMetrics

Contains font-level measurements:

| Property | Description |
|----------|-------------|
| `Ascent` | Distance from baseline to top of tallest glyph (positive) |
| `Descent` | Distance from baseline to bottom of lowest glyph (negative) |
| `LineGap` | Extra spacing between lines |
| `LineHeight` | Total line height (Ascent - Descent + LineGap) |
| `Decorations` | Underline/strikethrough positioning metrics |

### GlyphInfo

Information about a specific character:

| Property | Description |
|----------|-------------|
| `Codepoint` | Unicode codepoint |
| `AdvanceWidth` | Horizontal distance to next character |
| `LeftSideBearing` | Offset from cursor to left edge of glyph |
| `BoundingBox` | Glyph bounding rectangle |

## Font Loading Options

Configure font loading with `FontLoadOptions`:

```beef
FontLoadOptions options = .Default;
options.PixelHeight = 24;        // Font size in pixels
options.AtlasWidth = 512;        // Atlas texture width
options.AtlasHeight = 512;       // Atlas texture height
options.FirstCodepoint = 32;     // First character (space)
options.LastCodepoint = 126;     // Last character (~)
options.OversampleX = 2;         // Horizontal oversampling
options.OversampleY = 2;         // Vertical oversampling
options.Padding = 1;             // Glyph padding in atlas
```

Predefined configurations:
- `.Default` - 32px, ASCII range (32-126)
- `.Small` - 16px, ASCII range
- `.Large` - 48px, ASCII range
- `.ExtendedLatin` - 32px, extended Latin (32-255)

## Font Atlas

The atlas packs rendered glyphs into a texture for GPU rendering.

### IFontAtlas

```beef
public interface IFontAtlas
{
    uint32 Width { get; }
    uint32 Height { get; }
    Span<uint8> PixelData { get; }
    (float U, float V) WhitePixelUV { get; }

    bool GetGlyphQuad(int32 codepoint, ref float cursorX, float cursorY, out GlyphQuad quad);
    bool TryGetRegion(int32 codepoint, out AtlasRegion region);
}
```

### Rendering Text

```beef
float cursorX = 100;
float cursorY = 200 + font.Metrics.Ascent; // Y is baseline position

for (let char in text.DecodedChars)
{
    GlyphQuad quad = .();
    if (atlas.GetGlyphQuad((int32)char, ref cursorX, cursorY, out quad))
    {
        // quad contains screen coordinates (X0,Y0,X1,Y1)
        // and UV coordinates (U0,V0,U1,V1)
        DrawQuad(quad);
    }
}
```

### White Pixel for Solid Drawing

The atlas includes a white pixel for drawing solid geometry (lines, rectangles):

```beef
let (u, v) = atlas.WhitePixelUV;
// Use these UVs for underlines, selection rectangles, etc.
```

## Text Shaping

The `ITextShaper` interface handles text layout with proper character positioning.

### Basic Shaping

```beef
let shaper = scope TrueTypeTextShaper();
let positions = scope List<GlyphPosition>();

// Shape text starting at position (100, 50)
shaper.ShapeText(font, "Hello World", 100, 50, positions);

// Each GlyphPosition contains:
// - Index: character index in string
// - Codepoint: Unicode codepoint
// - X, Y: position for rendering
// - Advance: width of character
// - GlyphInfo: detailed glyph metrics
```

### Word Wrapping

```beef
float totalHeight;
shaper.ShapeTextWrapped(font, longText, maxWidth, positions, out totalHeight);

// Positions now contain line-broken text
// totalHeight is the total height of all lines
```

## UI Framework Support

The font library includes features for building text input controls.

### Hit Testing

Convert mouse coordinates to character positions:

```beef
// Single line hit test
let result = shaper.HitTest(font, positions, mouseX, mouseY);

// result.CharacterIndex - which character was hit
// result.IsTrailingHit - click was on trailing half of character
// result.IsInside - click was within text bounds
// result.InsertionIndex - cursor position for insertion

// Multi-line hit test
let result = shaper.HitTestWrapped(font, positions, mouseX, mouseY, lineHeight);
// Also includes result.LineIndex
```

### Cursor Positioning

Get X coordinate for cursor at a character index:

```beef
float cursorX = shaper.GetCursorPosition(font, positions, characterIndex);
```

### Selection Rectangles

Get rectangles for highlighting selected text:

```beef
let selection = SelectionRange(startIndex, endIndex);
let rects = scope List<Rect>();

shaper.GetSelectionRects(font, positions, selection, lineHeight, rects);

// rects contains one Rect per line of selection
for (let rect in rects)
{
    DrawSelectionHighlight(rect.X, rect.Y, rect.Width, rect.Height);
}
```

### SelectionRange

Represents a text selection:

```beef
var range = SelectionRange(2, 8);  // Select characters 2-7
range.Start;    // Normalized start (always <= End)
range.End;      // Normalized end (exclusive)
range.Length;   // Number of characters selected
range.IsEmpty;  // True if Start == End
range.Contains(5);  // True if index is in selection
```

### HitTestResult

Result from hit testing:

```beef
struct HitTestResult
{
    int32 CharacterIndex;  // Character that was hit
    bool IsTrailingHit;    // Hit trailing edge of character
    bool IsInside;         // Click was inside text bounds
    int32 LineIndex;       // Line number (for wrapped text)

    int32 InsertionIndex { get; }  // Where to place cursor
}
```

## Text Decorations

Support for underline and strikethrough:

```beef
let decorations = font.Metrics.Decorations;

// Underline position (positive = below baseline)
float underlineY = baseline + decorations.UnderlinePosition;
float underlineThickness = decorations.UnderlineThickness;

// Strikethrough position (negative = above baseline)
float strikeY = baseline + decorations.StrikethroughPosition;
float strikeThickness = decorations.StrikethroughThickness;
```

## Font Manager

Thread-safe font caching for applications using multiple font sizes:

```beef
let fontManager = scope FontManager(.Default);

// Optional: provide a shaper factory
fontManager.SetShaperFactory(new () => new TrueTypeTextShaper());

// Get or load font (cached by path + size)
let cached = fontManager.GetFont("fonts/arial.ttf", 24);
if (cached != null)
{
    // Use cached.Font, cached.Atlas, cached.Shaper

    // Release when done (font stays in cache)
    fontManager.ReleaseFont(cached);
}

// Clear unused fonts (RefCount == 0)
fontManager.ClearUnused();

// Clear all fonts
fontManager.ClearAll();
```

### CachedFont

Contains loaded font resources:

```beef
class CachedFont
{
    IFont Font;
    IFontAtlas Atlas;
    ITextShaper Shaper;  // May be null if no factory set
    int32 RefCount;
}
```

## Complete Rendering Example

```beef
class TextRenderer
{
    private IFont mFont;
    private IFontAtlas mAtlas;
    private TrueTypeTextShaper mShaper = new .() ~ delete _;
    private List<GlyphPosition> mPositions = new .() ~ delete _;

    public void DrawText(StringView text, float x, float y, Color color)
    {
        float cursorX = x;
        float cursorY = y + mFont.Metrics.Ascent;

        for (let char in text.DecodedChars)
        {
            GlyphQuad quad = .();
            if (mAtlas.GetGlyphQuad((int32)char, ref cursorX, cursorY, out quad))
            {
                EmitQuad(quad, color);
            }
        }
    }

    public void DrawTextWithUnderline(StringView text, float x, float y, Color color)
    {
        DrawText(text, x, y, color);

        let decorations = mFont.Metrics.Decorations;
        float textWidth = mFont.MeasureString(text);
        float baseline = y + mFont.Metrics.Ascent;
        float underlineY = baseline + decorations.UnderlinePosition;

        DrawLine(x, underlineY, textWidth, decorations.UnderlineThickness, color);
    }

    public void DrawWrappedText(StringView text, float x, float y, float maxWidth, Color color)
    {
        float totalHeight;
        mShaper.ShapeTextWrapped(mFont, text, maxWidth, mPositions, out totalHeight);

        float yOffset = y + mFont.Metrics.Ascent;

        for (let pos in mPositions)
        {
            if (pos.Codepoint == ' ')
                continue;

            float cursorX = x + pos.X;
            float cursorY = yOffset + pos.Y;

            GlyphQuad quad = .();
            if (mAtlas.GetGlyphQuad(pos.Codepoint, ref cursorX, cursorY, out quad))
            {
                EmitQuad(quad, color);
            }
        }
    }
}
```

## Performance Tips

1. **Reuse position lists** - Allocate `List<GlyphPosition>` once and reuse
2. **Cache shaped text** - Don't re-shape static text every frame
3. **Use FontManager** - Avoid loading the same font multiple times
4. **Appropriate atlas size** - Larger atlases reduce texture switches but use more memory
5. **Batch rendering** - Collect all quads before submitting to GPU
