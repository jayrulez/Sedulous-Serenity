namespace SampleFramework;

using System;
using System.IO;
using Sedulous.RHI;
using Sedulous.Shaders;

/// Helper class for shader compilation.
/// Automatically detects shader target (SPIRV/DXIL) and binding shifts from the device.
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

	/// Returns the appropriate shader target for the given device.
	/// DX12 devices use DXIL, Vulkan devices use SPIRV.
	public static ShaderTarget GetTargetForDevice(IDevice device)
	{
		return device.FlipProjectionRequired ? .SPIRV : .DXIL;
	}

	/// Compiles an HLSL shader from source.
	/// Target and binding shifts are auto-detected from the device.
	public static Result<IShaderModule> CompileShader(
		IDevice device,
		StringView source,
		StringView entryPoint,
		ShaderStage stage)
	{
		let target = GetTargetForDevice(device);

		let compiler = scope ShaderCompiler();
		if (compiler.Initialize() case .Err)
			return .Err;

		if (target == .SPIRV)
		{
			compiler.ConstantBufferShift = VulkanBindingShifts.SHIFT_B;
			compiler.TextureShift = VulkanBindingShifts.SHIFT_T;
			compiler.SamplerShift = VulkanBindingShifts.SHIFT_S;
			compiler.UAVShift = VulkanBindingShifts.SHIFT_U;
		}
		// DXIL: zero shifts (default) — DX12 uses HLSL registers natively

		let key = ShaderVariantKey("inline", stage, .None);
		var result = compiler.Compile(source, key, target, entryPoint);
		defer result.Dispose();

		if (!result.Success)
		{
			Console.WriteLine(scope $"Shader compilation failed: {result.Messages}");
			return .Err;
		}

		ShaderModuleDescriptor desc = .(result.Bytecode);
		if (device.CreateShaderModule(&desc) case .Ok(let module))
			return .Ok(module);

		Console.WriteLine("Failed to create shader module");
		return .Err;
	}

	/// Loads and compiles an HLSL shader from a file.
	/// Target and binding shifts are auto-detected from the device.
	public static Result<IShaderModule> LoadShader(
		IDevice device,
		StringView path,
		StringView entryPoint,
		ShaderStage stage)
	{
		String source = scope .();
		if (!ReadTextFile(path, source))
		{
			Console.WriteLine(scope $"Failed to read shader file: {path}");
			return .Err;
		}

		return CompileShader(device, source, entryPoint, stage);
	}

	/// Loads vertex and fragment shaders from files.
	/// Uses convention: {basePath}.vert.hlsl and {basePath}.frag.hlsl
	/// Target and binding shifts are auto-detected from the device.
	public static Result<(IShaderModule vert, IShaderModule frag)> LoadShaderPair(
		IDevice device,
		StringView basePath)
	{
		String vertPath = scope $"{basePath}.vert.hlsl";
		String fragPath = scope $"{basePath}.frag.hlsl";

		let vertResult = LoadShader(device, vertPath, "main", .Vertex);
		if (vertResult case .Err)
			return .Err;

		let vertShader = vertResult.Get();

		let fragResult = LoadShader(device, fragPath, "main", .Fragment);
		if (fragResult case .Err)
		{
			delete vertShader;
			return .Err;
		}

		return .Ok((vertShader, fragResult.Get()));
	}
}
