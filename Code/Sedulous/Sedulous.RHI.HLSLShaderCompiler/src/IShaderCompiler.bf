namespace Sedulous.RHI.HLSLShaderCompiler;

using System;
using Sedulous.RHI;

/// Interface for compiling shaders from source to bytecode.
interface IShaderCompiler : IDisposable
{
	/// Compiles HLSL source code to the target format with full options.
	///
	/// Parameters:
	///   source: The HLSL source code.
	///   options: Compilation options including entry point, stage, target, and binding shifts.
	///
	/// Returns:
	///   A ShaderCompileResult containing the bytecode or error messages.
	ShaderCompileResult Compile(StringView source, ShaderCompileOptions options);

	/// Compiles HLSL source code to the target format (simplified).
	///
	/// Parameters:
	///   source: The HLSL source code.
	///   entryPoint: The name of the entry point function.
	///   stage: The shader stage (Vertex, Fragment, Compute).
	///   target: The target bytecode format (SPIRV or DXIL).
	///
	/// Returns:
	///   A ShaderCompileResult containing the bytecode or error messages.
	ShaderCompileResult Compile(StringView source, StringView entryPoint, ShaderStage stage, ShaderTarget target);
}
