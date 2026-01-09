# Sedulous.Serialization

A unified serialization framework supporting both reading and writing with a single interface. Uses OpenDDL (Open Data Description Language) as the default format.

## Overview

```
Sedulous.Serialization           - Core interfaces and abstract base
Sedulous.Serialization.OpenDDL   - OpenDDL format implementation
Sedulous.Mathematics.Serialization - Math type extensions (Vector3, Matrix, etc.)
```

## Core Types

| Type | Purpose |
|------|---------|
| `ISerializable` | Interface for serializable types. Single `Serialize()` method for read/write. |
| `ISerializableFactory` | Creates instances by type ID for polymorphic deserialization. |
| `Serializer` | Abstract base class with unified read/write API. |
| `SerializerMode` | Enum: Read or Write. |
| `SerializationResult` | Result codes: Ok, FieldNotFound, TypeMismatch, etc. |
| `OpenDDLSerializer` | Concrete serializer using OpenDDL format. |

## Basic Usage

### Implementing ISerializable

```beef
class PlayerData : ISerializable
{
    public String Name = new .() ~ delete _;
    public int32 Level;
    public float Health;
    public bool IsActive;

    public int32 SerializationVersion => 1;

    public SerializationResult Serialize(Serializer s)
    {
        var result = s.String("name", Name);
        if (result != .Ok) return result;

        result = s.Int32("level", ref Level);
        if (result != .Ok) return result;

        result = s.Float("health", ref Health);
        if (result != .Ok) return result;

        result = s.Bool("isActive", ref IsActive);
        if (result != .Ok) return result;

        return .Ok;
    }
}
```

### Writing (Serialization)

```beef
let player = new PlayerData();
player.Name.Set("Hero");
player.Level = 10;
player.Health = 100.0f;
player.IsActive = true;

// Create writer
let writer = OpenDDLSerializer.CreateWriter();
defer delete writer;

// Serialize
PlayerData data = player;
writer.Object("player", ref data);

// Get output string
let output = scope String();
writer.GetOutput(output);

// Save to file
File.WriteAllText("save.oddl", output);
```

### Reading (Deserialization)

```beef
// Read file
let text = scope String();
File.ReadAllText("save.oddl", text);

// Parse OpenDDL
let doc = scope SerializableDataDescription();
doc.ParseText(text);

// Create reader
let reader = OpenDDLSerializer.CreateReader(doc);
defer delete reader;

// Deserialize
PlayerData player = null;
reader.Object("player", ref player);
defer delete player;

// Use data
Console.WriteLine($"Loaded: {player.Name} Level {player.Level}");
```

## Serializer API

### Mode Detection

```beef
serializer.IsReading  // true if deserializing
serializer.IsWriting  // true if serializing
serializer.Mode       // SerializerMode.Read or .Write
```

### Primitive Types

```beef
s.Bool("fieldName", ref boolValue);
s.Int8("fieldName", ref int8Value);
s.Int16("fieldName", ref int16Value);
s.Int32("fieldName", ref int32Value);
s.Int64("fieldName", ref int64Value);
s.UInt8("fieldName", ref uint8Value);
s.UInt16("fieldName", ref uint16Value);
s.UInt32("fieldName", ref uint32Value);
s.UInt64("fieldName", ref uint64Value);
s.Float("fieldName", ref floatValue);
s.Double("fieldName", ref doubleValue);
s.String("fieldName", stringValue);  // String object, not ref
```

### Enums

```beef
s.Enum<MyEnum>("fieldName", ref enumValue);
```

### Fixed Arrays

```beef
s.FixedFloatArray("fieldName", floatPtr, count);
s.FixedInt32Array("fieldName", int32Ptr, count);
```

### Dynamic Arrays

```beef
s.ArrayInt32("fieldName", ref int32Array);
s.ArrayFloat("fieldName", ref floatArray);
s.ArrayString("fieldName", ref stringArray);
```

### Nested Objects

```beef
// Single object (auto-creates on read if null)
s.Object<PlayerData>("player", ref playerData);

// Optional object (skips if null on write, doesn't create on read)
s.OptionalObject<Settings>("settings", ref settingsData);

// List of objects
s.ObjectList<Item>("items", itemList);
```

### Manual Nesting

```beef
// Begin/End for custom structure
s.BeginObject("customData");
s.Int32("value1", ref value1);
s.Float("value2", ref value2);
s.EndObject();

// Arrays with manual iteration
int32 count = items.Count;
s.BeginArray("items", ref count);
for (int i = 0; i < count; i++)
{
    s.BeginObject(default);
    items[i].Serialize(s);
    s.EndObject();
}
s.EndArray();
```

### Utility Methods

```beef
// Version management
var version = SerializationVersion;
s.Version(ref version);
// After reading: s.CurrentVersion contains the version from file

// Check field existence (reading only)
if (s.HasField("optionalField"))
{
    s.Int32("optionalField", ref optionalValue);
}
```

## Version Handling

Version support enables schema evolution:

```beef
public int32 SerializationVersion => 2;  // Current version

public SerializationResult Serialize(Serializer s)
{
    var version = SerializationVersion;
    s.Version(ref version);

    // Always serialize current fields
    s.String("name", Name);
    s.Int32("level", ref Level);

    // Handle version differences
    if (s.IsReading && s.CurrentVersion < 2)
    {
        // Old format - set defaults for new fields
        Health = 100.0f;
    }
    else
    {
        // New format - read/write health
        s.Float("health", ref Health);
    }

    return .Ok;
}
```

## Polymorphic Serialization

### ISerializableFactory

For deserializing objects when the concrete type isn't known at compile time:

```beef
class ComponentRegistry : ISerializableFactory
{
    private Dictionary<String, delegate ISerializable()> mFactories = new .();
    private Dictionary<Type, String> mTypeNames = new .();

    public void Register<T>(StringView typeName) where T : ISerializable, new
    {
        mFactories[new String(typeName)] = new () => new T();
        mTypeNames[typeof(T)] = new String(typeName);
    }

    public ISerializable CreateInstance(StringView typeId)
    {
        if (mFactories.TryGetValue(scope String(typeId), let factory))
            return factory();
        return null;
    }

    public void GetTypeId(ISerializable obj, String typeId)
    {
        if (mTypeNames.TryGetValue(obj.GetType(), let name))
            typeId.Append(name);
    }
}
```

### Using Factories

```beef
// Registration at startup
registry.Register<PlayerComponent>("PlayerComponent");
registry.Register<HealthComponent>("HealthComponent");
registry.Register<InventoryComponent>("InventoryComponent");

// Writing polymorphic data
s.BeginArray("components", ref count);
for (let component in components)
{
    s.BeginObject(default);

    // Store type identifier
    let typeName = scope String();
    registry.GetTypeId(component, typeName);
    s.String("type", typeName);

    // Serialize component data
    component.Serialize(s);

    s.EndObject();
}
s.EndArray();

// Reading polymorphic data
s.BeginArray("components", ref count);
for (int i = 0; i < count; i++)
{
    s.BeginObject(default);

    // Read type identifier
    let typeName = scope String();
    s.String("type", typeName);

    // Create correct type
    let component = registry.CreateInstance(typeName);
    if (component != null)
    {
        component.Serialize(s);
        components.Add(component);
    }

    s.EndObject();
}
s.EndArray();
```

## Math Type Extensions

The `Sedulous.Mathematics.Serialization` library provides extension methods:

```beef
using Sedulous.Mathematics.Serialization;

// Vector types
s.Vector2("position2d", ref position2d);
s.Vector3("position", ref position);
s.Vector4("color", ref color);

// Rotation
s.Quaternion("rotation", ref rotation);

// Transforms
s.Matrix4x4("transform", ref matrix);
```

## OpenDDL Format

### Output Example

```oddl
Obj_ $player
{
    string $name { "Hero" }
    int32 $level { 10 }
    float $health { 100.0 }
    bool $isActive { true }

    Arr_ $inventory
    {
        Obj_
        {
            string $name { "Sword" }
            int32 $damage { 25 }
        }
        Obj_
        {
            string $name { "Shield" }
            int32 $defense { 15 }
        }
    }
}
```

### Structure Types

| Type | OpenDDL | Purpose |
|------|---------|---------|
| Objects | `Obj_` | Nested serializable objects |
| Arrays | `Arr_` | Collections of objects |
| Primitives | `int32`, `float`, `string`, `bool`, etc. | Built-in OpenDDL types |

### SerializableDataDescription

Custom parser that preserves `Obj_` and `Arr_` structures:

```beef
// Use this instead of plain DataDescription for serialization
let doc = scope SerializableDataDescription();
doc.ParseText(text);
```

## Result Codes

```beef
enum SerializationResult
{
    Ok,                  // Success
    FieldNotFound,       // Required field missing
    TypeMismatch,        // Wrong data type
    InvalidData,         // Malformed data
    InvalidReference,    // Unresolvable reference
    WrongMode,           // Serializer in wrong mode
    NullValue,           // Null where not allowed
    ArraySizeMismatch,   // Unexpected array size
    UnsupportedVersion,  // Version not supported
    IOError,             // I/O error
    UnknownType,         // Unknown type identifier
    NestingTooDeep,      // Maximum depth exceeded
    DuplicateKey,        // Duplicate field name
}
```

## Common Patterns

### Resource Serialization

```beef
abstract class Resource : ISerializable
{
    private Guid mId;
    private String mName = new .() ~ delete _;

    public virtual int32 SerializationVersion => 1;

    public virtual SerializationResult Serialize(Serializer s)
    {
        var version = SerializationVersion;
        s.Version(ref version);

        // GUID as string
        let guidStr = scope String();
        if (s.IsWriting)
            mId.ToString(guidStr);
        s.String("id", guidStr);
        if (s.IsReading)
            mId = Guid.Parse(guidStr).GetValueOrDefault();

        s.String("name", mName);

        return OnSerialize(s);
    }

    protected virtual SerializationResult OnSerialize(Serializer s) => .Ok;
}
```

### Type Marshalling

```beef
// uint32 as int32
int32 layerMask = (int32)LayerMask;
s.Int32("layerMask", ref layerMask);
if (s.IsReading)
    LayerMask = (uint32)layerMask;

// Multiple bools as flags
int32 flags = (IsMain ? 1 : 0) | (UseReverseZ ? 2 : 0);
s.Int32("flags", ref flags);
if (s.IsReading)
{
    IsMain = (flags & 1) != 0;
    UseReverseZ = (flags & 2) != 0;
}
```

### Hierarchical Data with References

```beef
// Build index map for parent references
Dictionary<EntityId, int32> entityToIndex = scope .();
int32 index = 0;
for (let entity in Entities)
    entityToIndex[entity.Id] = index++;

// Serialize with index references
for (let entity in Entities)
{
    s.BeginObject(default);
    s.String("name", entity.Name);

    int32 parentIndex = -1;
    if (entity.ParentId.IsValid)
        entityToIndex.TryGetValue(entity.ParentId, out parentIndex);
    s.Int32("parent", ref parentIndex);

    s.EndObject();
}
```

## Best Practices

1. **Always check result codes** - Propagate errors immediately
2. **Maintain field order** - Fields must serialize in identical order
3. **Call `Version()` first** - Enable schema evolution
4. **Use extension methods** - Cleaner code for domain types
5. **Handle null gracefully** - Use `OptionalObject` or check before serializing
6. **Register factories early** - Before any deserialization
7. **Use `SerializableDataDescription`** - Preserves Obj_/Arr_ structures

## Project Structure

```
Code/Sedulous/Sedulous.Serialization/src/
├── ISerializable.bf           - Core interface
├── ISerializableFactory.bf    - Polymorphic factory interface
├── Serializer.bf              - Abstract base class
├── SerializerMode.bf          - Read/Write mode enum
└── SerializationResult.bf     - Result codes

Code/Sedulous/Sedulous.Serialization.OpenDDL/src/
├── OpenDDLSerializer.bf           - OpenDDL implementation
└── SerializableDataDescription.bf - Custom parser

Code/Sedulous/Sedulous.Mathematics.Serialization/src/
└── MathSerializerExtensions.bf    - Vector/Matrix extensions
```
