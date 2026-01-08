# Sedulous.Models

A 3D model representation library for loading, storing, and processing model data. Supports GLTF 2.0/GLB formats with full PBR materials, skeletal animation, and skinning.

## Overview

```
Sedulous.Models           - Core model data structures
Sedulous.Models.GLTF      - GLTF/GLB loader using cgltf
Sedulous.Geometry.Tooling - Import pipeline (Model -> GPU resources)
```

## Core Types

| Type | Purpose |
|------|---------|
| `Model` | Root container for all model data (meshes, materials, bones, animations). |
| `ModelMesh` | Geometry with vertex/index buffers and variable vertex formats. |
| `ModelMeshPart` | Portion of mesh using a specific material (index range + material ID). |
| `ModelVertex` | Standard 48-byte vertex: position, normal, texcoord, color, tangent. |
| `SkinnedModelVertex` | Extended 72-byte vertex adding joint indices and weights. |
| `ModelMaterial` | PBR material properties (base color, metallic, roughness, textures). |
| `ModelBone` | Skeleton node with transform, inverse bind matrix, parent/child links. |
| `ModelSkin` | Bone indices and inverse bind matrices for skeletal animation. |
| `ModelAnimation` | Animation with channels and duration. |
| `AnimationChannel` | Targets a bone property with keyframes and interpolation. |
| `ModelTexture` | Texture with embedded or external image data. |
| `TextureSampler` | Filtering and wrapping modes for textures. |

## Loading Pipeline

```
GLTF/GLB File
    |
    v
GltfLoader.Load()         Stage 1: Parse GLTF
    |
    v
Model (raw data)
    |
    v
ModelImporter.Import()    Stage 2: Convert to CPU resources
    |
    v
StaticMesh/SkinnedMesh/Skeleton/AnimationClip
    |
    v
ResourceSerializer        Stage 3: Cache for fast loading
    |
    v
GPU Resources
```

## Basic Usage

### Loading a Model

```beef
let model = new Model();
defer delete model;

let loader = scope GltfLoader();
let result = loader.Load("assets/character.glb", model);

switch (result)
{
case .Ok:
    Console.WriteLine($"Loaded {model.Meshes.Count} meshes");
case .FileNotFound:
    Console.WriteLine("File not found");
case .ParseError:
    Console.WriteLine("Invalid GLTF format");
}
```

### Importing for Rendering

```beef
let importOptions = new ModelImportOptions();
defer delete importOptions;

importOptions.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Textures | .Materials;
importOptions.BasePath.Set(modelDirectory);
importOptions.Scale = 1.0f;
importOptions.GenerateTangents = true;

let importer = scope ModelImporter(importOptions, imageLoader);
let importResult = importer.Import(model);

if (importResult.Success)
{
    let mesh = importResult.TakeSkinnedMesh(0);
    let skeleton = importResult.Skeleton;
    let animations = importResult.AnimationClips;
}
```

### Caching Imported Resources

```beef
// Save to cache
ResourceSerializer.SaveImportResult(importResult, cacheDirectory);

// Load from cache (fast)
let cached = ResourceSerializer.LoadSkinnedMeshBundle(cachePath);
```

## Model API

### Adding Resources

```beef
int32 meshIndex = model.AddMesh(mesh);
int32 materialIndex = model.AddMaterial(material);
int32 boneIndex = model.AddBone(bone);
int32 skinIndex = model.AddSkin(skin);
int32 animIndex = model.AddAnimation(animation);
int32 texIndex = model.AddTexture(texture);
int32 samplerIndex = model.AddSampler(sampler);
```

### Querying by Name

```beef
let mesh = model.GetMesh("Body");
let material = model.GetMaterial("Skin");
let bone = model.GetBone("Spine");
let animation = model.GetAnimation("Walk");
```

### Building Hierarchy

```beef
// After adding all bones
model.BuildBoneHierarchy();  // Establishes parent-child relationships
model.CalculateBounds();     // Computes bounds from all meshes
```

## ModelMesh

### Vertex Data Management

```beef
let mesh = new ModelMesh();
mesh.SetName("MyMesh");

// Allocate buffers
mesh.AllocateVertices(100, sizeof(ModelVertex));
mesh.AllocateIndices(300, false);  // false = uint16 indices

// Access raw data
uint8* vertexData = mesh.GetVertexData();
uint8* indexData = mesh.GetIndexData();

// Type-safe data setting
ModelVertex[] vertices = ...;
mesh.SetVertexData(vertices);

uint16[] indices = ...;
mesh.SetIndexData(indices);
```

### Vertex Elements

```beef
mesh.AddVertexElement(VertexElement(.Position, .Float3, 0, 0));
mesh.AddVertexElement(VertexElement(.Normal, .Float3, 12, 0));
mesh.AddVertexElement(VertexElement(.TexCoord, .Float2, 24, 0));
```

### Mesh Parts

```beef
// Each part references a material
mesh.AddPart(ModelMeshPart(startIndex: 0, indexCount: 100, materialIndex: 0));
mesh.AddPart(ModelMeshPart(startIndex: 100, indexCount: 200, materialIndex: 1));
```

## ModelMaterial (PBR)

```beef
let material = new ModelMaterial();
material.SetName("Metal");

// Base color
material.BaseColorFactor = .(0.8f, 0.8f, 0.8f, 1.0f);
material.BaseColorTextureIndex = 0;

// Metallic-roughness
material.MetallicFactor = 1.0f;
material.RoughnessFactor = 0.3f;
material.MetallicRoughnessTextureIndex = 1;

// Normal map
material.NormalTextureIndex = 2;
material.NormalScale = 1.0f;

// Occlusion
material.OcclusionTextureIndex = 3;
material.OcclusionStrength = 1.0f;

// Emissive
material.EmissiveFactor = .(0, 0, 0);
material.EmissiveTextureIndex = -1;

// Alpha
material.AlphaMode = .Opaque;  // Opaque, Mask, Blend
material.AlphaCutoff = 0.5f;
material.DoubleSided = false;
```

## Skeletal Animation

### ModelBone

```beef
let bone = new ModelBone();
bone.SetName("LeftArm");
bone.ParentIndex = parentBoneIndex;

// Local transform (TRS)
bone.Translation = .(0, 1, 0);
bone.Rotation = Quaternion.Identity;
bone.Scale = .(1, 1, 1);

// For skinning
bone.InverseBindMatrix = inverseBindPose;
```

### AnimationChannel

```beef
let channel = new AnimationChannel();
channel.BoneIndex = 5;
channel.Path = .Translation;  // Translation, Rotation, Scale, Weights
channel.Interpolation = .Linear;  // Linear, Step, CubicSpline

// Add keyframes
channel.AddKeyframe(0.0f, .(0, 0, 0, 0));
channel.AddKeyframe(0.5f, .(0, 1, 0, 0));
channel.AddKeyframe(1.0f, .(0, 0, 0, 0));

// Sample at time
Vector4 value = channel.Sample(0.25f);  // Interpolated
```

### ModelAnimation

```beef
let animation = new ModelAnimation();
animation.SetName("Walk");
animation.AddChannel(translationChannel);
animation.AddChannel(rotationChannel);
animation.CalculateDuration();  // Sets duration from keyframes

float duration = animation.Duration;
```

### Interpolation Types

| Type | Behavior |
|------|----------|
| `Linear` | Lerp for translation/scale, Slerp for rotation |
| `Step` | No interpolation, uses previous keyframe value |
| `CubicSpline` | Smooth cubic spline with tangent control |

## Vertex Formats

### ModelVertex (48 bytes)

```beef
[CRepr]
struct ModelVertex
{
    Vector3 Position;   // 12 bytes
    Vector3 Normal;     // 12 bytes
    Vector2 TexCoord;   // 8 bytes
    uint32 Color;       // 4 bytes (packed RGBA)
    Vector3 Tangent;    // 12 bytes
}
```

### SkinnedModelVertex (72 bytes)

```beef
[CRepr]
struct SkinnedModelVertex
{
    Vector3 Position;      // 12 bytes
    Vector3 Normal;        // 12 bytes
    Vector2 TexCoord;      // 8 bytes
    uint32 Color;          // 4 bytes
    Vector3 Tangent;       // 12 bytes
    uint16[4] Joints;      // 8 bytes (bone indices)
    Vector4 Weights;       // 16 bytes (bone weights, sum to 1.0)
}
```

## Import Options

```beef
class ModelImportOptions
{
    public ModelImportFlags Flags;
    public String BasePath;        // For external textures
    public float Scale = 1.0f;
    public bool GenerateTangents = true;
    public bool CalculateBounds = true;
    public bool FlipUVs = false;
    public bool MergeMeshes = false;
    public int32 MaxBonesPerVertex = 4;
}

[Flags]
enum ModelImportFlags
{
    Meshes,
    SkinnedMeshes,
    Skeletons,
    Animations,
    Textures,
    Materials,
    All = Meshes | SkinnedMeshes | Skeletons | Animations | Textures | Materials
}
```

## GLTF Loader Results

```beef
enum GltfResult
{
    Ok,
    FileNotFound,
    ParseError,
    InvalidFormat,
    UnsupportedVersion,
    BufferLoadError
}
```

## Framework Integration

### With Renderer Components

```beef
// Create entity with skinned mesh
let entity = scene.CreateEntity("Character");

let meshComponent = new SkinnedMeshComponent();
entity.AddComponent(meshComponent);

meshComponent.SetSkeleton(importResult.Skeleton, false);
meshComponent.SetMesh(importResult.TakeSkinnedMesh(0));
meshComponent.SetMaterial(materialHandle);

// Play animation
if (meshComponent.AnimationClips.Count > 0)
    meshComponent.PlayAnimation(0, loop: true);
```

### With Resource System

```beef
// Cache-aware loading pattern
if (File.Exists(cachePath))
{
    resource = ResourceSerializer.LoadSkinnedMeshBundle(cachePath);
}
else
{
    let model = new Model();
    GltfLoader.Load(gltfPath, model);

    let importer = scope ModelImporter(options, imageLoader);
    let result = importer.Import(model);

    resource = result.TakeSkinnedMesh(0);
    ResourceSerializer.SaveImportResult(result, cacheDir);

    delete model;
}
```

## Best Practices

1. **Use caching** - Import once, serialize, load from cache
2. **Delete Model after import** - Raw model data not needed after conversion
3. **Check GltfResult** - Handle all error cases
4. **Set BasePath** - Required for external textures
5. **Build hierarchy after adding bones** - Call `BuildBoneHierarchy()` last
6. **Weights sum to 1.0** - Normalize bone weights for correct skinning

## Project Structure

```
Code/Sedulous/Sedulous.Models/src/
├── Model.bf               - Root model container
├── ModelMesh.bf           - Mesh geometry
├── ModelMeshPart.bf       - Sub-mesh definition
├── ModelVertex.bf         - Standard vertex format
├── SkinnedModelVertex.bf  - Skinned vertex format
├── VertexElement.bf       - Vertex attribute descriptor
├── VertexFormat.bf        - Format enum
├── VertexSemantic.bf      - Semantic enum
├── ModelMaterial.bf       - PBR material
├── AlphaMode.bf           - Alpha mode enum
├── ModelBone.bf           - Skeleton bone
├── ModelSkin.bf           - Skinning data
├── ModelAnimation.bf      - Animation container
├── AnimationChannel.bf    - Animation channel
├── AnimationKeyframe.bf   - Keyframe data
├── AnimationInterpolation.bf
├── AnimationPath.bf
├── ModelTexture.bf        - Texture data
├── TextureSampler.bf      - Sampler settings
└── TextureEnums.bf        - Texture enums

Code/Sedulous/Sedulous.Models.GLTF/src/
├── GltfLoader.bf          - GLTF/GLB parser
└── GltfResult.bf          - Result enum

Code/Sedulous/Sedulous.Geometry.Tooling/src/
├── ModelImporter.bf       - Import pipeline
├── ModelImportOptions.bf  - Import configuration
├── ModelImportResult.bf   - Import output
├── ModelMeshConverter.bf  - Mesh conversion
├── SkeletonConverter.bf   - Skeleton conversion
└── ResourceSerializer.bf  - Cache serialization
```
