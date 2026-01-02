namespace Sedulous.RHI.HLSLShaderCompiler;

/// Target output format for shader compilation.
enum ShaderTarget
{
	/// SPIR-V bytecode for Vulkan.
	SPIRV,
	/// DXIL bytecode for Direct3D 12.
	DXIL,
}
