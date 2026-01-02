namespace Sedulous.RHI.HLSLShaderCompiler;

using System;
using Sedulous.RHI;

/// Options for shader compilation.
struct ShaderCompileOptions
{
	/// Entry point function name.
	public StringView EntryPoint;

	/// Shader stage.
	public ShaderStage Stage;

	/// Target bytecode format.
	public ShaderTarget Target;

	/// Descriptor set for binding resources (SPIRV only).
	public uint32 DescriptorSet;

	/// Shift for constant buffer (b) registers to Vulkan bindings.
	/// For example, if this is 0, HLSL register(b0) maps to Vulkan binding 0.
	public uint32 ConstantBufferShift;

	/// Shift for texture (t) registers to Vulkan bindings.
	public uint32 TextureShift;

	/// Shift for sampler (s) registers to Vulkan bindings.
	public uint32 SamplerShift;

	/// Shift for UAV (u) registers to Vulkan bindings.
	public uint32 UAVShift;

	/// Enable debug information.
	public bool Debug;

	/// Optimization level (0-3).
	public uint8 OptimizationLevel;

	public this()
	{
		EntryPoint = "main";
		Stage = .Vertex;
		Target = .SPIRV;
		DescriptorSet = 0;
		ConstantBufferShift = 0;
		TextureShift = 0;
		SamplerShift = 0;
		UAVShift = 0;
		Debug = false;
		OptimizationLevel = 3;
	}

	/// Creates options for vertex shader.
	public static Self Vertex(StringView entryPoint, ShaderTarget target)
	{
		Self opts = .();
		opts.EntryPoint = entryPoint;
		opts.Stage = .Vertex;
		opts.Target = target;
		return opts;
	}

	/// Creates options for fragment/pixel shader.
	public static Self Fragment(StringView entryPoint, ShaderTarget target)
	{
		Self opts = .();
		opts.EntryPoint = entryPoint;
		opts.Stage = .Fragment;
		opts.Target = target;
		return opts;
	}

	/// Creates options for compute shader.
	public static Self Compute(StringView entryPoint, ShaderTarget target)
	{
		Self opts = .();
		opts.EntryPoint = entryPoint;
		opts.Stage = .Compute;
		opts.Target = target;
		return opts;
	}
}
