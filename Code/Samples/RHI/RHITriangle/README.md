# RHITriangle

Basic RHI sample demonstrating a rotating colored triangle.

## Features

- Vertex buffer with position and color attributes
- Uniform buffer for transform matrix
- Bind groups and pipeline layout
- Basic render pipeline creation

## Technical Details

- Vertex format: Position (Float2) + Color (Float3)
- Rotation updated each frame via uniform buffer
- HLSL shaders compiled to SPIR-V

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
