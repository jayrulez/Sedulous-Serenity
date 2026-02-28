namespace Sedulous.RHI;

/// Texture pixel formats.
enum TextureFormat
{
	// No format / undefined
	Undefined = 0,

	// 8-bit formats
	R8Unorm,
	R8Snorm,
	R8Uint,
	R8Sint,

	// 16-bit formats
	R16Uint,
	R16Sint,
	R16Float,
	RG8Unorm,
	RG8Snorm,
	RG8Uint,
	RG8Sint,

	// 32-bit formats
	R32Uint,
	R32Sint,
	R32Float,
	RG16Uint,
	RG16Sint,
	RG16Float,
	RGBA8Unorm,
	RGBA8UnormSrgb,
	RGBA8Snorm,
	RGBA8Uint,
	RGBA8Sint,
	BGRA8Unorm,
	BGRA8UnormSrgb,
	RGB10A2Unorm,
	RG11B10Float,

	// 64-bit formats
	RG32Uint,
	RG32Sint,
	RG32Float,
	RGBA16Uint,
	RGBA16Sint,
	RGBA16Float,

	// 128-bit formats
	RGBA32Uint,
	RGBA32Sint,
	RGBA32Float,

	// Depth/stencil formats
	Depth16Unorm,
	Depth24Plus,
	Depth24PlusStencil8,
	Depth32Float,
	Depth32FloatStencil8,

	// BC compressed formats
	BC1RGBAUnorm,
	BC1RGBAUnormSrgb,
	BC2RGBAUnorm,
	BC2RGBAUnormSrgb,
	BC3RGBAUnorm,
	BC3RGBAUnormSrgb,
	BC4RUnorm,
	BC4RSnorm,
	BC5RGUnorm,
	BC5RGSnorm,
	BC6HRGBUfloat,
	BC6HRGBFloat,
	BC7RGBAUnorm,
	BC7RGBAUnormSrgb,
}
