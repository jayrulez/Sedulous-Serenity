# RendererSprite

Billboard sprite rendering sample demonstrating instanced 2D sprites in 3D space.

## Features

- Billboard sprites that always face the camera
- Instanced sprite batching for efficient rendering
- Animated sprite positions (orbiting circles)
- Dynamic color cycling
- Pulsing size animation
- Dark skybox background
- First-person camera controls

## Controls

| Key | Action |
|-----|--------|
| WASD | Move camera |
| Q/E | Move down/up |
| Right-click + Drag | Look around |
| Tab | Toggle mouse capture |
| Shift | Move faster |

## Screenshot

![RendererSprite Screenshot](screenshot.png)

## Technical Details

- `SpriteRenderer` handles sprite batching and instance buffer management
- Sprites rendered as camera-facing quads using vertex shader billboard transform
- Instance data: Position (12) + Size (8) + UVRect (16) + Color (4) = 40 bytes
- Alpha blending enabled for transparency
- Depth test without write for proper transparency sorting

## Dependencies

- Sedulous.Framework.Renderer
- SampleFramework
