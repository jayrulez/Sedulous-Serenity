namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

/// A stat modification: flat amount or percentage bonus on a given attribute.
class StatModifier : ISerializable
{
	public StatAttribute mAttribute;
	public float mFlatValue;
	public float mPercentValue;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Enum("Attribute", ref mAttribute);
		s.Float("FlatValue", ref mFlatValue);
		s.Float("PercentValue", ref mPercentValue);
		return .Ok;
	}
}
