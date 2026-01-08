# Sedulous.RHI

A modern graphics API abstraction layer inspired by WebGPU/wgpu. Provides a clean, portable interface for GPU programming with a Vulkan backend.

## Overview

```
Sedulous.RHI                    - Core interfaces and descriptors
Sedulous.RHI.Vulkan             - Vulkan backend implementation
Sedulous.RHI.HLSLShaderCompiler - HLSL to SPIR-V compilation via DXC
SampleFramework                 - Base class for RHI samples
```

## Core Types

### Device Management

| Type | Purpose |
|------|---------|
| `IBackend` | Rendering backend (e.g., VulkanBackend). Enumerates adapters, creates surfaces. |
| `IAdapter` | Physical GPU. Selected from backend enumeration, creates logical devices. |
| `IDevice` | Logical GPU device. Creates all resources, manages synchronization. |
| `IQueue` | Command submission. Has `Submit()`, `WriteBuffer()`, `WriteTexture()`. |

### Presentation

| Type | Purpose |
|------|---------|
| `ISurface` | Platform-specific rendering target (window handle). |
| `ISwapChain` | Display presentation. Properties: `CurrentTexture`, `CurrentTextureView`, `CurrentFrameIndex`. Methods: `AcquireNextImage()`, `Present()`, `Resize()`. |

### Resources

| Type | Purpose |
|------|---------|
| `IBuffer` | GPU memory buffer. Usage: Vertex, Index, Uniform, Storage, Copy, Indirect, MapRead, MapWrite. |
| `ITexture` | GPU texture. Dimensions: 1D, 2D, 3D. Usage: Sampled, Storage, RenderTarget, DepthStencil, Copy. |
| `ITextureView` | View into texture (subset, format reinterpretation). |
| `ISampler` | Texture sampling config. Filter modes, address modes, anisotropy, comparison. |

### Shaders & Pipelines

| Type | Purpose |
|------|---------|
| `IShaderModule` | Compiled shader bytecode (SPIR-V for Vulkan). |
| `IRenderPipeline` | Graphics pipeline state. Vertex/fragment stages, primitives, depth, blending. |
| `IComputePipeline` | Compute shader pipeline. |
| `IPipelineLayout` | Collection of bind group layouts defining shader resource structure. |

### Resource Binding

| Type | Purpose |
|------|---------|
| `IBindGroupLayout` | Defines resource binding structure (types, visibility, binding indices). |
| `IBindGroup` | Concrete resource bindings matching a layout. |

### Commands

| Type | Purpose |
|------|---------|
| `ICommandEncoder` | Records GPU commands. Creates render/compute passes, copy operations. |
| `IRenderPassEncoder` | Records render commands. Pipeline, bindings, draw calls. |
| `IComputePassEncoder` | Records compute shader dispatches. |
| `ICommandBuffer` | Immutable recorded commands. Submitted to queue. |

### Synchronization

| Type | Purpose |
|------|---------|
| `IFence` | GPU synchronization primitive. |
| `IQuerySet` | GPU query results (timestamps, occlusion, pipeline stats). |

## Initialization Flow

```
1. Create Backend (VulkanBackend)
       ↓
2. Create Window & Surface
       ↓
3. Enumerate & Select Adapter
       ↓
4. Create Device from Adapter
       ↓
5. Create SwapChain for Presentation
       ↓
6. Create Resources (buffers, textures, samplers)
       ↓
7. Load & Compile Shaders
       ↓
8. Create Bind Group Layouts & Bind Groups
       ↓
9. Create Pipeline Layout & Render Pipeline
       ↓
10. Enter Render Loop
```

## Frame Lifecycle

The RHISampleApp provides a structured frame lifecycle:

```
Main Loop:
  ProcessEvents()          - Window/input events
  OnInput()                - Input handling (no GPU access)
  OnUpdate(dt, total)      - Game logic (no buffer writes!)

  Frame():
    AcquireNextImage()     - FENCE WAIT - waits for GPU
    OnPrepareFrame(frameIndex)  - SAFE to write per-frame buffers
    OnRenderFrame(encoder, frameIndex)  - Record render commands
      OR OnRender(renderPass)           - Use default render pass
    Submit(commandBuffer)
    Present()
```

**Critical Rule:** Write per-frame buffers in `OnPrepareFrame()`, NOT in `OnUpdate()`. The fence wait in `AcquireNextImage()` ensures the GPU is done with that frame slot.

## Render Pass Structure

```beef
// Begin render pass
RenderPassColorAttachment[1] colorAttachments = .(.(textureView)
{
    LoadOp = .Clear,
    StoreOp = .Store,
    ClearValue = .(0.1f, 0.1f, 0.1f, 1.0f)
});
RenderPassDescriptor passDesc = .(colorAttachments);

let renderPass = encoder.BeginRenderPass(&passDesc);

// Issue draw commands
renderPass.SetPipeline(pipeline);
renderPass.SetBindGroup(0, bindGroup);
renderPass.SetVertexBuffer(0, vertexBuffer, 0);
renderPass.SetIndexBuffer(indexBuffer, .UInt16, 0);
renderPass.SetViewport(0, 0, width, height, 0, 1);
renderPass.SetScissorRect(0, 0, width, height);
renderPass.DrawIndexed(indexCount, 1, 0, 0, 0);

renderPass.End();
delete renderPass;

// Finish and submit
let commandBuffer = encoder.Finish();
Device.Queue.Submit(commandBuffer, swapChain);
```

## Shader Bindings

The RHI automatically applies Vulkan binding shifts. Use **HLSL register numbers** directly:

```hlsl
// HLSL shader
cbuffer Uniforms : register(b0) { float4x4 transform; }
Texture2D tex : register(t0);
SamplerState samp : register(s0);
```

```beef
// Beef bind group layout - use same indices as HLSL registers
BindGroupLayoutEntry[3] layoutEntries = .(
    BindGroupLayoutEntry.UniformBuffer(0, .Vertex),    // b0
    BindGroupLayoutEntry.SampledTexture(0, .Fragment), // t0
    BindGroupLayoutEntry.Sampler(0, .Fragment)         // s0
);
```

**Internal Vulkan shifts (applied automatically):**
- Constant buffers (b): +0
- Textures (t): +1000
- UAV/Storage (u): +2000
- Samplers (s): +3000

## Descriptors Reference

### BufferDescriptor

```beef
BufferDescriptor desc = .()
{
    Size = 1024,                    // Size in bytes
    Usage = .Vertex | .CopySrc,     // Usage flags
    MemoryAccess = .Upload,         // GpuOnly, Upload, or Readback
    Label = "My Buffer"             // Debug name
};
```

**Common patterns:**
- Vertex buffer: `Usage = .Vertex, MemoryAccess = .Upload`
- Index buffer: `Usage = .Index, MemoryAccess = .Upload`
- Uniform buffer: `Usage = .Uniform, MemoryAccess = .Upload`
- Storage buffer: `Usage = .Storage, MemoryAccess = .GpuOnly`

### TextureDescriptor

```beef
// Use factory method for common cases
TextureDescriptor desc = TextureDescriptor.Texture2D(
    width, height,
    .RGBA8Unorm,
    .Sampled | .CopyDst
);

// Or manual configuration
TextureDescriptor desc = .()
{
    Dimension = .Texture2D,
    Format = .RGBA8Unorm,
    Width = 512,
    Height = 512,
    Depth = 1,
    MipLevelCount = 1,
    ArrayLayerCount = 1,
    SampleCount = 1,
    Usage = .Sampled | .RenderTarget
};
```

**Common formats:**
- Display: `BGRA8Unorm`, `BGRA8UnormSrgb`
- Colors: `RGBA8Unorm`, `RGBA8UnormSrgb`, `RGBA16Float`, `RGBA32Float`
- Depth: `Depth24PlusStencil8`, `Depth32Float`
- Compressed: `BC1` (DXT1), `BC3` (DXT5), `BC7` (BPTC)

### SamplerDescriptor

```beef
SamplerDescriptor desc = .()
{
    MinFilter = .Linear,
    MagFilter = .Linear,
    MipmapFilter = .Linear,
    AddressModeU = .Repeat,
    AddressModeV = .Repeat,
    AddressModeW = .Repeat,
    MaxAnisotropy = 1
};
```

### BindGroupLayoutEntry

```beef
// Factory methods for common binding types
BindGroupLayoutEntry.UniformBuffer(binding, visibility, dynamicOffset)
BindGroupLayoutEntry.StorageBuffer(binding, visibility, dynamicOffset)
BindGroupLayoutEntry.SampledTexture(binding, visibility, dimension)
BindGroupLayoutEntry.StorageTexture(binding, visibility, format)
BindGroupLayoutEntry.Sampler(binding, visibility)
```

### BindGroupEntry

```beef
// Factory methods for binding resources
BindGroupEntry.Buffer(binding, buffer, offset, size)
BindGroupEntry.Texture(binding, textureView)
BindGroupEntry.Sampler(binding, sampler)
```

### RenderPipelineDescriptor

```beef
// Vertex attributes
VertexAttribute[2] vertexAttrs = .(
    .(VertexFormat.Float2, 0, 0),   // Position at offset 0, location 0
    .(VertexFormat.Float3, 8, 1)    // Color at offset 8, location 1
);
VertexBufferLayout[1] vertexBuffers = .(
    .((uint64)sizeof(Vertex), vertexAttrs)
);

// Color targets
ColorTargetState[1] colorTargets = .(
    .(SwapChain.Format, .AlphaBlend)  // Format + optional blend state
);

// Pipeline descriptor
RenderPipelineDescriptor desc = .()
{
    Layout = pipelineLayout,
    Vertex = .()
    {
        Shader = .(vertShader, "main"),
        Buffers = vertexBuffers
    },
    Fragment = .()
    {
        Shader = .(fragShader, "main"),
        Targets = colorTargets
    },
    Primitive = .()
    {
        Topology = .TriangleList,
        FrontFace = .CCW,
        CullMode = .Back
    },
    DepthStencil = null,  // Optional depth state
    Multisample = .()
    {
        Count = 1,
        Mask = uint32.MaxValue
    }
};
```

## Shader Compilation

### Loading Shader Pairs

```beef
// Loads quad.vert.hlsl and quad.frag.hlsl
let result = ShaderUtils.LoadShaderPair(Device, "shaders/quad");
if (result case .Ok(let shaders))
{
    (mVertShader, mFragShader) = shaders;
}
```

### Inline Compilation

```beef
String vertSrc = """
    struct VSOutput { float4 position : SV_Position; };
    VSOutput main(float2 pos : POSITION) {
        VSOutput o;
        o.position = float4(pos, 0, 1);
        return o;
    }
    """;

if (ShaderUtils.CompileShader(Device, vertSrc, "main", .Vertex) case .Ok(let shader))
{
    mVertShader = shader;
}
```

### HLSL Shader Structure

```hlsl
// Vertex shader
cbuffer Transform : register(b0) {
    float4x4 mvp;
};

struct VS_INPUT {
    float3 position : POSITION;
    float2 texCoord : TEXCOORD0;
};

struct VS_OUTPUT {
    float4 position : SV_POSITION;
    float2 texCoord : TEXCOORD0;
};

VS_OUTPUT main(VS_INPUT input) {
    VS_OUTPUT output;
    output.position = mul(float4(input.position, 1.0), mvp);
    output.texCoord = input.texCoord;
    return output;
}

// Fragment shader
Texture2D albedoTex : register(t0);
SamplerState albedoSampler : register(s0);

float4 main(float2 texCoord : TEXCOORD0) : SV_TARGET {
    return albedoTex.Sample(albedoSampler, texCoord);
}
```

## Matrix Convention

Beef uses **row-vector** convention:

```beef
// Vector * Matrix multiplication
// Reads left-to-right: Model → View → Projection
Matrix mvp = model * view * projection;

// Transform composition: Scale → Rotate → Translate
Matrix world = scale * rotation * translation;
```

HLSL's `mul(matrix, vector)` with cbuffer matrices works correctly because the implicit transpose aligns the conventions.

## Double Buffering

With 2 frames in flight, per-frame buffers prevent GPU read/CPU write conflicts:

```beef
// Per-frame uniform buffers
private IBuffer[MAX_FRAMES_IN_FLIGHT] mUniformBuffers;
private IBindGroup[MAX_FRAMES_IN_FLIGHT] mBindGroups;

protected override void OnPrepareFrame(int32 frameIndex)
{
    // Write to this frame's buffer - GPU is done with it
    Device.Queue.WriteBuffer(mUniformBuffers[frameIndex], 0, data);
}

protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
{
    // Use this frame's bind group
    renderPass.SetBindGroup(0, mBindGroups[frameIndex]);
    return true;
}
```

**When single buffers are fine:**
- Static geometry (vertex/index buffers that don't change)
- Textures (immutable after upload)
- Buffers written once during initialization

## Depth Buffer Setup

```beef
// Create depth texture
TextureDescriptor depthDesc = TextureDescriptor.Texture2D(
    width, height,
    .Depth24PlusStencil8,
    .DepthStencil
);
Device.CreateTexture(&depthDesc) => mDepthTexture;

// Create view
TextureViewDescriptor viewDesc = .() { Format = .Depth24PlusStencil8 };
Device.CreateTextureView(mDepthTexture, &viewDesc) => mDepthView;

// Use in render pass
RenderPassDepthStencilAttachment depthAttach = .()
{
    View = mDepthView,
    DepthLoadOp = .Clear,
    DepthStoreOp = .Store,
    DepthClearValue = 1.0f  // Use 0.0f for reverse-Z
};
```

**Reverse-Z depth** (recommended for better precision):
- Clear to 0.0f (far plane)
- Near plane = 1.0f
- Use `DepthCompare = .Greater`

## Texture Upload

```beef
// Create texture
TextureDescriptor desc = TextureDescriptor.Texture2D(
    width, height, .RGBA8Unorm, .Sampled | .CopyDst
);
Device.CreateTexture(&desc) => mTexture;

// Upload data
TextureDataLayout layout = .()
{
    Offset = 0,
    BytesPerRow = width * 4,
    RowsPerImage = height
};
Extent3D size = .(width, height, 1);
Device.Queue.WriteTexture(mTexture, pixelData, &layout, &size);
```

## Sample Projects

| Sample | Features |
|--------|----------|
| `RHITriangle` | Basic triangle, uniforms, rotation |
| `RHITexturedQuad` | Textures, samplers, index buffers |
| `RHIDepthBuffer` | 3D cubes with depth testing |
| `RHIInstancing` | Hardware instancing |
| `RHIBindGroups` | Multiple bind groups |
| `RHIBlending` | Alpha blending modes |
| `RHICompute` | Compute shaders, storage buffers |
| `RHIMRT` | Multiple render targets |
| `RHIMipmaps` | Mipmap generation |
| `RHIBlit` | Texture blitting/scaling |
| `RHIWireframe` | Wireframe rendering |
| `RHIReadback` | GPU to CPU data transfer |
| `RHIQueries` | Timestamps, occlusion queries |
| `RHIBorderSampler` | Border color sampling |
| `RHIMSAA` | Multisampling with resolve |

## Basic Sample Structure

```beef
class MySample : RHISampleApp
{
    private IBuffer mVertexBuffer;
    private IRenderPipeline mPipeline;
    // ... other resources

    public this() : base(.()
    {
        Title = "My Sample",
        Width = 800,
        Height = 600,
        ClearColor = .(0.1f, 0.1f, 0.1f, 1.0f),
        EnableDepth = false
    }) { }

    protected override bool OnInitialize()
    {
        // Create buffers, shaders, pipelines
        return true;
    }

    protected override void OnUpdate(float deltaTime, float totalTime)
    {
        // Game logic only - no buffer writes!
    }

    protected override void OnPrepareFrame(int32 frameIndex)
    {
        // Safe to write per-frame buffers here
    }

    protected override void OnRender(IRenderPassEncoder renderPass)
    {
        renderPass.SetPipeline(mPipeline);
        renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
        renderPass.Draw(3, 1, 0, 0);
    }

    protected override void OnCleanup()
    {
        if (mPipeline != null) delete mPipeline;
        if (mVertexBuffer != null) delete mVertexBuffer;
    }
}
```

## Project Structure

```
Code/Sedulous/Sedulous.RHI/src/
├── IBackend.bf              - Backend interface
├── IDevice.bf               - Device interface (resource creation)
├── IAdapter.bf              - GPU adapter interface
├── ISwapChain.bf            - Swap chain interface
├── IBuffer.bf               - Buffer interface
├── ITexture.bf              - Texture interface
├── ITextureView.bf          - Texture view interface
├── ISampler.bf              - Sampler interface
├── IShaderModule.bf         - Shader module interface
├── IRenderPipeline.bf       - Render pipeline interface
├── IComputePipeline.bf      - Compute pipeline interface
├── IPipelineLayout.bf       - Pipeline layout interface
├── IBindGroupLayout.bf      - Bind group layout interface
├── IBindGroup.bf            - Bind group interface
├── ICommandEncoder.bf       - Command encoder interface
├── IRenderPassEncoder.bf    - Render pass encoder interface
├── IComputePassEncoder.bf   - Compute pass encoder interface
├── ICommandBuffer.bf        - Command buffer interface
├── IQueue.bf                - Queue interface
├── IFence.bf                - Fence interface
├── IQuerySet.bf             - Query set interface
├── Descriptors/             - All descriptor structs
│   ├── BufferDescriptor.bf
│   ├── TextureDescriptor.bf
│   ├── SamplerDescriptor.bf
│   ├── RenderPipelineDescriptor.bf
│   └── ...
├── Enums/                   - All enumerations
│   ├── TextureFormat.bf
│   ├── BufferUsage.bf
│   ├── BlendState.bf
│   └── ...
└── ShaderUtils.bf           - Shader loading utilities

Code/Sedulous/Sedulous.RHI.Vulkan/src/
└── VulkanBackend.bf         - Vulkan implementation

Code/Samples/SampleFramework/src/
└── RHISampleApp.bf          - Base class for samples
```
