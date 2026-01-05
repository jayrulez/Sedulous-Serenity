# RHIBlending

Demonstrates alpha blending with overlapping transparent quads.

## Features

- Alpha blending pipeline state
- Multiple transparent quads with varying opacity
- Back-to-front rendering order

## Technical Details

- Standard alpha blend: `result = src.rgb * src.a + dst.rgb * (1 - src.a)`
- Three overlapping quads: Red (70%), Green (50%), Blue (60%) opacity
- Vertex format: Position (Float2) + Color (Float4 with alpha)

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
