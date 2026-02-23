# RHIMSAA

Demonstrates multisampled anti-aliasing (MSAA) with toggle.

## Features

- 4x MSAA render target
- ResolveTexture command
- Side-by-side comparison (MSAA vs aliased)

## Controls

| Key | Action |
|-----|--------|
| Space | Toggle MSAA on/off |

## Technical Details

- MSAA texture with SampleCount = 4
- Single-sample resolve target
- ResolveTexture copies and downsamples MSAA to regular texture
- Rotating triangle shows edge quality difference

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
