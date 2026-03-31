namespace Sedulous.Renderer;

using System;

/// Types of material properties.
public enum MaterialPropertyType
{
	Float,
	Float2,
	Float3,
	Float4,
	Int,
	Color,
	Texture2D,
	TextureCube,
	Sampler,
}

/// Descriptor for a single material property.
/// Scalar properties (Float..Color) are packed into the material UBO.
/// Texture/Sampler properties map to bind group entries.
public struct MaterialProperty
{
	/// Property name (for lookup and shader binding).
	public StringView Name;
	/// Property type.
	public MaterialPropertyType Type;
	/// Byte offset within the material UBO (scalar types only).
	public uint32 ByteOffset;
	/// Binding slot in the material bind group (texture/sampler types only).
	public uint32 BindingSlot;

	/// Returns the byte size of this property type in the UBO.
	public static uint32 GetTypeSize(MaterialPropertyType type)
	{
		switch (type)
		{
		case .Float:      return 4;
		case .Float2:     return 8;
		case .Float3:     return 12;
		case .Float4:     return 16;
		case .Int:        return 4;
		case .Color:      return 16;
		case .Texture2D:  return 0;
		case .TextureCube: return 0;
		case .Sampler:    return 0;
		}
	}

	/// Returns true if this property type lives in the UBO.
	public static bool IsScalar(MaterialPropertyType type)
	{
		return type != .Texture2D && type != .TextureCube && type != .Sampler;
	}
}
