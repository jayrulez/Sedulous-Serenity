namespace Sedulous.Engine.Scenes;

using System;
using System.Collections;
using Sedulous.Core;
using Sedulous.Serialization;

/// Serializer for component types that have no registered IComponentSerializer.
/// During reading, captures entity indices and raw data via CaptureScope + Base64.
/// During writing, replays the captured data via Base64 + RestoreScope.
class MissingComponentSerializer : IComponentSerializer
{
	private MissingComponentData mData;

	public StringView TypeName => mData.TypeName;

	public this(MissingComponentData data)
	{
		mData = data;
	}

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		if (mData.Entries.Count == 0)
			return .Ok;

		s.BeginObject(mData.TypeName);
		int32 count = (int32)mData.Entries.Count;
		s.Int32("count", ref count);

		for (int i = 0; i < mData.Entries.Count; i++)
		{
			let entry = mData.Entries[i];
			s.BeginObject(scope $"c{i}");
			var entityIdx = entry.EntityIndex;
			s.Int32("entity", ref entityIdx);

			if (!entry.RawData.IsEmpty)
			{
				// Decode base64 back to format-specific text, then restore the scope
				let decodedBytes = scope List<uint8>();
				if (Base64.Decode(entry.RawData, decodedBytes) case .Ok)
				{
					let scopeText = scope String((char8*)decodedBytes.Ptr, decodedBytes.Count);
					if (!s.RestoreScope(scopeText))
					{
						// Fallback: write as _rawData string field
						let rawStr = scope String();
						rawStr.Set(entry.RawData);
						s.String("_rawData", rawStr);
					}
				}
			}

			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}

	public SerializationResult Read(Scene scene, Serializer s, List<EntityId> loadedEntities)
	{
		s.BeginObject(mData.TypeName);
		int32 count = 0;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			int32 entityIdx = 0;
			s.Int32("entity", ref entityIdx);

			let rawData = scope String();

			// Try to capture the scope's remaining fields (excludes "entity")
			let scopeText = scope String();
			if (s.CaptureScope(scopeText, "entity"))
			{
				// Base64-encode the captured text for storage
				Base64.Encode(Span<uint8>((uint8*)scopeText.Ptr, scopeText.Length), rawData);
			}
			else if (s.HasField("_rawData"))
			{
				// Fallback: read _rawData string directly (legacy format)
				s.String("_rawData", rawData);
			}

			mData.Entries.Add(new MissingEntityEntry(entityIdx, rawData));
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
