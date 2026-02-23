# RHIReadback

Demonstrates buffer and texture readback from GPU to CPU.

## Features

- ReadBuffer for vertex data verification
- ReadTexture for pixel data verification
- Data integrity validation

## Controls

| Key | Action |
|-----|--------|
| R | Read back vertex buffer and verify |
| T | Read back texture and verify |

## Technical Details

- Vertex buffer created with CopySrc flag for readback
- 4x4 RGBA texture with quadrant colors (Red, Green, Blue, White)
- Compares readback data against original upload data
- Reports match/mismatch for each element

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
