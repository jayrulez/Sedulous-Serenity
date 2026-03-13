namespace Sedulous.RHI.DX12.Internal;

using Win32.Graphics.Dxgi.Common;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Direct3D;
using Sedulous.RHI;
using System;

/// Conversion utilities between RHI types and D3D12/DXGI types.
static class DX12Conversions
{
	// ===== Texture Format =====

	public static DXGI_FORMAT ToDxgiFormat(TextureFormat format)
	{
		switch (format)
		{
		case .Undefined:             return .DXGI_FORMAT_UNKNOWN;
		case .R8Unorm:               return .DXGI_FORMAT_R8_UNORM;
		case .R8Snorm:               return .DXGI_FORMAT_R8_SNORM;
		case .R8Uint:                return .DXGI_FORMAT_R8_UINT;
		case .R8Sint:                return .DXGI_FORMAT_R8_SINT;
		case .R16Uint:               return .DXGI_FORMAT_R16_UINT;
		case .R16Sint:               return .DXGI_FORMAT_R16_SINT;
		case .R16Float:              return .DXGI_FORMAT_R16_FLOAT;
		case .RG8Unorm:              return .DXGI_FORMAT_R8G8_UNORM;
		case .RG8Snorm:              return .DXGI_FORMAT_R8G8_SNORM;
		case .RG8Uint:               return .DXGI_FORMAT_R8G8_UINT;
		case .RG8Sint:               return .DXGI_FORMAT_R8G8_SINT;
		case .R32Uint:               return .DXGI_FORMAT_R32_UINT;
		case .R32Sint:               return .DXGI_FORMAT_R32_SINT;
		case .R32Float:              return .DXGI_FORMAT_R32_FLOAT;
		case .RG16Uint:              return .DXGI_FORMAT_R16G16_UINT;
		case .RG16Sint:              return .DXGI_FORMAT_R16G16_SINT;
		case .RG16Float:             return .DXGI_FORMAT_R16G16_FLOAT;
		case .RGBA8Unorm:            return .DXGI_FORMAT_R8G8B8A8_UNORM;
		case .RGBA8UnormSrgb:        return .DXGI_FORMAT_R8G8B8A8_UNORM_SRGB;
		case .RGBA8Snorm:            return .DXGI_FORMAT_R8G8B8A8_SNORM;
		case .RGBA8Uint:             return .DXGI_FORMAT_R8G8B8A8_UINT;
		case .RGBA8Sint:             return .DXGI_FORMAT_R8G8B8A8_SINT;
		case .BGRA8Unorm:            return .DXGI_FORMAT_B8G8R8A8_UNORM;
		case .BGRA8UnormSrgb:        return .DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;
		case .RGB10A2Unorm:          return .DXGI_FORMAT_R10G10B10A2_UNORM;
		case .RG11B10Float:          return .DXGI_FORMAT_R11G11B10_FLOAT;
		case .RG32Uint:              return .DXGI_FORMAT_R32G32_UINT;
		case .RG32Sint:              return .DXGI_FORMAT_R32G32_SINT;
		case .RG32Float:             return .DXGI_FORMAT_R32G32_FLOAT;
		case .RGBA16Uint:            return .DXGI_FORMAT_R16G16B16A16_UINT;
		case .RGBA16Sint:            return .DXGI_FORMAT_R16G16B16A16_SINT;
		case .RGBA16Float:           return .DXGI_FORMAT_R16G16B16A16_FLOAT;
		case .RGBA32Uint:            return .DXGI_FORMAT_R32G32B32A32_UINT;
		case .RGBA32Sint:            return .DXGI_FORMAT_R32G32B32A32_SINT;
		case .RGBA32Float:           return .DXGI_FORMAT_R32G32B32A32_FLOAT;
		case .Depth16Unorm:          return .DXGI_FORMAT_D16_UNORM;
		case .Depth24Plus:           return .DXGI_FORMAT_D24_UNORM_S8_UINT;
		case .Depth24PlusStencil8:   return .DXGI_FORMAT_D24_UNORM_S8_UINT;
		case .Depth32Float:          return .DXGI_FORMAT_D32_FLOAT;
		case .Depth32FloatStencil8:  return .DXGI_FORMAT_D32_FLOAT_S8X24_UINT;
		case .BC1RGBAUnorm:          return .DXGI_FORMAT_BC1_UNORM;
		case .BC1RGBAUnormSrgb:      return .DXGI_FORMAT_BC1_UNORM_SRGB;
		case .BC2RGBAUnorm:          return .DXGI_FORMAT_BC2_UNORM;
		case .BC2RGBAUnormSrgb:      return .DXGI_FORMAT_BC2_UNORM_SRGB;
		case .BC3RGBAUnorm:          return .DXGI_FORMAT_BC3_UNORM;
		case .BC3RGBAUnormSrgb:      return .DXGI_FORMAT_BC3_UNORM_SRGB;
		case .BC4RUnorm:             return .DXGI_FORMAT_BC4_UNORM;
		case .BC4RSnorm:             return .DXGI_FORMAT_BC4_SNORM;
		case .BC5RGUnorm:            return .DXGI_FORMAT_BC5_UNORM;
		case .BC5RGSnorm:            return .DXGI_FORMAT_BC5_SNORM;
		case .BC6HRGBUfloat:         return .DXGI_FORMAT_BC6H_UF16;
		case .BC6HRGBFloat:          return .DXGI_FORMAT_BC6H_SF16;
		case .BC7RGBAUnorm:          return .DXGI_FORMAT_BC7_UNORM;
		case .BC7RGBAUnormSrgb:      return .DXGI_FORMAT_BC7_UNORM_SRGB;
		default:                     return .DXGI_FORMAT_UNKNOWN;
		}
	}

	public static TextureFormat FromDxgiFormat(DXGI_FORMAT format)
	{
		switch (format)
		{
		case .DXGI_FORMAT_R8G8B8A8_UNORM:        return .RGBA8Unorm;
		case .DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:   return .RGBA8UnormSrgb;
		case .DXGI_FORMAT_B8G8R8A8_UNORM:        return .BGRA8Unorm;
		case .DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:   return .BGRA8UnormSrgb;
		case .DXGI_FORMAT_R16G16B16A16_FLOAT:    return .RGBA16Float;
		case .DXGI_FORMAT_R10G10B10A2_UNORM:     return .RGB10A2Unorm;
		default:                                  return .Undefined;
		}
	}

	/// Gets the typeless format for depth textures that need both DSV + SRV.
	public static DXGI_FORMAT GetTypelessDepthFormat(TextureFormat format)
	{
		switch (format)
		{
		case .Depth16Unorm:          return .DXGI_FORMAT_R16_TYPELESS;
		case .Depth24Plus,
			 .Depth24PlusStencil8:   return .DXGI_FORMAT_R24G8_TYPELESS;
		case .Depth32Float:          return .DXGI_FORMAT_R32_TYPELESS;
		case .Depth32FloatStencil8:  return .DXGI_FORMAT_R32G8X24_TYPELESS;
		default:                     return ToDxgiFormat(format);
		}
	}

	/// Gets the SRV format for a depth texture (for sampling in shaders).
	public static DXGI_FORMAT GetDepthSrvFormat(TextureFormat format)
	{
		switch (format)
		{
		case .Depth16Unorm:          return .DXGI_FORMAT_R16_UNORM;
		case .Depth24Plus,
			 .Depth24PlusStencil8:   return .DXGI_FORMAT_R24_UNORM_X8_TYPELESS;
		case .Depth32Float:          return .DXGI_FORMAT_R32_FLOAT;
		case .Depth32FloatStencil8:  return .DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS;
		default:                     return ToDxgiFormat(format);
		}
	}

	/// Gets the DSV format for a depth texture.
	public static DXGI_FORMAT GetDepthDsvFormat(TextureFormat format)
	{
		return ToDxgiFormat(format);
	}

	public static bool IsDepthFormat(TextureFormat format)
	{
		switch (format)
		{
		case .Depth16Unorm, .Depth24Plus, .Depth24PlusStencil8,
			 .Depth32Float, .Depth32FloatStencil8:
			return true;
		default:
			return false;
		}
	}

	public static bool HasStencil(TextureFormat format)
	{
		switch (format)
		{
		case .Depth24PlusStencil8, .Depth32FloatStencil8:
			return true;
		default:
			return false;
		}
	}

	public static uint32 GetFormatBytesPerPixel(TextureFormat format)
	{
		switch (format)
		{
		case .R8Unorm, .R8Snorm, .R8Uint, .R8Sint:
			return 1;
		case .R16Uint, .R16Sint, .R16Float, .RG8Unorm, .RG8Snorm, .RG8Uint, .RG8Sint, .Depth16Unorm:
			return 2;
		case .R32Uint, .R32Sint, .R32Float, .RG16Uint, .RG16Sint, .RG16Float,
			 .RGBA8Unorm, .RGBA8UnormSrgb, .RGBA8Snorm, .RGBA8Uint, .RGBA8Sint,
			 .BGRA8Unorm, .BGRA8UnormSrgb, .RGB10A2Unorm, .RG11B10Float,
			 .Depth24Plus, .Depth24PlusStencil8, .Depth32Float:
			return 4;
		case .RG32Uint, .RG32Sint, .RG32Float, .RGBA16Uint, .RGBA16Sint, .RGBA16Float,
			 .Depth32FloatStencil8:
			return 8;
		case .RGBA32Uint, .RGBA32Sint, .RGBA32Float:
			return 16;
		default:
			return 4;
		}
	}

	// ===== Vertex Format =====

	public static DXGI_FORMAT ToDxgiFormat(VertexFormat format)
	{
		switch (format)
		{
		case .UByte2:             return .DXGI_FORMAT_R8G8_UINT;
		case .UByte4:             return .DXGI_FORMAT_R8G8B8A8_UINT;
		case .Byte2:              return .DXGI_FORMAT_R8G8_SINT;
		case .Byte4:              return .DXGI_FORMAT_R8G8B8A8_SINT;
		case .UByte2Normalized:   return .DXGI_FORMAT_R8G8_UNORM;
		case .UByte4Normalized:   return .DXGI_FORMAT_R8G8B8A8_UNORM;
		case .Byte2Normalized:    return .DXGI_FORMAT_R8G8_SNORM;
		case .Byte4Normalized:    return .DXGI_FORMAT_R8G8B8A8_SNORM;
		case .UShort2:            return .DXGI_FORMAT_R16G16_UINT;
		case .UShort4:            return .DXGI_FORMAT_R16G16B16A16_UINT;
		case .Short2:             return .DXGI_FORMAT_R16G16_SINT;
		case .Short4:             return .DXGI_FORMAT_R16G16B16A16_SINT;
		case .UShort2Normalized:  return .DXGI_FORMAT_R16G16_UNORM;
		case .UShort4Normalized:  return .DXGI_FORMAT_R16G16B16A16_UNORM;
		case .Short2Normalized:   return .DXGI_FORMAT_R16G16_SNORM;
		case .Short4Normalized:   return .DXGI_FORMAT_R16G16B16A16_SNORM;
		case .Half2:              return .DXGI_FORMAT_R16G16_FLOAT;
		case .Half4:              return .DXGI_FORMAT_R16G16B16A16_FLOAT;
		case .Float:              return .DXGI_FORMAT_R32_FLOAT;
		case .Float2:             return .DXGI_FORMAT_R32G32_FLOAT;
		case .Float3:             return .DXGI_FORMAT_R32G32B32_FLOAT;
		case .Float4:             return .DXGI_FORMAT_R32G32B32A32_FLOAT;
		case .UInt:               return .DXGI_FORMAT_R32_UINT;
		case .UInt2:              return .DXGI_FORMAT_R32G32_UINT;
		case .UInt3:              return .DXGI_FORMAT_R32G32B32_UINT;
		case .UInt4:              return .DXGI_FORMAT_R32G32B32A32_UINT;
		case .Int:                return .DXGI_FORMAT_R32_SINT;
		case .Int2:               return .DXGI_FORMAT_R32G32_SINT;
		case .Int3:               return .DXGI_FORMAT_R32G32B32_SINT;
		case .Int4:               return .DXGI_FORMAT_R32G32B32A32_SINT;
		default:                  return .DXGI_FORMAT_UNKNOWN;
		}
	}

	// ===== Blend =====

	public static D3D12_BLEND ToDx12Blend(BlendFactor factor)
	{
		switch (factor)
		{
		case .Zero:                return .D3D12_BLEND_ZERO;
		case .One:                 return .D3D12_BLEND_ONE;
		case .Src:                 return .D3D12_BLEND_SRC_COLOR;
		case .OneMinusSrc:         return .D3D12_BLEND_INV_SRC_COLOR;
		case .SrcAlpha:            return .D3D12_BLEND_SRC_ALPHA;
		case .OneMinusSrcAlpha:    return .D3D12_BLEND_INV_SRC_ALPHA;
		case .Dst:                 return .D3D12_BLEND_DEST_COLOR;
		case .OneMinusDst:         return .D3D12_BLEND_INV_DEST_COLOR;
		case .DstAlpha:            return .D3D12_BLEND_DEST_ALPHA;
		case .OneMinusDstAlpha:    return .D3D12_BLEND_INV_DEST_ALPHA;
		case .SrcAlphaSaturated:   return .D3D12_BLEND_SRC_ALPHA_SAT;
		case .Constant:            return .D3D12_BLEND_BLEND_FACTOR;
		case .OneMinusConstant:    return .D3D12_BLEND_INV_BLEND_FACTOR;
		default:                   return .D3D12_BLEND_ONE;
		}
	}

	public static D3D12_BLEND_OP ToDx12BlendOp(BlendOperation op)
	{
		switch (op)
		{
		case .Add:              return .D3D12_BLEND_OP_ADD;
		case .Subtract:         return .D3D12_BLEND_OP_SUBTRACT;
		case .ReverseSubtract:  return .D3D12_BLEND_OP_REV_SUBTRACT;
		case .Min:              return .D3D12_BLEND_OP_MIN;
		case .Max:              return .D3D12_BLEND_OP_MAX;
		default:                return .D3D12_BLEND_OP_ADD;
		}
	}

	// ===== Comparison =====

	public static D3D12_COMPARISON_FUNC ToDx12CompareFunc(CompareFunction func)
	{
		switch (func)
		{
		case .Never:          return .D3D12_COMPARISON_FUNC_NEVER;
		case .Less:           return .D3D12_COMPARISON_FUNC_LESS;
		case .Equal:          return .D3D12_COMPARISON_FUNC_EQUAL;
		case .LessEqual:      return .D3D12_COMPARISON_FUNC_LESS_EQUAL;
		case .Greater:        return .D3D12_COMPARISON_FUNC_GREATER;
		case .NotEqual:       return .D3D12_COMPARISON_FUNC_NOT_EQUAL;
		case .GreaterEqual:   return .D3D12_COMPARISON_FUNC_GREATER_EQUAL;
		case .Always:         return .D3D12_COMPARISON_FUNC_ALWAYS;
		default:              return .D3D12_COMPARISON_FUNC_LESS;
		}
	}

	// ===== Stencil =====

	public static D3D12_STENCIL_OP ToDx12StencilOp(StencilOperation op)
	{
		switch (op)
		{
		case .Keep:              return .D3D12_STENCIL_OP_KEEP;
		case .Zero:              return .D3D12_STENCIL_OP_ZERO;
		case .Replace:           return .D3D12_STENCIL_OP_REPLACE;
		case .IncrementClamp:    return .D3D12_STENCIL_OP_INCR_SAT;
		case .DecrementClamp:    return .D3D12_STENCIL_OP_DECR_SAT;
		case .Invert:            return .D3D12_STENCIL_OP_INVERT;
		case .IncrementWrap:     return .D3D12_STENCIL_OP_INCR;
		case .DecrementWrap:     return .D3D12_STENCIL_OP_DECR;
		default:                 return .D3D12_STENCIL_OP_KEEP;
		}
	}

	// ===== Cull / Fill / FrontFace =====

	public static D3D12_CULL_MODE ToDx12CullMode(CullMode mode)
	{
		switch (mode)
		{
		case .None:    return .D3D12_CULL_MODE_NONE;
		case .Front:   return .D3D12_CULL_MODE_FRONT;
		case .Back:    return .D3D12_CULL_MODE_BACK;
		default:       return .D3D12_CULL_MODE_BACK;
		}
	}

	public static D3D12_FILL_MODE ToDx12FillMode(FillMode mode)
	{
		switch (mode)
		{
		case .Solid:       return .D3D12_FILL_MODE_SOLID;
		case .Wireframe:   return .D3D12_FILL_MODE_WIREFRAME;
		default:           return .D3D12_FILL_MODE_SOLID;
		}
	}

	// ===== Primitive Topology =====

	public static D3D12_PRIMITIVE_TOPOLOGY_TYPE ToDx12TopologyType(PrimitiveTopology topology)
	{
		switch (topology)
		{
		case .PointList:       return .D3D12_PRIMITIVE_TOPOLOGY_TYPE_POINT;
		case .LineList,
			 .LineStrip:       return .D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE;
		case .TriangleList,
			 .TriangleStrip:   return .D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
		default:               return .D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
		}
	}

	public static D3D_PRIMITIVE_TOPOLOGY ToDx12Topology(PrimitiveTopology topology)
	{
		switch (topology)
		{
		case .PointList:       return .D3D_PRIMITIVE_TOPOLOGY_POINTLIST;
		case .LineList:        return .D3D_PRIMITIVE_TOPOLOGY_LINELIST;
		case .LineStrip:       return .D3D_PRIMITIVE_TOPOLOGY_LINESTRIP;
		case .TriangleList:    return .D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
		case .TriangleStrip:   return .D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP;
		default:               return .D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
		}
	}

	// ===== Sampler =====

	public static D3D12_FILTER ToDx12Filter(FilterMode minFilter, FilterMode magFilter, FilterMode mipFilter, bool comparison)
	{
		// Build D3D12 filter from min/mag/mip (each can be Point or Linear)
		int32 min = (minFilter == .Linear) ? 1 : 0;
		int32 mag = (magFilter == .Linear) ? 1 : 0;
		int32 mip = (mipFilter == .Linear) ? 1 : 0;

		int32 filter = (min << 4) | (mag << 2) | mip;
		if (comparison)
			filter |= 0x80; // D3D12_FILTER_COMPARISON_BIT

		return (D3D12_FILTER)filter;
	}

	public static D3D12_TEXTURE_ADDRESS_MODE ToDx12AddressMode(AddressMode mode)
	{
		switch (mode)
		{
		case .Repeat:          return .D3D12_TEXTURE_ADDRESS_MODE_WRAP;
		case .MirrorRepeat:    return .D3D12_TEXTURE_ADDRESS_MODE_MIRROR;
		case .ClampToEdge:     return .D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
		case .ClampToBorder:   return .D3D12_TEXTURE_ADDRESS_MODE_BORDER;
		default:               return .D3D12_TEXTURE_ADDRESS_MODE_WRAP;
		}
	}

	// ===== Resource States =====

	public static D3D12_RESOURCE_STATES ToDx12ResourceState(TextureLayout layout)
	{
		switch (layout)
		{
		case .Undefined:                   return .D3D12_RESOURCE_STATE_COMMON;
		case .General:                     return .D3D12_RESOURCE_STATE_COMMON;
		case .ColorAttachment:             return .D3D12_RESOURCE_STATE_RENDER_TARGET;
		case .DepthStencilAttachment:      return .D3D12_RESOURCE_STATE_DEPTH_WRITE;
		case .DepthStencilReadOnly:        return .D3D12_RESOURCE_STATE_DEPTH_READ;
		case .ShaderReadOnly:              return (D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		case .TransferSrc:                 return .D3D12_RESOURCE_STATE_COPY_SOURCE;
		case .TransferDst:                 return .D3D12_RESOURCE_STATE_COPY_DEST;
		case .Present:                     return .D3D12_RESOURCE_STATE_PRESENT;
		default:                           return .D3D12_RESOURCE_STATE_COMMON;
		}
	}

	// ===== SRV/UAV/RTV/DSV Dimension =====

	public static D3D12_SRV_DIMENSION ToDx12SrvDimension(TextureViewDimension dim)
	{
		switch (dim)
		{
		case .Texture1D:         return .D3D12_SRV_DIMENSION_TEXTURE1D;
		case .Texture2D:         return .D3D12_SRV_DIMENSION_TEXTURE2D;
		case .Texture2DArray:    return .D3D12_SRV_DIMENSION_TEXTURE2DARRAY;
		case .Texture3D:         return .D3D12_SRV_DIMENSION_TEXTURE3D;
		case .TextureCube:       return .D3D12_SRV_DIMENSION_TEXTURECUBE;
		case .TextureCubeArray:  return .D3D12_SRV_DIMENSION_TEXTURECUBEARRAY;
		default:                 return .D3D12_SRV_DIMENSION_TEXTURE2D;
		}
	}

	public static D3D12_UAV_DIMENSION ToDx12UavDimension(TextureViewDimension dim)
	{
		switch (dim)
		{
		case .Texture1D:         return .D3D12_UAV_DIMENSION_TEXTURE1D;
		case .Texture2D:         return .D3D12_UAV_DIMENSION_TEXTURE2D;
		case .Texture2DArray:    return .D3D12_UAV_DIMENSION_TEXTURE2DARRAY;
		case .Texture3D:         return .D3D12_UAV_DIMENSION_TEXTURE3D;
		default:                 return .D3D12_UAV_DIMENSION_TEXTURE2D;
		}
	}

	public static D3D12_RTV_DIMENSION ToDx12RtvDimension(TextureViewDimension dim, uint32 sampleCount)
	{
		if (sampleCount > 1)
			return .D3D12_RTV_DIMENSION_TEXTURE2DMS;

		switch (dim)
		{
		case .Texture1D:         return .D3D12_RTV_DIMENSION_TEXTURE1D;
		case .Texture2D:         return .D3D12_RTV_DIMENSION_TEXTURE2D;
		case .Texture2DArray:    return .D3D12_RTV_DIMENSION_TEXTURE2DARRAY;
		case .Texture3D:         return .D3D12_RTV_DIMENSION_TEXTURE3D;
		default:                 return .D3D12_RTV_DIMENSION_TEXTURE2D;
		}
	}

	public static D3D12_DSV_DIMENSION ToDx12DsvDimension(TextureViewDimension dim, uint32 sampleCount)
	{
		if (sampleCount > 1)
			return .D3D12_DSV_DIMENSION_TEXTURE2DMS;

		switch (dim)
		{
		case .Texture1D:         return .D3D12_DSV_DIMENSION_TEXTURE1D;
		case .Texture2D:         return .D3D12_DSV_DIMENSION_TEXTURE2D;
		case .Texture2DArray:    return .D3D12_DSV_DIMENSION_TEXTURE2DARRAY;
		default:                 return .D3D12_DSV_DIMENSION_TEXTURE2D;
		}
	}

	// ===== Index Format =====

	public static DXGI_FORMAT ToDxgiFormat(IndexFormat format)
	{
		switch (format)
		{
		case .UInt16:   return .DXGI_FORMAT_R16_UINT;
		case .UInt32:   return .DXGI_FORMAT_R32_UINT;
		default:        return .DXGI_FORMAT_R16_UINT;
		}
	}

	// ===== Descriptor Range Type =====

	public static D3D12_DESCRIPTOR_RANGE_TYPE ToDx12RangeType(BindingType type)
	{
		switch (type)
		{
		case .UniformBuffer:                return .D3D12_DESCRIPTOR_RANGE_TYPE_CBV;
		case .StorageBuffer:                return .D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
		case .StorageBufferReadWrite:       return .D3D12_DESCRIPTOR_RANGE_TYPE_UAV;
		case .SampledTexture:               return .D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
		case .StorageTexture,
			 .StorageTextureReadWrite:      return .D3D12_DESCRIPTOR_RANGE_TYPE_UAV;
		case .Sampler,
			 .ComparisonSampler:            return .D3D12_DESCRIPTOR_RANGE_TYPE_SAMPLER;
		default:                            return .D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
		}
	}

	/// Returns true if the binding type is a sampler (goes into the sampler heap).
	public static bool IsSamplerBinding(BindingType type)
	{
		return type == .Sampler || type == .ComparisonSampler;
	}

	/// Returns true if the binding type is a CBV/SRV/UAV (goes into the CBV/SRV/UAV heap).
	public static bool IsCbvSrvUavBinding(BindingType type)
	{
		return !IsSamplerBinding(type);
	}

	// ===== Vertex Semantic Mapping =====

	/// Maps ShaderLocation to HLSL semantic name for input layout.
	public static void GetSemanticName(uint32 shaderLocation, String outName, out uint32 semanticIndex)
	{
		switch (shaderLocation)
		{
		case 0:
			outName.Append("POSITION");
			semanticIndex = 0;
		case 1:
			outName.Append("NORMAL");
			semanticIndex = 0;
		case 2:
			outName.Append("TEXCOORD");
			semanticIndex = 0;
		case 3:
			outName.Append("COLOR");
			semanticIndex = 0;
		case 4:
			outName.Append("TANGENT");
			semanticIndex = 0;
		default:
			// Locations 5+ use TEXCOORD{N} (for bone indices/weights/instance data)
			outName.Append("TEXCOORD");
			semanticIndex = shaderLocation;
		}
	}
}
