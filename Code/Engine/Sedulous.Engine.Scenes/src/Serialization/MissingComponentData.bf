namespace Sedulous.Engine.Scenes;

using System;
using System.Collections;

/// Stores serialized data for a component type with no registered serializer.
/// Preserves data for roundtripping (read -> hold -> write back).
class MissingComponentData
{
	/// The type name of the missing component (as stored in serialized data).
	public String TypeName ~ delete _;
	/// Per-entity data entries.
	public List<MissingEntityEntry> Entries = new .() ~ DeleteContainerAndItems!(_);

	public this(StringView typeName)
	{
		TypeName = new String(typeName);
	}
}

/// One entity's data for a missing component type.
class MissingEntityEntry
{
	/// The serialized entity index (from the save file).
	public int32 EntityIndex;
	/// Raw component data as base64 string.
	public String RawData ~ delete _;

	public this(int32 entityIndex, StringView rawData)
	{
		EntityIndex = entityIndex;
		RawData = new String(rawData);
	}
}
