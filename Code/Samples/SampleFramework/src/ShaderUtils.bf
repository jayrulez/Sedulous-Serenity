namespace SampleFramework;

using System;
using System.IO;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;

/// Binding shift configuration for SPIRV compilation.
/// Default values use VulkanBindingShifts constants for automatic separation.
struct BindingShifts
{
	public uint32 ConstantBuffer = VulkanBindingShifts.SHIFT_B;
	public uint32 Texture = VulkanBindingShifts.SHIFT_T;
	public uint32 Sampler = VulkanBindingShifts.SHIFT_S;
	public uint32 UAV = VulkanBindingShifts.SHIFT_U;

	/// No shifts - each register type starts at binding 0.
	/// Only use this if you're manually managing bindings.
	public static Self None => .() { ConstantBuffer = 0, Texture = 0, Sampler = 0, UAV = 0 };

	/// Default Vulkan shifts for automatic separation of resource types.
	public static Self Vulkan => .();
}

/// Helper class for shader compilation.
static class ShaderUtils
{
	/// Reads a text file into a string.
	public static bool ReadTextFile(StringView path, String outContent)
	{
		let stream = scope FileStream();
		if (stream.Open(path, .Read, .Read) case .Err)
			return false;

		let reader = scope StreamReader(stream);
		if (reader.ReadToEnd(outContent) case .Err)
			return false;

		return true;
	}

	/// Compiles an HLSL shader to SPIRV with optional binding shifts.
	public static Result<IShaderModule> CompileShader(
		IDevice device,
		StringView source,
		StringView entryPoint,
		ShaderStage stage,
		BindingShifts shifts = .())
	{
		let compiler = scope HLSLCompiler();
		if (!compiler.IsInitialized)
			return .Err;

		ShaderCompileOptions options = .();
		options.EntryPoint = entryPoint;
		options.Stage = stage;
		options.Target = .SPIRV;
		options.ConstantBufferShift = shifts.ConstantBuffer;
		options.TextureShift = shifts.Texture;
		options.SamplerShift = shifts.Sampler;
		options.UAVShift = shifts.UAV;

		let result = compiler.Compile(source, options);
		defer delete result;

		if (!result.Success)
		{
			Console.WriteLine(scope $"Shader compilation failed: {result.Errors}");
			return .Err;
		}

		ShaderModuleDescriptor desc = .(result.Bytecode);
		if (device.CreateShaderModule(&desc) case .Ok(let module))
			return .Ok(module);

		Console.WriteLine("Failed to create shader module");
		return .Err;
	}

	/// Loads and compiles an HLSL shader from a file.
	public static Result<IShaderModule> LoadShader(
		IDevice device,
		StringView path,
		StringView entryPoint,
		ShaderStage stage,
		BindingShifts shifts = .())
	{
		String source = scope .();
		if (!ReadTextFile(path, source))
		{
			Console.WriteLine(scope $"Failed to read shader file: {path}");
			return .Err;
		}

		return CompileShader(device, source, entryPoint, stage, shifts);
	}

	/// Loads vertex and fragment shaders from files.
	/// Uses convention: {basePath}.vert.hlsl and {basePath}.frag.hlsl
	public static Result<(IShaderModule vert, IShaderModule frag)> LoadShaderPair(
		IDevice device,
		StringView basePath,
		BindingShifts vertShifts = .(),
		BindingShifts fragShifts = .())
	{
		String vertPath = scope $"{basePath}.vert.hlsl";
		String fragPath = scope $"{basePath}.frag.hlsl";

		let vertResult = LoadShader(device, vertPath, "main", .Vertex, vertShifts);
		if (vertResult case .Err)
			return .Err;

		let vertShader = vertResult.Get();

		let fragResult = LoadShader(device, fragPath, "main", .Fragment, fragShifts);
		if (fragResult case .Err)
		{
			delete vertShader;
			return .Err;
		}

		return .Ok((vertShader, fragResult.Get()));
	}
}
