# RHIMipmaps

Demonstrates mipmap levels and GPU mipmap generation.

## Features

- 8 mipmap levels (256 down to 2)
- Manual colored mips for visualization
- GPU-generated mipmaps via GenerateMipmaps()
- Trilinear filtering

## Controls

| Key | Action |
|-----|--------|
| Up/Down | Move quad closer/further (changes mip level) |
| M | Toggle between manual colored mips and GPU-generated mips |

## Technical Details

- Manual mode: Each mip level has distinct color (Red, Orange, Yellow, Green, Cyan, Blue, Magenta, White)
- Generated mode: GPU downsamples from level 0 checkerboard
- Large tiled quad to make mip transitions visible

## Dependencies

- Sedulous.RHI
- Sedulous.Imaging
- RHI.SampleFramework
