namespace Sedulous.RHI.Vulkan.Internal;

using Bulkan;
using Sedulous.RHI;

/// Conversion utilities between RHI types and Vulkan types.
static class VulkanConversions
{
	/// Converts RHI TextureFormat to VkFormat.
	public static VkFormat ToVkFormat(TextureFormat format)
	{
		switch (format)
		{
		// Undefined format
		case .Undefined: return .VK_FORMAT_UNDEFINED;

		// 8-bit formats
		case .R8Unorm: return .VK_FORMAT_R8_UNORM;
		case .R8Snorm: return .VK_FORMAT_R8_SNORM;
		case .R8Uint: return .VK_FORMAT_R8_UINT;
		case .R8Sint: return .VK_FORMAT_R8_SINT;

		// 16-bit formats
		case .R16Uint: return .VK_FORMAT_R16_UINT;
		case .R16Sint: return .VK_FORMAT_R16_SINT;
		case .R16Float: return .VK_FORMAT_R16_SFLOAT;
		case .RG8Unorm: return .VK_FORMAT_R8G8_UNORM;
		case .RG8Snorm: return .VK_FORMAT_R8G8_SNORM;
		case .RG8Uint: return .VK_FORMAT_R8G8_UINT;
		case .RG8Sint: return .VK_FORMAT_R8G8_SINT;

		// 32-bit formats
		case .R32Uint: return .VK_FORMAT_R32_UINT;
		case .R32Sint: return .VK_FORMAT_R32_SINT;
		case .R32Float: return .VK_FORMAT_R32_SFLOAT;
		case .RG16Uint: return .VK_FORMAT_R16G16_UINT;
		case .RG16Sint: return .VK_FORMAT_R16G16_SINT;
		case .RG16Float: return .VK_FORMAT_R16G16_SFLOAT;
		case .RGBA8Unorm: return .VK_FORMAT_R8G8B8A8_UNORM;
		case .RGBA8UnormSrgb: return .VK_FORMAT_R8G8B8A8_SRGB;
		case .RGBA8Snorm: return .VK_FORMAT_R8G8B8A8_SNORM;
		case .RGBA8Uint: return .VK_FORMAT_R8G8B8A8_UINT;
		case .RGBA8Sint: return .VK_FORMAT_R8G8B8A8_SINT;
		case .BGRA8Unorm: return .VK_FORMAT_B8G8R8A8_UNORM;
		case .BGRA8UnormSrgb: return .VK_FORMAT_B8G8R8A8_SRGB;
		case .RGB10A2Unorm: return .VK_FORMAT_A2B10G10R10_UNORM_PACK32;
		case .RG11B10Float: return .VK_FORMAT_B10G11R11_UFLOAT_PACK32;

		// 64-bit formats
		case .RG32Uint: return .VK_FORMAT_R32G32_UINT;
		case .RG32Sint: return .VK_FORMAT_R32G32_SINT;
		case .RG32Float: return .VK_FORMAT_R32G32_SFLOAT;
		case .RGBA16Uint: return .VK_FORMAT_R16G16B16A16_UINT;
		case .RGBA16Sint: return .VK_FORMAT_R16G16B16A16_SINT;
		case .RGBA16Float: return .VK_FORMAT_R16G16B16A16_SFLOAT;

		// 128-bit formats
		case .RGBA32Uint: return .VK_FORMAT_R32G32B32A32_UINT;
		case .RGBA32Sint: return .VK_FORMAT_R32G32B32A32_SINT;
		case .RGBA32Float: return .VK_FORMAT_R32G32B32A32_SFLOAT;

		// Depth/stencil formats
		case .Depth16Unorm: return .VK_FORMAT_D16_UNORM;
		case .Depth24Plus: return .VK_FORMAT_D24_UNORM_S8_UINT;
		case .Depth24PlusStencil8: return .VK_FORMAT_D24_UNORM_S8_UINT;
		case .Depth32Float: return .VK_FORMAT_D32_SFLOAT;
		case .Depth32FloatStencil8: return .VK_FORMAT_D32_SFLOAT_S8_UINT;

		// BC compressed formats
		case .BC1RGBAUnorm: return .VK_FORMAT_BC1_RGBA_UNORM_BLOCK;
		case .BC1RGBAUnormSrgb: return .VK_FORMAT_BC1_RGBA_SRGB_BLOCK;
		case .BC2RGBAUnorm: return .VK_FORMAT_BC2_UNORM_BLOCK;
		case .BC2RGBAUnormSrgb: return .VK_FORMAT_BC2_SRGB_BLOCK;
		case .BC3RGBAUnorm: return .VK_FORMAT_BC3_UNORM_BLOCK;
		case .BC3RGBAUnormSrgb: return .VK_FORMAT_BC3_SRGB_BLOCK;
		case .BC4RUnorm: return .VK_FORMAT_BC4_UNORM_BLOCK;
		case .BC4RSnorm: return .VK_FORMAT_BC4_SNORM_BLOCK;
		case .BC5RGUnorm: return .VK_FORMAT_BC5_UNORM_BLOCK;
		case .BC5RGSnorm: return .VK_FORMAT_BC5_SNORM_BLOCK;
		case .BC6HRGBUfloat: return .VK_FORMAT_BC6H_UFLOAT_BLOCK;
		case .BC6HRGBFloat: return .VK_FORMAT_BC6H_SFLOAT_BLOCK;
		case .BC7RGBAUnorm: return .VK_FORMAT_BC7_UNORM_BLOCK;
		case .BC7RGBAUnormSrgb: return .VK_FORMAT_BC7_SRGB_BLOCK;

		default: return .VK_FORMAT_UNDEFINED;
		}
	}

	/// Converts RHI BufferUsage to VkBufferUsageFlags.
	public static VkBufferUsageFlags ToVkBufferUsage(BufferUsage usage)
	{
		VkBufferUsageFlags flags = 0;

		if ((usage & .CopySrc) != 0)
			flags |= .VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
		if ((usage & .CopyDst) != 0)
			flags |= .VK_BUFFER_USAGE_TRANSFER_DST_BIT;
		if ((usage & .Vertex) != 0)
			flags |= .VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
		if ((usage & .Index) != 0)
			flags |= .VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
		if ((usage & .Uniform) != 0)
			flags |= .VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
		if ((usage & .Storage) != 0)
			flags |= .VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
		if ((usage & .Indirect) != 0)
			flags |= .VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;

		return flags;
	}

	/// Converts RHI TextureUsage to VkImageUsageFlags.
	public static VkImageUsageFlags ToVkImageUsage(TextureUsage usage)
	{
		VkImageUsageFlags flags = 0;

		if ((usage & .CopySrc) != 0)
			flags |= .VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
		if ((usage & .CopyDst) != 0)
			flags |= .VK_IMAGE_USAGE_TRANSFER_DST_BIT;
		if ((usage & .Sampled) != 0)
			flags |= .VK_IMAGE_USAGE_SAMPLED_BIT;
		if ((usage & .Storage) != 0)
			flags |= .VK_IMAGE_USAGE_STORAGE_BIT;
		if ((usage & .RenderTarget) != 0)
			flags |= .VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
		if ((usage & .DepthStencil) != 0)
			flags |= .VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;

		return flags;
	}

	/// Converts RHI TextureDimension to VkImageType.
	public static VkImageType ToVkImageType(TextureDimension dimension)
	{
		switch (dimension)
		{
		case .Texture1D: return .VK_IMAGE_TYPE_1D;
		case .Texture2D: return .VK_IMAGE_TYPE_2D;
		case .Texture3D: return .VK_IMAGE_TYPE_3D;
		default: return .VK_IMAGE_TYPE_2D;
		}
	}

	/// Converts RHI TextureViewDimension to VkImageViewType.
	public static VkImageViewType ToVkImageViewType(TextureViewDimension dimension)
	{
		switch (dimension)
		{
		case .Texture1D: return .VK_IMAGE_VIEW_TYPE_1D;
		case .Texture2D: return .VK_IMAGE_VIEW_TYPE_2D;
		case .Texture2DArray: return .VK_IMAGE_VIEW_TYPE_2D_ARRAY;
		case .TextureCube: return .VK_IMAGE_VIEW_TYPE_CUBE;
		case .TextureCubeArray: return .VK_IMAGE_VIEW_TYPE_CUBE_ARRAY;
		case .Texture3D: return .VK_IMAGE_VIEW_TYPE_3D;
		default: return .VK_IMAGE_VIEW_TYPE_2D;
		}
	}

	/// Converts RHI FilterMode to VkFilter.
	public static VkFilter ToVkFilter(FilterMode mode)
	{
		switch (mode)
		{
		case .Nearest: return .VK_FILTER_NEAREST;
		case .Linear: return .VK_FILTER_LINEAR;
		default: return .VK_FILTER_LINEAR;
		}
	}

	/// Converts RHI FilterMode to VkSamplerMipmapMode.
	public static VkSamplerMipmapMode ToVkSamplerMipmapMode(FilterMode mode)
	{
		switch (mode)
		{
		case .Nearest: return .VK_SAMPLER_MIPMAP_MODE_NEAREST;
		case .Linear: return .VK_SAMPLER_MIPMAP_MODE_LINEAR;
		default: return .VK_SAMPLER_MIPMAP_MODE_LINEAR;
		}
	}

	/// Converts RHI AddressMode to VkSamplerAddressMode.
	public static VkSamplerAddressMode ToVkSamplerAddressMode(AddressMode mode)
	{
		switch (mode)
		{
		case .Repeat: return .VK_SAMPLER_ADDRESS_MODE_REPEAT;
		case .MirrorRepeat: return .VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT;
		case .ClampToEdge: return .VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
		case .ClampToBorder: return .VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER;
		default: return .VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
		}
	}

	/// Converts RHI CompareFunction to VkCompareOp.
	public static VkCompareOp ToVkCompareOp(CompareFunction func)
	{
		switch (func)
		{
		case .Never: return .VK_COMPARE_OP_NEVER;
		case .Less: return .VK_COMPARE_OP_LESS;
		case .Equal: return .VK_COMPARE_OP_EQUAL;
		case .LessEqual: return .VK_COMPARE_OP_LESS_OR_EQUAL;
		case .Greater: return .VK_COMPARE_OP_GREATER;
		case .NotEqual: return .VK_COMPARE_OP_NOT_EQUAL;
		case .GreaterEqual: return .VK_COMPARE_OP_GREATER_OR_EQUAL;
		case .Always: return .VK_COMPARE_OP_ALWAYS;
		default: return .VK_COMPARE_OP_ALWAYS;
		}
	}

	/// Converts RHI MemoryAccess to VkMemoryPropertyFlags.
	public static VkMemoryPropertyFlags ToVkMemoryProperties(MemoryAccess access)
	{
		switch (access)
		{
		case .GpuOnly:
			return .VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
		case .Upload:
			return .VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | .VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
		case .Readback:
			return .VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | .VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | .VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
		default:
			return .VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
		}
	}

	/// Checks if a format has a depth component.
	public static bool HasDepthComponent(TextureFormat format)
	{
		switch (format)
		{
		case .Depth16Unorm, .Depth24Plus, .Depth24PlusStencil8, .Depth32Float, .Depth32FloatStencil8:
			return true;
		default:
			return false;
		}
	}

	/// Checks if a format has a stencil component.
	public static bool HasStencilComponent(TextureFormat format)
	{
		switch (format)
		{
		case .Depth24PlusStencil8, .Depth32FloatStencil8:
			return true;
		default:
			return false;
		}
	}

	/// Gets the VkImageAspectFlags for a format.
	public static VkImageAspectFlags GetAspectFlags(TextureFormat format)
	{
		if (HasDepthComponent(format) && HasStencilComponent(format))
			return .VK_IMAGE_ASPECT_DEPTH_BIT | .VK_IMAGE_ASPECT_STENCIL_BIT;
		else if (HasDepthComponent(format))
			return .VK_IMAGE_ASPECT_DEPTH_BIT;
		else
			return .VK_IMAGE_ASPECT_COLOR_BIT;
	}

	/// Gets the VkImageAspectFlags for a format with explicit aspect selection.
	/// For sampled depth/stencil views, use DepthOnly or StencilOnly aspect.
	public static VkImageAspectFlags GetAspectFlags(TextureFormat format, TextureAspect aspect)
	{
		switch (aspect)
		{
		case .DepthOnly:
			return .VK_IMAGE_ASPECT_DEPTH_BIT;
		case .StencilOnly:
			return .VK_IMAGE_ASPECT_STENCIL_BIT;
		case .All:
			return GetAspectFlags(format);
		}
	}

	/// Converts RHI BindingType to VkDescriptorType.
	public static VkDescriptorType ToVkDescriptorType(BindingType type)
	{
		switch (type)
		{
		case .UniformBuffer: return .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		case .StorageBuffer, .StorageBufferReadWrite: return .VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
		case .SampledTexture: return .VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
		case .StorageTexture, .StorageTextureReadWrite: return .VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
		case .Sampler: return .VK_DESCRIPTOR_TYPE_SAMPLER;
		case .ComparisonSampler: return .VK_DESCRIPTOR_TYPE_SAMPLER;
		default: return .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		}
	}

	/// Converts RHI BindingType to VkDescriptorType with dynamic offset support.
	public static VkDescriptorType ToVkDescriptorType(BindingType type, bool hasDynamicOffset)
	{
		switch (type)
		{
		case .UniformBuffer:
			return hasDynamicOffset ? .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC : .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		case .StorageBuffer, .StorageBufferReadWrite:
			return hasDynamicOffset ? .VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC : .VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
		case .SampledTexture: return .VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
		case .StorageTexture, .StorageTextureReadWrite: return .VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
		case .Sampler: return .VK_DESCRIPTOR_TYPE_SAMPLER;
		case .ComparisonSampler: return .VK_DESCRIPTOR_TYPE_SAMPLER;
		default: return .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		}
	}

	/// Converts RHI ShaderStage to VkShaderStageFlags.
	public static VkShaderStageFlags ToVkShaderStage(ShaderStage stage)
	{
		VkShaderStageFlags flags = 0;
		if ((stage & .Vertex) != 0)
			flags |= .VK_SHADER_STAGE_VERTEX_BIT;
		if ((stage & .Fragment) != 0)
			flags |= .VK_SHADER_STAGE_FRAGMENT_BIT;
		if ((stage & .Compute) != 0)
			flags |= .VK_SHADER_STAGE_COMPUTE_BIT;
		return flags;
	}

	/// Converts RHI PrimitiveTopology to VkPrimitiveTopology.
	public static VkPrimitiveTopology ToVkPrimitiveTopology(PrimitiveTopology topology)
	{
		switch (topology)
		{
		case .PointList: return .VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
		case .LineList: return .VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
		case .LineStrip: return .VK_PRIMITIVE_TOPOLOGY_LINE_STRIP;
		case .TriangleList: return .VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
		case .TriangleStrip: return .VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
		default: return .VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
		}
	}

	/// Converts RHI CullMode to VkCullModeFlags.
	public static VkCullModeFlags ToVkCullMode(CullMode mode)
	{
		switch (mode)
		{
		case .None: return .VK_CULL_MODE_NONE;
		case .Front: return .VK_CULL_MODE_FRONT_BIT;
		case .Back: return .VK_CULL_MODE_BACK_BIT;
		default: return .VK_CULL_MODE_BACK_BIT;
		}
	}

	/// Converts RHI FrontFace to VkFrontFace.
	public static VkFrontFace ToVkFrontFace(FrontFace face)
	{
		switch (face)
		{
		case .CCW: return .VK_FRONT_FACE_COUNTER_CLOCKWISE;
		case .CW: return .VK_FRONT_FACE_CLOCKWISE;
		default: return .VK_FRONT_FACE_COUNTER_CLOCKWISE;
		}
	}

	/// Converts RHI FillMode to VkPolygonMode.
	public static VkPolygonMode ToVkPolygonMode(FillMode mode)
	{
		switch (mode)
		{
		case .Solid: return .VK_POLYGON_MODE_FILL;
		case .Wireframe: return .VK_POLYGON_MODE_LINE;
		default: return .VK_POLYGON_MODE_FILL;
		}
	}

	/// Converts RHI BlendFactor to VkBlendFactor.
	public static VkBlendFactor ToVkBlendFactor(BlendFactor factor)
	{
		switch (factor)
		{
		case .Zero: return .VK_BLEND_FACTOR_ZERO;
		case .One: return .VK_BLEND_FACTOR_ONE;
		case .Src: return .VK_BLEND_FACTOR_SRC_COLOR;
		case .OneMinusSrc: return .VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR;
		case .SrcAlpha: return .VK_BLEND_FACTOR_SRC_ALPHA;
		case .OneMinusSrcAlpha: return .VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
		case .Dst: return .VK_BLEND_FACTOR_DST_COLOR;
		case .OneMinusDst: return .VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR;
		case .DstAlpha: return .VK_BLEND_FACTOR_DST_ALPHA;
		case .OneMinusDstAlpha: return .VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA;
		case .SrcAlphaSaturated: return .VK_BLEND_FACTOR_SRC_ALPHA_SATURATE;
		case .Constant: return .VK_BLEND_FACTOR_CONSTANT_COLOR;
		case .OneMinusConstant: return .VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR;
		default: return .VK_BLEND_FACTOR_ONE;
		}
	}

	/// Converts RHI BlendOperation to VkBlendOp.
	public static VkBlendOp ToVkBlendOp(BlendOperation op)
	{
		switch (op)
		{
		case .Add: return .VK_BLEND_OP_ADD;
		case .Subtract: return .VK_BLEND_OP_SUBTRACT;
		case .ReverseSubtract: return .VK_BLEND_OP_REVERSE_SUBTRACT;
		case .Min: return .VK_BLEND_OP_MIN;
		case .Max: return .VK_BLEND_OP_MAX;
		default: return .VK_BLEND_OP_ADD;
		}
	}

	/// Converts RHI StencilOperation to VkStencilOp.
	public static VkStencilOp ToVkStencilOp(StencilOperation op)
	{
		switch (op)
		{
		case .Keep: return .VK_STENCIL_OP_KEEP;
		case .Zero: return .VK_STENCIL_OP_ZERO;
		case .Replace: return .VK_STENCIL_OP_REPLACE;
		case .IncrementClamp: return .VK_STENCIL_OP_INCREMENT_AND_CLAMP;
		case .DecrementClamp: return .VK_STENCIL_OP_DECREMENT_AND_CLAMP;
		case .Invert: return .VK_STENCIL_OP_INVERT;
		case .IncrementWrap: return .VK_STENCIL_OP_INCREMENT_AND_WRAP;
		case .DecrementWrap: return .VK_STENCIL_OP_DECREMENT_AND_WRAP;
		default: return .VK_STENCIL_OP_KEEP;
		}
	}

	/// Converts RHI ColorWriteMask to VkColorComponentFlags.
	public static VkColorComponentFlags ToVkColorWriteMask(ColorWriteMask mask)
	{
		VkColorComponentFlags flags = 0;
		if ((mask & .Red) != 0)
			flags |= .VK_COLOR_COMPONENT_R_BIT;
		if ((mask & .Green) != 0)
			flags |= .VK_COLOR_COMPONENT_G_BIT;
		if ((mask & .Blue) != 0)
			flags |= .VK_COLOR_COMPONENT_B_BIT;
		if ((mask & .Alpha) != 0)
			flags |= .VK_COLOR_COMPONENT_A_BIT;
		return flags;
	}

	/// Converts RHI VertexFormat to VkFormat.
	public static VkFormat ToVkVertexFormat(VertexFormat format)
	{
		switch (format)
		{
		// 8-bit formats
		case .UByte2: return .VK_FORMAT_R8G8_UINT;
		case .UByte4: return .VK_FORMAT_R8G8B8A8_UINT;
		case .Byte2: return .VK_FORMAT_R8G8_SINT;
		case .Byte4: return .VK_FORMAT_R8G8B8A8_SINT;
		case .UByte2Normalized: return .VK_FORMAT_R8G8_UNORM;
		case .UByte4Normalized: return .VK_FORMAT_R8G8B8A8_UNORM;
		case .Byte2Normalized: return .VK_FORMAT_R8G8_SNORM;
		case .Byte4Normalized: return .VK_FORMAT_R8G8B8A8_SNORM;

		// 16-bit formats
		case .UShort2: return .VK_FORMAT_R16G16_UINT;
		case .UShort4: return .VK_FORMAT_R16G16B16A16_UINT;
		case .Short2: return .VK_FORMAT_R16G16_SINT;
		case .Short4: return .VK_FORMAT_R16G16B16A16_SINT;
		case .UShort2Normalized: return .VK_FORMAT_R16G16_UNORM;
		case .UShort4Normalized: return .VK_FORMAT_R16G16B16A16_UNORM;
		case .Short2Normalized: return .VK_FORMAT_R16G16_SNORM;
		case .Short4Normalized: return .VK_FORMAT_R16G16B16A16_SNORM;
		case .Half2: return .VK_FORMAT_R16G16_SFLOAT;
		case .Half4: return .VK_FORMAT_R16G16B16A16_SFLOAT;

		// 32-bit formats
		case .Float: return .VK_FORMAT_R32_SFLOAT;
		case .Float2: return .VK_FORMAT_R32G32_SFLOAT;
		case .Float3: return .VK_FORMAT_R32G32B32_SFLOAT;
		case .Float4: return .VK_FORMAT_R32G32B32A32_SFLOAT;
		case .UInt: return .VK_FORMAT_R32_UINT;
		case .UInt2: return .VK_FORMAT_R32G32_UINT;
		case .UInt3: return .VK_FORMAT_R32G32B32_UINT;
		case .UInt4: return .VK_FORMAT_R32G32B32A32_UINT;
		case .Int: return .VK_FORMAT_R32_SINT;
		case .Int2: return .VK_FORMAT_R32G32_SINT;
		case .Int3: return .VK_FORMAT_R32G32B32_SINT;
		case .Int4: return .VK_FORMAT_R32G32B32A32_SINT;

		default: return .VK_FORMAT_R32G32B32_SFLOAT;
		}
	}

	/// Converts RHI VertexStepMode to VkVertexInputRate.
	public static VkVertexInputRate ToVkVertexInputRate(VertexStepMode mode)
	{
		switch (mode)
		{
		case .Vertex: return .VK_VERTEX_INPUT_RATE_VERTEX;
		case .Instance: return .VK_VERTEX_INPUT_RATE_INSTANCE;
		default: return .VK_VERTEX_INPUT_RATE_VERTEX;
		}
	}

	/// Gets the VkSampleCountFlags for a sample count.
	public static VkSampleCountFlags ToVkSampleCount(uint32 count)
	{
		switch (count)
		{
		case 1: return .VK_SAMPLE_COUNT_1_BIT;
		case 2: return .VK_SAMPLE_COUNT_2_BIT;
		case 4: return .VK_SAMPLE_COUNT_4_BIT;
		case 8: return .VK_SAMPLE_COUNT_8_BIT;
		case 16: return .VK_SAMPLE_COUNT_16_BIT;
		case 32: return .VK_SAMPLE_COUNT_32_BIT;
		case 64: return .VK_SAMPLE_COUNT_64_BIT;
		default: return .VK_SAMPLE_COUNT_1_BIT;
		}
	}

	/// Converts RHI PresentMode to VkPresentModeKHR.
	public static VkPresentModeKHR ToVkPresentMode(PresentMode mode)
	{
		switch (mode)
		{
		case .Immediate: return .VK_PRESENT_MODE_IMMEDIATE_KHR;
		case .Fifo: return .VK_PRESENT_MODE_FIFO_KHR;
		case .Mailbox: return .VK_PRESENT_MODE_MAILBOX_KHR;
		default: return .VK_PRESENT_MODE_FIFO_KHR;
		}
	}

	/// Converts VkFormat to RHI TextureFormat (reverse conversion).
	public static TextureFormat ToTextureFormat(VkFormat format)
	{
		switch (format)
		{
		// 8-bit formats
		case .VK_FORMAT_R8_UNORM: return .R8Unorm;
		case .VK_FORMAT_R8_SNORM: return .R8Snorm;
		case .VK_FORMAT_R8_UINT: return .R8Uint;
		case .VK_FORMAT_R8_SINT: return .R8Sint;

		// 16-bit formats
		case .VK_FORMAT_R16_UINT: return .R16Uint;
		case .VK_FORMAT_R16_SINT: return .R16Sint;
		case .VK_FORMAT_R16_SFLOAT: return .R16Float;
		case .VK_FORMAT_R8G8_UNORM: return .RG8Unorm;
		case .VK_FORMAT_R8G8_SNORM: return .RG8Snorm;
		case .VK_FORMAT_R8G8_UINT: return .RG8Uint;
		case .VK_FORMAT_R8G8_SINT: return .RG8Sint;

		// 32-bit formats
		case .VK_FORMAT_R32_UINT: return .R32Uint;
		case .VK_FORMAT_R32_SINT: return .R32Sint;
		case .VK_FORMAT_R32_SFLOAT: return .R32Float;
		case .VK_FORMAT_R16G16_UINT: return .RG16Uint;
		case .VK_FORMAT_R16G16_SINT: return .RG16Sint;
		case .VK_FORMAT_R16G16_SFLOAT: return .RG16Float;
		case .VK_FORMAT_R8G8B8A8_UNORM: return .RGBA8Unorm;
		case .VK_FORMAT_R8G8B8A8_SRGB: return .RGBA8UnormSrgb;
		case .VK_FORMAT_R8G8B8A8_SNORM: return .RGBA8Snorm;
		case .VK_FORMAT_R8G8B8A8_UINT: return .RGBA8Uint;
		case .VK_FORMAT_R8G8B8A8_SINT: return .RGBA8Sint;
		case .VK_FORMAT_B8G8R8A8_UNORM: return .BGRA8Unorm;
		case .VK_FORMAT_B8G8R8A8_SRGB: return .BGRA8UnormSrgb;
		case .VK_FORMAT_A2B10G10R10_UNORM_PACK32: return .RGB10A2Unorm;
		case .VK_FORMAT_B10G11R11_UFLOAT_PACK32: return .RG11B10Float;

		// 64-bit formats
		case .VK_FORMAT_R32G32_UINT: return .RG32Uint;
		case .VK_FORMAT_R32G32_SINT: return .RG32Sint;
		case .VK_FORMAT_R32G32_SFLOAT: return .RG32Float;
		case .VK_FORMAT_R16G16B16A16_UINT: return .RGBA16Uint;
		case .VK_FORMAT_R16G16B16A16_SINT: return .RGBA16Sint;
		case .VK_FORMAT_R16G16B16A16_SFLOAT: return .RGBA16Float;

		// 128-bit formats
		case .VK_FORMAT_R32G32B32A32_UINT: return .RGBA32Uint;
		case .VK_FORMAT_R32G32B32A32_SINT: return .RGBA32Sint;
		case .VK_FORMAT_R32G32B32A32_SFLOAT: return .RGBA32Float;

		// Depth/stencil formats
		case .VK_FORMAT_D16_UNORM: return .Depth16Unorm;
		case .VK_FORMAT_D24_UNORM_S8_UINT: return .Depth24PlusStencil8;
		case .VK_FORMAT_D32_SFLOAT: return .Depth32Float;
		case .VK_FORMAT_D32_SFLOAT_S8_UINT: return .Depth32FloatStencil8;

		// Default to BGRA8 (common swap chain format)
		default: return .BGRA8Unorm;
		}
	}

	/// Converts RHI SamplerBorderColor to VkBorderColor.
	public static VkBorderColor ToVkBorderColor(SamplerBorderColor color)
	{
		switch (color)
		{
		case .TransparentBlack: return .VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK;
		case .OpaqueBlack: return .VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK;
		case .OpaqueWhite: return .VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE;
		default: return .VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK;
		}
	}
}
