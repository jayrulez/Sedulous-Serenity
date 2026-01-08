# Sedulous.Geometry

A CPU-side mesh and geometry library for creating, storing, and manipulating 3D geometry. Provides vertex/index buffers, primitive generation, and mesh data structures for GPU upload.

## Overview

```
Sedulous.Geometry           - Core mesh types and buffers
Sedulous.Geometry.Tooling   - Model import and conversion
```

## Core Types

| Type | Purpose |
|------|---------|
| `VertexBuffer` | Dynamic vertex data storage with attribute tracking. |
| `IndexBuffer` | Index data storage (16-bit or 32-bit). |
| `VertexAttribute` | Describes a vertex attribute (name, type, offset). |
| `SubMesh` | Defines a mesh portion with material and topology. |
| `StaticMesh` | Non-animated mesh with vertex/index buffers. |
| `SkinnedMesh` | Animated mesh with bone weights. |
| `SkinnedVertex` | Fixed 72-byte vertex format for skeletal animation. |
| `AttributeType` | Vertex data types (Float, Vec2, Vec3, Vec4, etc.). |
| `PrimitiveType` | Rendering topology (Triangles, Lines, Points, etc.). |

## VertexBuffer

Dynamic storage for vertex data with flexible attribute layouts.

### Basic Usage

```beef
let buffer = new VertexBuffer(vertexSize: 32);
defer delete buffer;

// Define attributes
buffer.AddAttribute("position", .Vec3, offset: 0, size: 12);
buffer.AddAttribute("normal", .Vec3, offset: 12, size: 12);
buffer.AddAttribute("uv", .Vec2, offset: 24, size: 8);

// Allocate vertices
buffer.Resize(100);

// Write data
buffer.SetVertexData<Vector3>(index: 0, offset: 0, .(1, 2, 3));
buffer.SetVertexData<Vector3>(index: 0, offset: 12, .(0, 1, 0));
buffer.SetVertexData<Vector2>(index: 0, offset: 24, .(0.5f, 0.5f));

// Read data
Vector3 pos = buffer.GetVertexData<Vector3>(index: 0, offset: 0);
```

### API

```beef
Reserve(int32 count)           // Ensure capacity
Resize(int32 count)            // Set vertex count
AddAttribute(name, type, offset, size)
SetVertexData<T>(index, offset, value)
GetVertexData<T>(index, offset) -> T
GetRawData() -> uint8*         // For GPU upload
GetDataSize() -> int32         // Total bytes

// Properties
VertexCount -> int32
VertexSize -> int32
Attributes -> List<VertexAttribute>
```

## IndexBuffer

Stores face indices in 16-bit or 32-bit format.

### Basic Usage

```beef
let buffer = new IndexBuffer(.UInt16);
defer delete buffer;

buffer.Resize(6);
buffer.SetIndex(0, 0);
buffer.SetIndex(1, 1);
buffer.SetIndex(2, 2);
buffer.SetIndex(3, 2);
buffer.SetIndex(4, 1);
buffer.SetIndex(5, 3);

uint32 index = buffer.GetIndex(0);
```

### API

```beef
Reserve(int32 count)
Resize(int32 count)
SetIndex(index, value)
GetIndex(index) -> uint32
GetIndexSize() -> int32        // 2 or 4 bytes
GetRawData() -> uint8*
GetDataSize() -> int32

// Properties
IndexCount -> int32
Format -> IndexFormat          // UInt16 or UInt32
```

## StaticMesh

Complete mesh with vertex data, indices, and submeshes.

### Creating with Common Format

```beef
let mesh = new StaticMesh();
defer delete mesh;

mesh.SetupCommonVertexFormat();  // 52-byte PBR format
mesh.Vertices.Resize(4);
mesh.Indices.Resize(6);

// Set vertex data using convenience methods
mesh.SetPosition(0, .(0, 0, 0));
mesh.SetNormal(0, .(0, 1, 0));
mesh.SetUV(0, .(0, 0));
mesh.SetColor(0, 0xFFFFFFFF);
mesh.SetTangent(0, .(1, 0, 0));

// Set indices
mesh.Indices.SetIndex(0, 0);
mesh.Indices.SetIndex(1, 1);
mesh.Indices.SetIndex(2, 2);

// Add submesh
mesh.AddSubMesh(SubMesh(startIndex: 0, indexCount: 6, materialIndex: 0));

// Generate tangents
mesh.GenerateTangents();
```

### Common Vertex Format (52 bytes)

| Offset | Attribute | Type | Size |
|--------|-----------|------|------|
| 0 | Position | Vector3 | 12 |
| 12 | Normal | Vector3 | 12 |
| 24 | UV | Vector2 | 8 |
| 32 | Color | uint32 | 4 |
| 36 | Tangent | Vector3 | 12 |

### Custom Vertex Format

```beef
let mesh = new StaticMesh();

int32 vertexSize = sizeof(Vector3) + sizeof(Vector2);
mesh.Initialize(vertexSize, .UInt16);

mesh.Vertices.AddAttribute("position", .Vec3, 0, 12);
mesh.Vertices.AddAttribute("uv", .Vec2, 12, 8);

mesh.Vertices.Resize(4);
mesh.SetVertexAttribute<Vector3>(0, 0, position);
mesh.SetVertexAttribute<Vector2>(0, 12, uv);
```

### API

```beef
// Initialization
Initialize(vertexSize, indexFormat)
SetupCommonVertexFormat()

// Vertex access (common format)
SetPosition(index, pos) / GetPosition(index) -> Vector3
SetNormal(index, normal) / GetNormal(index) -> Vector3
SetUV(index, uv) / GetUV(index) -> Vector2
SetColor(index, color) / GetColor(index) -> uint32
SetTangent(index, tangent) / GetTangent(index) -> Vector3

// Generic access
SetVertexAttribute<T>(index, offset, value)
GetVertexAttribute<T>(index, offset) -> T

// Mesh operations
AddSubMesh(submesh)
GenerateTangents()
GetBounds() -> BoundingBox

// Properties
Vertices -> VertexBuffer
Indices -> IndexBuffer
SubMeshes -> List<SubMesh>
```

## Primitive Factory Methods

StaticMesh provides factory methods for common primitives:

### Triangle

```beef
let mesh = StaticMesh.CreateTriangle();
// 3 vertices at (-1,-1,0), (1,-1,0), (0,1,0)
// 3 indices, 1 submesh
```

### Quad

```beef
let mesh = StaticMesh.CreateQuad(width: 1.0f, height: 1.0f);
// 4 vertices, 6 indices, 1 submesh
```

### Cube

```beef
let mesh = StaticMesh.CreateCube(size: 1.0f);
// 24 vertices (4 per face for correct normals)
// 36 indices, 1 submesh
```

### Sphere

```beef
let mesh = StaticMesh.CreateSphere(radius: 0.5f, segments: 32, rings: 16);
// UV sphere with proper normals
// (rings+1)*(segments+1) vertices
```

### Cylinder

```beef
let mesh = StaticMesh.CreateCylinder(radius: 0.5f, height: 1.0f, segments: 32);
// With top and bottom caps
// Separate normals for caps and sides
```

### Cone

```beef
let mesh = StaticMesh.CreateCone(radius: 0.5f, height: 1.0f, segments: 32);
// With base cap
```

### Torus

```beef
let mesh = StaticMesh.CreateTorus(radius: 1.0f, tubeRadius: 0.3f, segments: 32, tubeSegments: 16);
// Doughnut shape
```

### Plane

```beef
let mesh = StaticMesh.CreatePlane(width: 10.0f, depth: 10.0f, widthSegments: 10, depthSegments: 10);
// Subdivided plane at Y=0
// Useful for terrain or grids
```

## SkinnedMesh

Mesh with bone weights for skeletal animation.

### SkinnedVertex (72 bytes)

```beef
[CRepr]
struct SkinnedVertex
{
    Vector3 Position;      // 12 bytes
    Vector3 Normal;        // 12 bytes
    Vector2 TexCoord;      // 8 bytes
    uint32 Color;          // 4 bytes (packed RGBA)
    Vector3 Tangent;       // 12 bytes
    uint16[4] Joints;      // 8 bytes (up to 4 bone indices)
    Vector4 Weights;       // 16 bytes (bone weights, sum to 1.0)
}
```

### Basic Usage

```beef
let mesh = new SkinnedMesh();
defer delete mesh;

mesh.ResizeVertices(100);
mesh.ReserveIndices(300);

// Create vertex
SkinnedVertex v = .();
v.Position = .(1, 2, 3);
v.Normal = .(0, 1, 0);
v.TexCoord = .(0.5f, 0.5f);
v.Color = SkinnedMesh.PackColor(.(1, 1, 1, 1));
v.Joints = .(0, 1, 2, 3);  // Bone indices
v.Weights = .(0.5f, 0.3f, 0.15f, 0.05f);  // Must sum to 1.0

mesh.SetVertex(0, v);

// Add triangles
mesh.AddTriangle(0, 1, 2);
mesh.AddIndex(3);

// Add submesh
mesh.AddSubMesh(SubMesh(0, mesh.IndexCount, 0));

// Calculate bounds
mesh.CalculateBounds();
```

### API

```beef
// Vertex management
ResizeVertices(count)
AddVertex(vertex)
SetVertex(index, vertex)
GetVertex(index) -> SkinnedVertex

// Index management
ReserveIndices(count)
AddIndex(index)
AddTriangle(i0, i1, i2)
SetIndex(position, value)

// Other
AddSubMesh(submesh)
CalculateBounds()
PackColor(Vector4) -> uint32  // Static helper
PackColor(Color) -> uint32

// Properties
Vertices -> List<SkinnedVertex>
Indices -> IndexBuffer
SubMeshes -> List<SubMesh>
Bounds -> BoundingBox
VertexCount -> int32
IndexCount -> int32
VertexSize -> int32  // Always 72
```

## SubMesh

Defines a portion of a mesh for multi-material rendering.

```beef
struct SubMesh
{
    int32 startIndex;      // Start in index buffer
    int32 indexCount;      // Number of indices
    int32 materialIndex;   // Material to use (default: 0)
    PrimitiveType primitiveType;  // Topology (default: Triangles)
}

// Constructor
SubMesh(startIndex, indexCount, materialIndex = 0, primitiveType = .Triangles)
```

## AttributeType

```beef
enum AttributeType
{
    Float,    // Single float
    Vec2,     // 2 floats
    Vec3,     // 3 floats
    Vec4,     // 4 floats
    Int,      // Single int
    UInt,     // Single uint
    Color32   // Packed RGBA
}
```

## PrimitiveType

```beef
enum PrimitiveType
{
    Triangles,
    TriangleStrip,
    TriangleFan,
    Lines,
    LineStrip,
    Points
}
```

## GPU Integration

### Uploading to GPU

```beef
// Create CPU mesh
let cpuMesh = StaticMesh.CreateCube(1.0f);
defer delete cpuMesh;

// Upload via resource manager
let gpuHandle = resourceManager.CreateMesh(cpuMesh);

// Get GPU mesh for rendering
let gpuMesh = resourceManager.GetMesh(gpuHandle);
```

### Rendering

```beef
renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);

for (let submesh in gpuMesh.SubMeshes)
{
    // Set material for this submesh
    SetMaterial(submesh.materialIndex);

    // Draw
    renderPass.DrawIndexed(
        submesh.indexCount,
        instanceCount: 1,
        submesh.startIndex,
        baseVertex: 0,
        firstInstance: 0
    );
}
```

### Cleanup

```beef
resourceManager.ReleaseMesh(gpuHandle);
```

## Tangent Generation

The `GenerateTangents()` method uses Lengyel's algorithm:

1. Calculates tangent vectors from edge and UV differences
2. Normalizes tangents
3. Orthogonalizes against normals (Gram-Schmidt)
4. Generates default tangents when computation fails

Required for normal mapping.

## Best Practices

1. **Use common format when possible** - `SetupCommonVertexFormat()` for standard PBR
2. **Choose correct index format** - UInt16 for meshes < 65536 vertices
3. **Normalize bone weights** - Must sum to 1.0 for correct skinning
4. **Generate tangents** - Required for normal mapping
5. **Delete CPU mesh after GPU upload** - Free memory once uploaded
6. **Use factory methods** - Primitives are well-tested and optimized

## Project Structure

```
Code/Sedulous/Sedulous.Geometry/src/
├── AttributeType.bf       - Vertex attribute types
├── PrimitiveType.bf       - Rendering topology
├── VertexAttribute.bf     - Attribute descriptor
├── VertexBuffer.bf        - Vertex data storage
├── IndexBuffer.bf         - Index data storage
├── SubMesh.bf             - Sub-mesh definition
├── StaticMesh.bf          - Non-animated mesh
├── SkinnedMesh.bf         - Animated mesh
└── SkinnedVertex.bf       - Skinned vertex format

Code/Sedulous/Sedulous.Geometry.Tooling/src/
├── ModelMeshConverter.bf  - Model to mesh conversion
├── ModelImporter.bf       - Full import pipeline
└── SkeletonConverter.bf   - Skeleton extraction
```
