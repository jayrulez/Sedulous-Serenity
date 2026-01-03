namespace RHI.SampleFramework;

using System;
using System.IO;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;

/// Binding shift configuration for SPIRV compilation.
struct BindingShifts
{
	public uint32 ConstantBuffer = 0;
	public uint32 Texture = 0;
	public uint32 Sampler = 0;
	public uint32 UAV = 0;

	/// No shifts - each register type starts at binding 0.
	public static Self None => .();

	/// Standard shifts: b at 0, t at 1, s at 2, u at 3.
	/// Useful for simple shaders with one of each type.
	public static Self Standard => .() { Texture = 1, Sampler = 2, UAV = 3 };
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
