# RendererLighting

Clustered forward lighting sample with cascaded shadow maps.

## Features

- LightingSystem with clustered light culling
- Cascaded shadow maps (4 cascades, 2048x2048 each)
- Multiple point lights with varied colors
- PBR-style material variation (metallic/roughness)
- Floor plane as shadow receiver
- Pillar geometry as shadow casters

## Controls

| Key | Action |
|-----|--------|
| WASD | Move camera |
| Q/E | Move down/up |
| Right-click + Drag | Look around |
| Tab | Toggle mouse capture |
| Shift | Move faster |

## Technical Details

- Clustered forward rendering with 16x9x24 cluster grid
- Shadow pass renders depth-only to cascade array
- Per-cascade VP matrix for orthographic light space
- Depth bias to prevent shadow acne
- Back-face culling in shadow pass reduces peter-panning
- Per-frame GPU buffers (double/triple buffering)

## Scene Setup

- 11x11 grid of cubes with varying metallic/roughness
- 4 corner pillars (4 cubes tall each)
- 7 point lights: Red, Green, Blue, Yellow, Magenta, Cyan, White
- 1 directional light with shadows

## Dependencies

- Sedulous.Engine.Renderer
- RHI.SampleFramework
