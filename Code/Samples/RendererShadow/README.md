# RendererShadow

Shadow mapping development sample with debug visualization.

## Features

- 4-cascade shadow maps
- Debug frustum visualization
- Per-cascade uniform buffers
- Per-frame resource management
- Shadow depth pass with instancing

## Controls

| Key | Action |
|-----|--------|
| WASD | Move camera |
| Q/E | Move down/up |
| Right-click + Drag | Look around |
| Tab | Toggle mouse capture |
| Shift | Move faster |

## Technical Details

- Per-frame resources struct avoids GPU/CPU sync issues
- One shadow uniform buffer per cascade per frame
- Debug line rendering for cascade frustums
- Depth-only shadow pass (Fragment = null)
- Depth bias via pipeline state

## Dependencies

- Sedulous.Engine.Renderer
- RHI.SampleFramework
