# RendererTriangle

Basic Framework.Renderer sample demonstrating the RenderGraph system.

## Features

- RenderGraph for automatic resource management
- Forward pass setup via builder pattern
- Imported swapchain texture handling
- Lambda-based render pass execution

## Technical Details

- Rotating colored triangle
- RenderGraph compiles and executes passes automatically
- Pass execution via closure capturing GPU resources
- Minimal manual resource barriers

## Dependencies

- Sedulous.Framework.Renderer
- RHI.SampleFramework
