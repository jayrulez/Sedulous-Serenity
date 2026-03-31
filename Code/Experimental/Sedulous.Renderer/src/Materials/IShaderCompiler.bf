namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;

/// Abstract shader compiler interface.
/// The application provides an implementation that wraps the actual
/// compiler (DXC, glslang, etc.) and targets the correct backend format.
public interface IShaderCompiler
{
	/// Compiles HLSL source to backend-specific bytecode.
	/// Defines are injected as #define NAME VALUE before the source.
	Result<void> Compile(
		StringView source,
		StringView entryPoint,
		ShaderStage stage,
		Span<ShaderDefine> defines,
		List<uint8> outBytecode);
}
