# Sedulous.Drawing

A 2D drawing library that produces batched geometry for external rendering. Designed for both UI frameworks and 2D games.

## Overview

Sedulous.Drawing provides a high-level drawing API that outputs batched vertex/index data. The library handles tessellation, transforms, clipping, and batching - your renderer just needs to upload the geometry and issue draw calls.

```
DrawContext (user API)
    |
    v
DrawBatch (output: vertices, indices, commands)
    |
    v
External Renderer (GPU)
```

## Dependencies

- `Sedulous.Foundation`
- `Sedulous.Mathematics` - Vector2, Matrix, Color, RectangleF
- `Sedulous.Imaging` - Image for textures
- `Sedulous.Fonts` - Text rendering support

## Core Types

### DrawVertex

Vertex structure for all 2D geometry:

```beef
[CRepr]
public struct DrawVertex
{
    public Vector2 Position;   // Screen/world coordinates
    public Vector2 TexCoord;   // UV coordinates
    public Color Color;        // RGBA vertex color
}
```

Size: 20 bytes (8 + 8 + 4)

### DrawCommand

Represents a batch of geometry with shared render state:

```beef
public struct DrawCommand
{
    public int32 TextureIndex;   // -1 for no texture (solid color)
    public int32 StartIndex;     // Starting index in index buffer
    public int32 IndexCount;     // Number of indices to draw
    public RectangleF ClipRect;  // Scissor rectangle
    public BlendMode BlendMode;  // Blend mode
    public ClipMode ClipMode;    // None, Scissor, or Stencil
    public int32 StencilRef;     // For stencil clipping
}
```

### DrawBatch

Output container with all geometry and commands:

```beef
public class DrawBatch
{
    public List<DrawVertex> Vertices;
    public List<uint16> Indices;
    public List<DrawCommand> Commands;
    public List<ITexture> Textures;

    public Span<DrawVertex> GetVertexData();
    public Span<uint16> GetIndexData();
    public int CommandCount { get; }
    public DrawCommand GetCommand(int index);
}
```

## DrawContext API

The main drawing API. Create one instance and reuse it each frame.

### Basic Usage

```beef
let ctx = scope DrawContext();

// Set white pixel UV for solid color drawing
ctx.WhitePixelUV = .(0.5f, 0.5f);

// Draw shapes
ctx.FillRect(.(10, 10, 100, 50), Color.Red);
ctx.FillCircle(.(200, 100), 40, Color.Blue);
ctx.DrawLine(.(0, 0), .(100, 100), Color.White, 2.0f);

// Get output for rendering
let batch = ctx.GetBatch();
// Upload batch.Vertices and batch.Indices to GPU
// Issue draw calls for each command in batch.Commands

// Clear for next frame
ctx.Clear();
```

### State Management

```beef
// Push/pop state (saves transform, clip, etc.)
ctx.PushState();
ctx.Translate(100, 100);
ctx.Rotate(Math.PI_f / 4);
ctx.FillRect(.(-25, -25, 50, 50), Color.Green);
ctx.PopState();
```

### Transform Methods

```beef
ctx.SetTransform(matrix);      // Set transform directly
ctx.GetTransform();            // Get current transform
ctx.Translate(x, y);           // Apply translation
ctx.Rotate(radians);           // Apply rotation
ctx.Scale(sx, sy);             // Apply scale
ctx.ResetTransform();          // Reset to identity
```

### Filled Shapes

```beef
// Rectangles
ctx.FillRect(rect, color);
ctx.FillRect(rect, brush);

// Rounded rectangles
ctx.FillRoundedRect(rect, radius, color);
ctx.FillRoundedRect(rect, radius, brush);

// Circles
ctx.FillCircle(center, radius, color);
ctx.FillCircle(center, radius, brush);

// Ellipses
ctx.FillEllipse(center, rx, ry, color);
ctx.FillEllipse(center, rx, ry, brush);

// Arcs (pie slices)
ctx.FillArc(center, radius, startAngle, sweepAngle, color);

// Polygons
ctx.FillPolygon(points, color);
ctx.FillPolygon(points, brush);
```

### Stroked Shapes

```beef
// Lines
ctx.DrawLine(start, end, color, thickness);
ctx.DrawLine(start, end, pen);

// Rectangles
ctx.DrawRect(rect, color, thickness);
ctx.DrawRect(rect, pen);

// Circles
ctx.DrawCircle(center, radius, color, thickness);
ctx.DrawCircle(center, radius, pen);

// Ellipses
ctx.DrawEllipse(center, rx, ry, color, thickness);
ctx.DrawEllipse(center, rx, ry, pen);

// Polylines (open paths)
ctx.DrawPolyline(points, color, thickness);
ctx.DrawPolyline(points, pen);

// Polygon outlines (closed paths)
ctx.DrawPolygon(points, color, thickness);
ctx.DrawPolygon(points, pen);
```

### Images

```beef
ctx.DrawImage(texture, position);
ctx.DrawImage(texture, destRect);
ctx.DrawImage(texture, srcRect, destRect);
ctx.DrawImage(texture, destRect, tint);
```

### 9-Slice Images

For scalable UI elements like buttons and panels:

```beef
let slices = NineSlice(left: 10, top: 10, right: 10, bottom: 10);
ctx.DrawNineSlice(texture, destRect, srcRect, slices, Color.White);
```

### Sprites

```beef
// Basic sprite drawing
ctx.DrawSprite(sprite, position);
ctx.DrawSprite(sprite, position, tint);

// With transform
ctx.DrawSprite(sprite, position, rotation, scale, flip, tint);

// From animation
ctx.DrawSprite(animation, player, position);
```

### Text Rendering

Requires `Sedulous.Fonts`:

```beef
// Basic text at position
ctx.DrawText(text, fontAtlas, atlasTexture, position, color);

// Text with brush (gradients)
ctx.DrawText(text, fontAtlas, atlasTexture, position, brush);

// Aligned text within bounds
ctx.DrawText(text, font, fontAtlas, atlasTexture, bounds, TextAlignment.Center, color);

// Full alignment control
ctx.DrawText(text, font, fontAtlas, atlasTexture, bounds, hAlign, vAlign, color);
```

**Note:** The position is the baseline position. For top-left positioning, add `font.Metrics.Ascent` to Y:

```beef
let adjustedY = y + font.Metrics.Ascent;
ctx.DrawText(text, atlas, texture, .(x, adjustedY), color);
```

### Clipping

```beef
// Scissor clipping
ctx.PushClipRect(.(100, 100, 200, 150));
// Draw clipped content...
ctx.PopClip();
```

### Blend Modes

```beef
ctx.SetBlendMode(.Normal);    // Standard alpha blending
ctx.SetBlendMode(.Additive);  // Add colors
ctx.SetBlendMode(.Multiply);  // Multiply colors
ctx.SetBlendMode(.Screen);    // Screen blend
```

## Brushes

### SolidBrush

```beef
let brush = scope SolidBrush(Color.Red);
ctx.FillRect(rect, brush);
```

### LinearGradientBrush

```beef
let brush = scope LinearGradientBrush(
    startPoint: .(0, 0),
    endPoint: .(100, 0),
    startColor: Color.Red,
    endColor: Color.Blue
);
ctx.FillRect(.(0, 0, 100, 50), brush);
```

### RadialGradientBrush

```beef
let brush = scope RadialGradientBrush(
    center: .(50, 50),
    radius: 50,
    centerColor: Color.White,
    edgeColor: Color.Blue
);
ctx.FillCircle(.(50, 50), 50, brush);
```

## Pen

For stroked shapes with line cap and join styles:

```beef
let pen = scope Pen(Color.Red, thickness: 3.0f);
pen.LineCap = .Round;   // Butt, Round, Square
pen.LineJoin = .Round;  // Miter, Round, Bevel
ctx.DrawRect(rect, pen);
```

## Sprites and Animation

### Sprite

```beef
// From texture region
let sprite = Sprite(texture, .(0, 0, 32, 32));

// From entire texture
let sprite = Sprite.FromTexture(texture);

// With centered origin (for rotation)
let sprite = Sprite(texture, rect).WithCenteredOrigin();
```

### SpriteSheet

```beef
let sheet = new SpriteSheet(texture, spriteWidth: 32, spriteHeight: 32);
let sprite = sheet.GetSprite(column: 2, row: 1);
let sprite = sheet.GetSpriteByIndex(5);
```

### SpriteAnimation

```beef
let anim = new SpriteAnimation(sheet, frameIndices, frameDuration: 0.1f);
anim.Loop = true;

let player = AnimationPlayer();
player.Play();
player.Update(deltaTime);

ctx.DrawSprite(anim, player, position);
```

### SpriteFlip

```beef
ctx.DrawSprite(sprite, pos, rotation, scale, .Horizontal, tint);
// Options: None, Horizontal, Vertical, Both
```

## ITexture Interface

Wrap your GPU textures:

```beef
public interface ITexture
{
    uint32 Width { get; }
    uint32 Height { get; }
    Object Handle { get; }  // Your GPU texture reference
}

// Simple implementation provided:
let textureRef = new TextureRef(gpuTexture, width, height);
```

## Rendering the Batch

Example renderer integration:

```beef
let batch = ctx.GetBatch();

// Upload vertex/index data
UpdateBuffer(vertexBuffer, batch.Vertices);
UpdateBuffer(indexBuffer, batch.Indices);

// Render each command
for (int i = 0; i < batch.CommandCount; i++)
{
    let cmd = batch.GetCommand(i);
    let texture = batch.GetTextureForCommand(i);

    // Set render state
    SetScissorRect(cmd.ClipRect);
    SetBlendMode(cmd.BlendMode);
    BindTexture(texture?.Handle);

    // Draw
    DrawIndexed(cmd.IndexCount, cmd.StartIndex);
}
```

## Performance Tips

1. **Batch by texture** - DrawContext automatically batches geometry by texture/state
2. **Use texture atlases** - Fewer texture switches = fewer draw commands
3. **Font atlas white pixel** - The font atlas includes a white pixel for solid colors, use it for both text and shapes
4. **Reserve capacity** - Call `batch.Reserve()` if you know approximate geometry counts
5. **Double-buffer GPU resources** - Prevents flickering from write-while-read conflicts

## Sample Project

See `Code/Samples/DrawingSandbox` for a complete example demonstrating:
- All shape types
- Gradient fills
- Transform hierarchy
- Text rendering with Sedulous.Fonts
- Sprite rendering

## UI Framework Integration

Sedulous.Drawing serves as the rendering backend for Sedulous.UI. The UI framework uses DrawContext for all rendering operations.

### UIContext and DrawContext

```beef
// In your render loop
let drawContext = scope DrawContext();
drawContext.WhitePixelUV = .(u, v);

// Update and render UI
uiContext.Update(deltaTime, totalTime);
uiContext.Render(drawContext);

// Get batch for GPU rendering
let batch = drawContext.GetBatch();
```

### Custom Control Rendering

UI controls override `OnRender()` to draw themselves:

```beef
class MyButton : Control
{
    protected override void OnRender(DrawContext drawContext)
    {
        let bounds = Bounds;

        // Background based on state
        if (IsPressed)
            drawContext.FillRect(bounds, Color(180, 180, 180));
        else if (IsMouseOver)
            drawContext.FillRect(bounds, Color(225, 225, 225));
        else
            drawContext.FillRect(bounds, Color(240, 240, 240));

        // Border
        drawContext.DrawRect(bounds, Color.Gray, 1.0f);

        // Content (text, icon, etc.)
        RenderContent(drawContext);
    }
}
```

### Transform Support

UI elements can have render transforms that don't affect layout:

```beef
// UIElement applies transforms before calling OnRender
if (mHasRenderTransform)
{
    savedTransform = drawContext.GetTransform();

    // Transform around origin point
    let originX = mBounds.X + mBounds.Width * mRenderTransformOrigin.X;
    let originY = mBounds.Y + mBounds.Height * mRenderTransformOrigin.Y;

    let toOrigin = Matrix.CreateTranslation(-originX, -originY, 0);
    let fromOrigin = Matrix.CreateTranslation(originX, originY, 0);
    let combined = toOrigin * mRenderTransform * fromOrigin * savedTransform;
    drawContext.SetTransform(combined);
}

OnRender(drawContext);

if (mHasRenderTransform)
    drawContext.SetTransform(savedTransform);
```

### Opacity Stacking

The UI framework uses opacity for fade effects:

```beef
if (mOpacity < 1.0f)
    drawContext.PushOpacity(mOpacity);

OnRender(drawContext);

if (mOpacity < 1.0f)
    drawContext.PopOpacity();
```

### Debug Visualization

UIContext can render debug overlays using DrawContext:

```beef
// Layout bounds (blue outline)
if (showLayoutBounds)
    drawContext.DrawRect(element.Bounds, Color(0, 120, 215, 200), 1.0f);

// Margins (orange fill)
if (showMargins && margin.Top > 0)
    drawContext.FillRect(marginRect, Color(255, 165, 0, 80));

// Focus indicator (yellow outline)
if (showFocused && element == focusedElement)
    drawContext.DrawRect(bounds, Color(255, 255, 0, 255), 2.0f);
```

## Future Improvements

### Anti-Aliasing

The current implementation produces aliased (jagged) edges. Several approaches could be implemented for smoother rendering:

1. **MSAA (Multisample Anti-Aliasing)** - Hardware-based, enabled at render target creation. Samples multiple points per pixel along edges. Good quality with moderate performance cost.

2. **Feathered/Fringed Edges** - Expand shape outlines by 1 pixel with alpha gradient from 1.0 to 0.0. Software-based, works with any renderer. Slightly increases vertex count.

3. **Signed Distance Field (SDF)** - Store distance to edge in texture. Shader computes smooth alpha based on distance. Excellent for text and scalable shapes. Requires shader support.

4. **Analytical Coverage** - Calculate exact pixel coverage mathematically. Highest quality but computationally expensive. Best for offline rendering.

5. **Post-Process AA (FXAA, SMAA)** - Shader-based screen-space anti-aliasing applied after rendering. Fast, works with any geometry, but can blur textures.

**Recommended approach for this library:** Feathered edges for shapes (software, no shader changes) combined with SDF for text rendering (already common in font systems).

## Project Structure

```
Code/Sedulous/Sedulous.Drawing/
├── src/
│   ├── DrawContext.bf      - Main drawing API
│   ├── DrawBatch.bf        - Output container
│   ├── DrawCommand.bf      - Draw command structure
│   ├── DrawVertex.bf       - Vertex structure
│   ├── ShapeRasterizer.bf  - Tessellation
│   ├── IBrush.bf           - Brush interface
│   ├── SolidBrush.bf
│   ├── LinearGradientBrush.bf
│   ├── RadialGradientBrush.bf
│   ├── Pen.bf              - Stroke style
│   ├── LineCap.bf
│   ├── LineJoin.bf
│   ├── Sprite.bf
│   ├── SpriteSheet.bf
│   ├── SpriteAnimation.bf
│   ├── SpriteFlip.bf
│   ├── NineSlice.bf
│   ├── ITexture.bf
│   ├── BlendMode.bf
│   └── ClipMode.bf
└── BeefProj.toml
```
