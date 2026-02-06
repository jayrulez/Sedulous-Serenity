namespace Sedulous.Framework.Scenes;

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

	/// Encode raw bytes to base64 string. STUB - returns empty string.
	public static void EncodeBase64(Span<uint8> data, String outBase64)
	{
		// TODO: Implement base64 encoding
	}

	/// Decode base64 string to raw bytes. STUB - returns empty.
	public static void DecodeBase64(StringView base64, List<uint8> outData)
	{
		// TODO: Implement base64 decoding
	}
}

/// One entity's data for a missing component type.
class MissingEntityEntry
{
	/// The serialized entity index (from the save file).
	public int32 EntityIndex;
	/// Raw component data encoded as base64 (stub: stored as empty string for now).
	public String RawData ~ delete _;

	public this(int32 entityIndex, StringView rawData)
	{
		EntityIndex = entityIndex;
		RawData = new String(rawData);
	}
}
