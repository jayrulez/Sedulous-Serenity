using System;
namespace Sedulous.RHI;

/// Describes a texture sampler.
struct SamplerDescriptor
{
	/// Minification filter.
	public FilterMode MinFilter;
	/// Magnification filter.
	public FilterMode MagFilter;
	/// Mipmap filter.
	public FilterMode MipmapFilter;
	/// Address mode for U coordinate.
	public AddressMode AddressModeU;
	/// Address mode for V coordinate.
	public AddressMode AddressModeV;
	/// Address mode for W coordinate.
	public AddressMode AddressModeW;
	/// LOD clamp minimum.
	public float LodMinClamp;
	/// LOD clamp maximum.
	public float LodMaxClamp;
	/// Comparison function for comparison samplers.
	public CompareFunction Compare;
	/// Maximum anisotropy level (1 = no anisotropic filtering).
	public uint16 MaxAnisotropy;
	/// Border color used when address mode is ClampToBorder.
	public SamplerBorderColor BorderColor;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		MinFilter = .Linear;
		MagFilter = .Linear;
		MipmapFilter = .Linear;
		AddressModeU = .ClampToEdge;
		AddressModeV = .ClampToEdge;
		AddressModeW = .ClampToEdge;
		LodMinClamp = 0.0f;
		LodMaxClamp = 1000.0f;
		Compare = .Always;
		MaxAnisotropy = 1;
		BorderColor = .TransparentBlack;
		Label = default;
	}

	/// Creates a linear sampler with repeat wrapping.
	public static Self LinearRepeat()
	{
		Self desc = .();
		desc.AddressModeU = .Repeat;
		desc.AddressModeV = .Repeat;
		desc.AddressModeW = .Repeat;
		return desc;
	}

	/// Creates a nearest-neighbor sampler with clamp-to-edge.
	public static Self NearestClamp()
	{
		Self desc = .();
		desc.MinFilter = .Nearest;
		desc.MagFilter = .Nearest;
		desc.MipmapFilter = .Nearest;
		return desc;
	}
}
