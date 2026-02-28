namespace Sedulous.RHI;

using System;

/// Describes a shader module to be created.
struct ShaderModuleDescriptor
{
	/// Compiled shader bytecode (SPIRV for Vulkan, DXIL for DX12).
	public Span<uint8> Code;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Code = default;
		Label = default;
	}

	public this(Span<uint8> code)
	{
		Code = code;
		Label = default;
	}
}
