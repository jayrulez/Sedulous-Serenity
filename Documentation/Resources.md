# Sedulous.Resources

A unified resource management system with reference counting, caching, and asynchronous loading. Provides a framework for managing game resources like meshes, textures, audio, fonts, and scenes.

## Overview

```
ResourceSystem
├── ResourceCache          (thread-safe caching)
├── ResourceManager<T>     (type-specific loaders)
└── LoadResourceJob<T>     (async loading via JobSystem)
```

## Core Types

| Type | Purpose |
|------|---------|
| `IResource` | Base interface for all resources (ID, name, ref counting). |
| `Resource` | Abstract base class implementing ref counting and serialization. |
| `ResourceHandle<T>` | RAII-style handle with automatic ref count management. |
| `IResourceManager` | Interface for type-specific resource loaders. |
| `ResourceManager<T>` | Generic base class for resource managers. |
| `ResourceSystem` | Central registry, loading, and caching coordinator. |
| `ResourceCache` | Thread-safe cache for loaded resources. |
| `ResourceLoadError` | Error codes: NotFound, InvalidFormat, ReadError, etc. |

## Resource Lifecycle

```
Load Request
    ↓
Check Cache (if fromCache=true)
    ↓ (miss)
Get Manager for Type
    ↓
LoadFromFile() → LoadFromMemory()
    ↓
Cache Result (if cacheIfLoaded=true)
    ↓
Return ResourceHandle<T>
    ↓
Handle.Release() when done
    ↓ (RefCount → 0)
Resource Deleted
```

## Basic Usage

### Setup

```beef
// Create resource system
let resourceSystem = new ResourceSystem(logger, jobSystem);

// Register managers for each resource type
resourceSystem.AddResourceManager(new AudioClipResourceManager(audioSystem));
resourceSystem.AddResourceManager(new FontResourceManager());
resourceSystem.AddResourceManager(new SceneResourceManager(componentRegistry));
```

### Synchronous Loading

```beef
let result = resourceSystem.LoadResource<AudioClipResource>("sounds/music.wav");

switch (result)
{
case .Ok(var handle):
    defer handle.Release();  // Release when done
    let clip = handle.Resource?.Clip;
    if (clip != null)
        audioSystem.Play(clip);

case .Err(let error):
    logger.LogError($"Failed to load: {error}");
}
```

### Asynchronous Loading

```beef
resourceSystem.LoadResourceAsync<TextureResource>(
    "textures/hero.png",
    fromCache: true,
    cacheIfLoaded: true,
    onCompleted: new (result) =>
    {
        switch (result)
        {
        case .Ok(var handle):
            // Use texture...
            mTextureHandle = handle;  // Store handle
        case .Err(let error):
            Console.WriteLine($"Load failed: {error}");
        }
    },
    ownsDelegate: true  // System will delete delegate
);
```

## Reference Counting

Resources use manual reference counting with automatic deletion:

```beef
let resource = new MyResource();    // RefCount = 0
resource.AddRef();                   // RefCount = 1

var handle = ResourceHandle<MyResource>(resource);  // RefCount = 2
handle.Release();                    // RefCount = 1

resource.ReleaseRef();               // RefCount = 0 → deleted
```

### ResourceHandle<T>

RAII wrapper that manages ref counts automatically:

```beef
struct ResourceHandle<T> where T : IResource
{
    public T Resource { get; }      // Returns null if invalid
    public bool IsValid { get; }    // Valid and RefCount > 0

    public this(T resource);        // AddRef on construction
    public void Release() mut;      // ReleaseRef
    public void AddRef() mut;       // Manual AddRef
}
```

## Creating Custom Resources

### Step 1: Define the Resource

```beef
class GameConfigResource : Resource
{
    public String Title = new .() ~ delete _;
    public int32 ScreenWidth;
    public int32 ScreenHeight;
    public bool Fullscreen;

    public override int32 SerializationVersion => 1;

    protected override SerializationResult OnSerialize(Serializer s)
    {
        s.String("title", Title);
        s.Int32("screen_width", ref ScreenWidth);
        s.Int32("screen_height", ref ScreenHeight);
        s.Bool("fullscreen", ref Fullscreen);
        return .Ok;
    }
}
```

### Step 2: Define the Manager

```beef
class GameConfigResourceManager : ResourceManager<GameConfigResource>
{
    protected override Result<GameConfigResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
    {
        // Read stream into string
        let content = scope String();
        let bytes = scope uint8[memory.Length];
        if (memory.TryRead(bytes) case .Err)
            return .Err(.ReadError);
        content.Append((char8*)bytes.Ptr, bytes.Count);

        // Parse OpenDDL
        let doc = scope DataDescription();
        if (doc.ParseText(content) != .Ok)
            return .Err(.InvalidFormat);

        // Deserialize
        let reader = OpenDDLSerializer.CreateReader(doc);
        defer delete reader;

        let resource = new GameConfigResource();
        if (resource.Serialize(reader) != .Ok)
        {
            delete resource;
            return .Err(.InvalidFormat);
        }

        return .Ok(resource);
    }

    public override void Unload(GameConfigResource resource)
    {
        // Ref counting handles deletion
    }
}
```

### Step 3: Register and Use

```beef
resourceSystem.AddResourceManager(new GameConfigResourceManager());

let result = resourceSystem.LoadResource<GameConfigResource>("config/game.oddl");
```

## ResourceManager<T> API

```beef
abstract class ResourceManager<T> : IResourceManager where T : IResource
{
    // Type identification
    public Type ResourceType => typeof(T);

    // Override for custom file reading
    protected virtual Result<T, ResourceLoadError> LoadFromFile(StringView path);

    // Must override - parse from memory stream
    protected abstract Result<T, ResourceLoadError> LoadFromMemory(MemoryStream memory);

    // Must override - cleanup
    public abstract void Unload(T resource);

    // Helper for reading files
    protected virtual Result<void, ResourceLoadError> ReadFile(StringView path, List<uint8> buffer);
}
```

## ResourceSystem API

### Registration

```beef
void AddResourceManager(IResourceManager manager);
void RemoveResourceManager(IResourceManager manager);
```

### Loading

```beef
Result<ResourceHandle<T>, ResourceLoadError> LoadResource<T>(
    StringView path,
    bool fromCache = true,
    bool cacheIfLoaded = true);

Job<Result<ResourceHandle<T>, ResourceLoadError>> LoadResourceAsync<T>(
    StringView path,
    bool fromCache = true,
    bool cacheIfLoaded = true,
    delegate void(Result<...>) onCompleted = null,
    bool ownsDelegate = true);
```

### Management

```beef
Result<ResourceHandle<T>, ResourceLoadError> AddResource<T>(T resource, bool cache = true);
void UnloadResource<T>(ref ResourceHandle<IResource> resource);
ResourceCache Cache { get; }
void Startup();
void Shutdown();  // Unloads all cached resources
```

## Caching

### Cache Behavior

```beef
// Load with caching (default)
LoadResource<T>(path);

// Skip cache lookup, still cache result
LoadResource<T>(path, fromCache: false, cacheIfLoaded: true);

// Completely bypass cache
LoadResource<T>(path, fromCache: false, cacheIfLoaded: false);
```

### Cache Keys

Cache uses composite keys: `(Path, ResourceType)`. Same path with different types = different cache entries.

### Cache Access

```beef
int count = resourceSystem.Cache.Count;
resourceSystem.Cache.Clear();
```

## Error Handling

```beef
enum ResourceLoadError
{
    NotFound,        // File not found
    ManagerNotFound, // No manager for type
    InvalidFormat,   // Parse/format error
    ReadError,       // I/O error
    NotSupported,    // Unsupported operation
    Unknown          // Generic error
}
```

## Real-World Examples

### AudioClipResource

```beef
class AudioClipResource : Resource
{
    private IAudioClip mClip ~ if (_ != null) delete _;
    public IAudioClip Clip { get => mClip; set => mClip = value; }
}

class AudioClipResourceManager : ResourceManager<AudioClipResource>
{
    private IAudioSystem mAudioSystem;

    protected override Result<AudioClipResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
    {
        let buffer = scope List<uint8>((int)memory.Length);
        buffer.Count = (int)memory.Length;
        if (memory.TryRead(buffer) case .Err)
            return .Err(.ReadError);

        switch (mAudioSystem.LoadClip(Span<uint8>(buffer.Ptr, buffer.Count)))
        {
        case .Ok(let clip):
            let resource = new AudioClipResource();
            resource.Clip = clip;
            return .Ok(resource);
        case .Err:
            return .Err(.InvalidFormat);
        }
    }
}
```

### FontResource with Custom Caching

```beef
class FontResourceManager : ResourceManager<FontResource>
{
    private Dictionary<String, FontResource> mCache ~ DeleteDictionaryAndKeys!(_);

    public Result<FontResource, ResourceLoadError> LoadFont(StringView path, FontLoadOptions options)
    {
        // Check internal cache first
        if (mCache.TryGetValue(scope String(path), let cached))
        {
            cached.AddRef();
            return .Ok(cached);
        }

        // Load and cache
        if (FontLoaderFactory.LoadFont(path, options) case .Ok(let font))
        {
            let resource = new FontResource(font);
            mCache[new String(path)] = resource;
            resource.AddRef();  // Cache ref
            resource.AddRef();  // Caller ref
            return .Ok(resource);
        }

        return .Err(.NotFound);
    }
}
```

## Thread Safety

| Operation | Thread Safety |
|-----------|---------------|
| `AddRef()`/`ReleaseRef()` | Thread-safe (Interlocked) |
| `ResourceCache` operations | Thread-safe (Monitor) |
| `ResourceSystem` manager registry | Thread-safe (Monitor) |
| Async loading | Via JobSystem with main-thread callbacks |

## Best Practices

1. **Always release handles** when done with resources
2. **Use `defer handle.Release()`** for automatic cleanup
3. **Prefer async loading** for large resources
4. **Enable caching** unless resources change at runtime
5. **Implement `OnSerialize()`** for resource persistence
6. **Handle all error cases** in switch statements
7. **Clean up sub-objects** in resource destructors

## Project Structure

```
Code/Sedulous/Sedulous.Resources/src/
├── IResource.bf           - Resource interface
├── Resource.bf            - Abstract base class
├── ResourceHandle.bf      - RAII handle
├── IResourceManager.bf    - Manager interface
├── ResourceManager.bf     - Generic manager base
├── ResourceSystem.bf      - Central coordinator
├── ResourceCache.bf       - Thread-safe cache
├── ResourceCacheKey.bf    - Cache key structure
├── ResourceLoadError.bf   - Error enum
└── LoadResourceJob.bf     - Async loading job
```
