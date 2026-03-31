namespace RendererFramework;

using System;
using System.Collections;
using Dxc_Beef;
using Sedulous.RHI;
using Sedulous.Renderer;

/// Output format for compiled shaders.
public enum ShaderOutputFormat
{
	DXIL,
	SPIRV,
}

/// IShaderCompiler implementation using DXC (DirectX Shader Compiler).
/// Compiles HLSL to DXIL or SPIR-V with variant defines prepended.
public class DxcShaderCompiler : IShaderCompiler
{
	private IDxcCompiler3* mCompiler;
	private IDxcUtils* mUtils;
	private IDxcIncludeHandler* mIncludeHandler;
	private ShaderOutputFormat mFormat;
	private bool mInitialized;

	public int OptimizationLevel = 3;
	public bool EnableDebugInfo = false;
	public uint32 SrvShift = 1000;
	public uint32 UavShift = 2000;
	public uint32 SamplerShift = 3000;
	public uint32 CbvShift = 0;

	public this(ShaderOutputFormat format)
	{
		mFormat = format;
	}

	public Result<void> Init()
	{
		if (mInitialized) return .Ok;

		if (Dxc.CreateInstance<IDxcCompiler3>(out mCompiler) != .S_OK)
			return .Err;

		if (Dxc.CreateInstance<IDxcUtils>(out mUtils) != .S_OK)
		{
			mCompiler.Release(); mCompiler = null;
			return .Err;
		}

		if (mUtils.CreateDefaultIncludeHandler(out mIncludeHandler) != .S_OK)
		{
			mUtils.Release(); mUtils = null;
			mCompiler.Release(); mCompiler = null;
			return .Err;
		}

		mInitialized = true;
		return .Ok;
	}

	public Result<void> Compile(
		StringView source,
		StringView entryPoint,
		ShaderStage stage,
		Span<ShaderDefine> defines,
		List<uint8> outBytecode)
	{
		if (!mInitialized) return .Err;

		// Prepend #defines for variant flags and backend identification
		let fullSource = scope String();
		if (mFormat == .SPIRV)
			fullSource.Append("#define VULKAN 1\n");
		for (let define in defines)
			fullSource.AppendF("#define {} {}\n", define.Name, define.Value);
		fullSource.Append(source);

		// Map ShaderStage to HLSL profile
		let profile = GetProfile(stage);
		if (profile.IsEmpty)
			return .Err;

		// Build DXC arguments
		List<StringView> args = scope .();
		args.Add("-E");
		args.Add(entryPoint);
		args.Add("-T");
		args.Add(profile);

		switch (OptimizationLevel)
		{
		case 0: args.Add(DXC_ARG_OPTIMIZATION_LEVEL0);
		case 1: args.Add(DXC_ARG_OPTIMIZATION_LEVEL1);
		case 2: args.Add(DXC_ARG_OPTIMIZATION_LEVEL2);
		default: args.Add(DXC_ARG_OPTIMIZATION_LEVEL3);
		}

		if (EnableDebugInfo)
			args.Add(DXC_ARG_DEBUG);

		if (mFormat == .SPIRV)
		{
			args.Add("-spirv");
			args.Add("-fspv-target-env=vulkan1.3");
			args.Add("-fspv-extension=SPV_EXT_mesh_shader");
			args.Add("-fspv-extension=SPV_KHR_ray_tracing");

			for (int32 setIdx = 0; setIdx < 4; setIdx++)
			{
				String setStr = scope:: .();
				setStr.AppendF("{}", setIdx);

				if (CbvShift > 0)
				{
					args.Add("-fvk-b-shift");
					String s = scope:: .();
					s.AppendF("{}", CbvShift);
					args.Add(s);
					args.Add(setStr);
				}

				if (SrvShift > 0)
				{
					args.Add("-fvk-t-shift");
					String s = scope:: .();
					s.AppendF("{}", SrvShift);
					args.Add(s);
					args.Add(setStr);
				}

				if (UavShift > 0)
				{
					args.Add("-fvk-u-shift");
					String s = scope:: .();
					s.AppendF("{}", UavShift);
					args.Add(s);
					args.Add(setStr);
				}

				if (SamplerShift > 0)
				{
					args.Add("-fvk-s-shift");
					String s = scope:: .();
					s.AppendF("{}", SamplerShift);
					args.Add(s);
					args.Add(setStr);
				}
			}
		}

		// Create source buffer
		DxcBuffer srcBuffer = .()
		{
			Ptr = fullSource.Ptr,
			Size = (uint)fullSource.Length,
			Encoding = DXC_CP_UTF8
		};

		// Compile
		void** ppResult = null;
		let hr = mCompiler.Compile(&srcBuffer, args, mIncludeHandler, ref IDxcResult.IID, out ppResult);
		if (hr != .S_OK || ppResult == null)
			return .Err;

		IDxcResult* result = (.)ppResult;
		defer result.Release();

		// Check status
		HRESULT status = .S_OK;
		result.GetStatus(out status);

		// Log errors
		if (result.HasOutput(.DXC_OUT_ERRORS))
		{
			void** errorPtr = null;
			IDxcBlobWide* errorName = null;
			if (result.GetOutput(.DXC_OUT_ERRORS, ref IDxcBlobUtf8.IID, out errorPtr, out errorName) == .S_OK && errorPtr != null)
			{
				IDxcBlobUtf8* errorBlob = (.)errorPtr;
				let errorStr = errorBlob.GetStringPointer();
				let errorLen = errorBlob.GetStringLength();
				if (errorStr != null && errorLen > 0 && status != .S_OK)
					Console.WriteLine(StringView(errorStr, errorLen));
				errorBlob.Release();
				if (errorName != null)
					errorName.Release();
			}
		}

		if (status != .S_OK)
			return .Err;

		// Extract bytecode
		if (result.HasOutput(.DXC_OUT_OBJECT))
		{
			void** objectPtr = null;
			IDxcBlobWide* objectName = null;
			if (result.GetOutput(.DXC_OUT_OBJECT, ref IDxcBlob.sIID, out objectPtr, out objectName) == .S_OK && objectPtr != null)
			{
				IDxcBlob* blob = (.)objectPtr;
				let ptr = (uint8*)blob.GetBufferPointer();
				let size = blob.GetBufferSize();

				if (ptr != null && size > 0)
					outBytecode.AddRange(Span<uint8>(ptr, (int)size));

				blob.Release();
				if (objectName != null)
					objectName.Release();
			}
		}

		return .Ok;
	}

	public void Destroy()
	{
		if (mIncludeHandler != null) { mIncludeHandler.Release(); mIncludeHandler = null; }
		if (mUtils != null) { mUtils.Release(); mUtils = null; }
		if (mCompiler != null) { mCompiler.Release(); mCompiler = null; }
		mInitialized = false;
	}

	private static StringView GetProfile(ShaderStage stage)
	{
		switch (stage)
		{
		case .Vertex:   return "vs_6_0";
		case .Fragment:  return "ps_6_0";
		case .Compute:   return "cs_6_0";
		case .Mesh:      return "ms_6_5";
		case .Task:      return "as_6_5";
		default:         return "";
		}
	}
}
