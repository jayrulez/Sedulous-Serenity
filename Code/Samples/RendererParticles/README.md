# RendererParticles

GPU particle system sample demonstrating a fountain effect with the Sedulous renderer.

## Features

- CPU particle simulation with GPU rendering
- Fountain effect with gravity
- Color fading over particle lifetime (yellow-orange to red)
- Size reduction over lifetime
- Instanced quad rendering
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

![RendererParticles Screenshot](screenshot.png)

## Technical Details

- `ParticleSystem` manages particle lifecycle and simulation
- Configurable emission rate, velocity range, size range, lifetime
- Per-particle: position, velocity, size, color, lifetime
- Color and size interpolation over lifetime
- Gravity applied each frame
- Particle data: Position (12) + Size (8) + Color (4) + Rotation (4) = 28 bytes
- Indexed instanced rendering (6 indices per quad)
- Alpha blending for transparency

## Particle Configuration

```beef
config.EmissionRate = 150;
config.MinVelocity = .(-1.0f, 6.0f, -1.0f);
config.MaxVelocity = .(1.0f, 10.0f, 1.0f);
config.MinSize = 0.1f;
config.MaxSize = 0.25f;
config.MinLife = 2.0f;
config.MaxLife = 3.5f;
config.Gravity = .(0, -8.0f, 0);
```

## Dependencies

- Sedulous.Engine.Renderer
- SampleFramework
