namespace Sedulous.RHI.HLSLShaderCompiler;

using System;
using System.Collections;
using Sedulous.RHI;
using Dxc_Beef;

/// HLSL shader compiler using DirectX Shader Compiler (DXC).
class HLSLCompiler : IShaderCompiler
{
	private IDxcCompiler3* mCompiler;
	private IDxcUtils* mUtils;

	/// Creates a new HLSL compiler instance.
	public this()
	{
		IDxcCompiler3* compiler = null;
		if (Dxc.CreateInstance<IDxcCompiler3>(out compiler) == .S_OK)
		{
			mCompiler = compiler;
		}

		IDxcUtils* utils = null;
		if (Dxc.CreateInstance<IDxcUtils>(out utils) == .S_OK)
		{
			mUtils = utils;
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mCompiler != null)
		{
			mCompiler.Release();
			mCompiler = null;
		}
		if (mUtils != null)
		{
			mUtils.Release();
			mUtils = null;
		}
	}

	/// Returns true if the compiler was initialized successfully.
	public bool IsInitialized => mCompiler != null && mUtils != null;

	public ShaderCompileResult Compile(StringView source, StringView entryPoint, ShaderStage stage, ShaderTarget target)
	{
		ShaderCompileOptions options = .();
		options.EntryPoint = entryPoint;
		options.Stage = stage;
		options.Target = target;
		return Compile(source, options);
	}

	public ShaderCompileResult Compile(StringView source, ShaderCompileOptions options)
	{
		if (!IsInitialized)
		{
			return .Fail("Shader compiler not initialized");
		}

		// Get target profile string
		StringView profile = GetProfile(options.Stage, options.Target);
		if (profile.IsEmpty)
		{
			return .Fail("Unsupported shader stage");
		}

		// Build arguments
		List<StringView> args = scope .();

		// Entry point
		args.Add("-E");
		args.Add(options.EntryPoint);

		// Target profile
		args.Add("-T");
		args.Add(profile);

		// For SPIRV output, add -spirv flag and binding shifts
		if (options.Target == .SPIRV)
		{
			args.Add("-spirv");
			args.Add("-fspv-target-env=vulkan1.2");

			// Binding shifts for Vulkan
			// -fvk-b-shift <shift> <set> - shifts constant buffer registers
			// -fvk-t-shift <shift> <set> - shifts texture registers
			// -fvk-s-shift <shift> <set> - shifts sampler registers
			// -fvk-u-shift <shift> <set> - shifts UAV registers

			String setStr = scope .();
			setStr.AppendF("{}", options.DescriptorSet);

			if (options.ConstantBufferShift > 0)
			{
				args.Add("-fvk-b-shift");
				String shiftStr = scope:: .();
				shiftStr.AppendF("{}", options.ConstantBufferShift);
				args.Add(shiftStr);
				args.Add(setStr);
			}

			if (options.TextureShift > 0)
			{
				args.Add("-fvk-t-shift");
				String shiftStr = scope:: .();
				shiftStr.AppendF("{}", options.TextureShift);
				args.Add(shiftStr);
				args.Add(setStr);
			}

			if (options.SamplerShift > 0)
			{
				args.Add("-fvk-s-shift");
				String shiftStr = scope:: .();
				shiftStr.AppendF("{}", options.SamplerShift);
				args.Add(shiftStr);
				args.Add(setStr);
			}

			if (options.UAVShift > 0)
			{
				args.Add("-fvk-u-shift");
				String shiftStr = scope:: .();
				shiftStr.AppendF("{}", options.UAVShift);
				args.Add(shiftStr);
				args.Add(setStr);
			}
		}

		// Optimization level
		switch (options.OptimizationLevel)
		{
		case 0: args.Add("-O0");
		case 1: args.Add("-O1");
		case 2: args.Add("-O2");
		default: args.Add("-O3");
		}

		// Debug info
		if (options.Debug)
		{
			args.Add("-Zi");
		}

		// Create source buffer
		DxcBuffer sourceBuffer = .();
		sourceBuffer.Ptr = source.Ptr;
		sourceBuffer.Size = (.)source.Length;
		sourceBuffer.Encoding = DXC_CP_UTF8;

		// Compile
		void** resultPtr = null;
		Guid resultIID = IDxcResult.IID;
		let hr = mCompiler.Compile(&sourceBuffer, args, null, ref resultIID, out resultPtr);

		if (hr != .S_OK || resultPtr == null)
		{
			return .Fail("Compilation failed to execute");
		}

		IDxcResult* result = (.)resultPtr;
		defer result.Release();

		// Check status
		HRESULT status = .S_OK;
		result.GetStatus(out status);

		// Get errors if any
		String errorStr = scope .();
		if (result.HasOutput(.DXC_OUT_ERRORS))
		{
			void** errorsPtr = null;
			IDxcBlobWide* errorName = null;
			Guid blobIID = IDxcBlobUtf8.sIID;
			if (result.GetOutput(.DXC_OUT_ERRORS, ref blobIID, out errorsPtr, out errorName) == .S_OK && errorsPtr != null)
			{
				IDxcBlobUtf8* errorsBlob = (.)errorsPtr;
				defer errorsBlob.Release();

				let errorPtr = errorsBlob.GetStringPointer();
				let errorLen = errorsBlob.GetStringLength();
				if (errorPtr != null && errorLen > 0)
				{
					errorStr.Append(StringView((char8*)errorPtr, (.)errorLen));
				}
			}
		}

		if (status != .S_OK)
		{
			if (errorStr.IsEmpty)
			{
				return .Fail("Compilation failed with unknown error");
			}
			return .Fail(errorStr);
		}

		// Get bytecode
		if (!result.HasOutput(.DXC_OUT_OBJECT))
		{
			return .Fail("Compilation succeeded but no output bytecode");
		}

		void** objectPtr = null;
		IDxcBlobWide* objectName = null;
		Guid blobIID = IDxcBlob.sIID;
		if (result.GetOutput(.DXC_OUT_OBJECT, ref blobIID, out objectPtr, out objectName) != .S_OK || objectPtr == null)
		{
			return .Fail("Failed to get compiled shader bytecode");
		}

		IDxcBlob* objectBlob = (.)objectPtr;
		defer objectBlob.Release();

		let bytecodePtr = (uint8*)objectBlob.GetBufferPointer();
		let bytecodeSize = objectBlob.GetBufferSize();

		if (bytecodePtr == null || bytecodeSize == 0)
		{
			return .Fail("Compiled shader bytecode is empty");
		}

		return .Ok(Span<uint8>(bytecodePtr, (.)bytecodeSize), errorStr.IsEmpty ? default : errorStr);
	}

	/// Gets the shader model profile string for the given stage and target.
	private StringView GetProfile(ShaderStage stage, ShaderTarget target)
	{
		// Use shader model 6.0 as baseline
		switch (stage)
		{
		case .Vertex:
			return "vs_6_0";
		case .Fragment:
			return "ps_6_0";
		case .Compute:
			return "cs_6_0";
		default:
			return default;
		}
	}
}
