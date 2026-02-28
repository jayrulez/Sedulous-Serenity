namespace Sedulous.Engine.Scenes;

using System;
using System.Collections;
using Sedulous.Serialization;

/// Serializer for component types that have no registered IComponentSerializer.
/// During reading, captures entity indices and raw data (stubbed pending base64).
/// During writing, replays the captured data.
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
			let rawStr = scope String();
			rawStr.Set(entry.RawData);
			s.String("_rawData", rawStr);
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

			let rawStr = scope String();
			if (s.HasField("_rawData"))
				s.String("_rawData", rawStr);

			mData.Entries.Add(new MissingEntityEntry(entityIdx, rawStr));
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
