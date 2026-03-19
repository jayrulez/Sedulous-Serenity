using System;
namespace Sedulous.RHI;

/// Describes a texture sampler.
struct SamplerDesc
{
	/// Minification filter.
	public FilterMode MinFilter;
	/// Magnification filter.
	public FilterMode MagFilter;
	/// Mipmap filter.
	public FilterMode MipmapFilter;
	/// Address mode for U coordinate.
	public AddressMode AddressU;
	/// Address mode for V coordinate.
	public AddressMode AddressV;
	/// Address mode for W coordinate.
	public AddressMode AddressW;
	/// LOD clamp minimum.
	public float MinLod;
	/// LOD clamp maximum.
	public float MaxLod;
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
		AddressU = .ClampToEdge;
		AddressV = .ClampToEdge;
		AddressW = .ClampToEdge;
		MinLod = 0.0f;
		MaxLod = 1000.0f;
		Compare = .Always;
		MaxAnisotropy = 1;
		BorderColor = .TransparentBlack;
		Label = default;
	}

	/// Creates a linear sampler with repeat wrapping.
	public static Self LinearRepeat()
	{
		Self desc = .();
		desc.AddressU = .Repeat;
		desc.AddressV = .Repeat;
		desc.AddressW = .Repeat;
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
