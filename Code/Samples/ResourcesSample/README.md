# ResourcesSample

Demonstrates the Sedulous resource serialization system using OpenDDL format.

## Features

- Custom resource class definition
- Resource serialization to OpenDDL format
- Resource deserialization from OpenDDL format
- Data verification after round-trip

## What It Does

1. Creates a `PlayerSaveResource` with player data (name, level, health, position, gold)
2. Serializes to OpenDDL format and saves to disk
3. Displays the OpenDDL file contents
4. Loads the resource back from disk
5. Verifies all data matches the original

## Technical Details

- Extends `Resource` base class
- Implements `OnSerialize()` for bidirectional serialization
- Uses `OpenDDLSerializer` for reading/writing
- Demonstrates serialization of strings, integers, floats, and Vector3

## Sample Output

```
Step 1: Creating player save resource...
Original resource:
=== Player Save Data ===
  Player: Hero
  Level: 25
  Health: 85.5/100
  Position: (123.5, 0, -456.7)
  Gold: 9999
========================
```

## Dependencies

- Sedulous.Resources
- Sedulous.Serialization
- Sedulous.Serialization.OpenDDL
- Sedulous.Mathematics
