# RHIBorderSampler

Demonstrates sampler border colors with ClampToBorder address mode.

## Features

- Three border color modes
- Extended UV coordinates beyond 0-1 range
- Alpha blending to show transparency

## Controls

| Key | Action |
|-----|--------|
| 1 | TransparentBlack border (shows background) |
| 2 | OpaqueBlack border |
| 3 | OpaqueWhite border |

## Technical Details

- AddressMode.ClampToBorder samples border color outside UV range
- UV range: -0.5 to 1.5 (extends beyond texture)
- 8x8 checkerboard texture in center
- Border fills surrounding area

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
