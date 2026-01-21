using Sedulous.Resources;
using System;
using Sedulous.Serialization;
namespace Sedulous.Materials.Resources;

class MaterialResource : Resource
{
	public const int32 FileVersion = 1;
	public String ShaderName = new .() ~ delete _;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		return .Ok;
	}
}