namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

class FormationPreset : ISerializable
{
	public String mName = new .() ~ delete _;
	public List<FormationUnitSlot> mSlots = new .() ~ DeleteContainerAndItems!(_);

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.String("Name", mName);
		s.ObjectList("Slots", mSlots);
		return .Ok;
	}
}
