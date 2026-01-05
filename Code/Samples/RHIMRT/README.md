# RHIMRT

Demonstrates multiple render targets (MRT) for deferred rendering.

## Features

- G-buffer with 3 color attachments (Albedo, Normal, Position)
- Deferred lighting pass
- Display mode switching for debugging

## Controls

| Key | Action |
|-----|--------|
| 1 | Lit output (with lighting) |
| 2 | Albedo only |
| 3 | Normals |
| 4 | World position |

## Technical Details

- Albedo: RGBA8Unorm
- Normal: RGBA16Float (for precision)
- Position: RGBA32Float (world coordinates)
- Fullscreen triangle composite pass
- Texture barriers between passes

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
