namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

class FormationUnitSlot : ISerializable
{
	public int32 mUnitId;
	public int32 mGridX;
	public int32 mGridY;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("UnitId", ref mUnitId);
		s.Int32("GridX", ref mGridX);
		s.Int32("GridY", ref mGridY);
		return .Ok;
	}
}
