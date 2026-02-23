# RHIBlit

Demonstrates the Blit command for texture scaling.

## Features

- Render to small texture (64x64)
- Blit to larger texture (256x256) with scaling
- Side-by-side comparison

## Technical Details

- Source: 64x64 render target with rotating triangle
- Destination: 256x256 texture
- Blit() performs copy with automatic format conversion and filtering
- Left side shows original, right side shows scaled result

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
