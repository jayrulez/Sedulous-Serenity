namespace Sedulous.Renderer;

using System;
using System.IO;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;

/// Shader variant flags for compile-time shader permutations.
//[Flags]
enum ShaderFlags : uint32
{
	None = 0,
	Skinned = 1 << 0,      // Vertex skinning enabled
	Instanced = 1 << 1,    // GPU instancing enabled
	AlphaTest = 1 << 2,    // Alpha testing/cutout
	NormalMap = 1 << 3,    // Normal mapping enabled
	Emissive = 1 << 4,     // Emissive channel enabled
}

/// Identifies a specific shader variant.
struct ShaderVariantKey : IEquatable<ShaderVariantKey>, IHashable
{
	public StringView ShaderName;
	public ShaderFlags Flags;
	public ShaderStage Stage;

	public this(StringView name, ShaderStage stage, ShaderFlags flags = .None)
	{
		ShaderName = name;
		Stage = stage;
		Flags = flags;
	}

	public bool Equals(ShaderVariantKey other)
	{
		return ShaderName == other.ShaderName && Flags == other.Flags && Stage == other.Stage;
	}

	public int GetHashCode()
	{
		int hash = ShaderName.GetHashCode();
		hash = hash * 31 + (int)Flags;
		hash = hash * 31 + (int)Stage;
		return hash;
	}
}

/// A compiled shader module with its metadata.
class ShaderModule
{
	public IShaderModule Module ~ delete _;
	public ShaderStage Stage;
	public ShaderFlags Flags;
	public String Name ~ delete _;

	public this(IShaderModule module, ShaderStage stage, ShaderFlags flags, StringView name)
	{
		Module = module;
		Stage = stage;
		Flags = flags;
		Name = new String(name);
	}
}

/// Manages shader loading, compilation, and caching.
class ShaderLibrary
{
	private IDevice mDevice;
	private HLSLCompiler mCompiler ~ delete _;
	private Dictionary<int, ShaderModule> mShaderCache = new .() ~ DeleteDictionaryAndValues!(_);
	private String mShaderBasePath = new .() ~ delete _;

	/// Binding shifts for SPIRV compilation (Vulkan).
	public uint32 ConstantBufferShift = VulkanBindingShifts.SHIFT_B;
	public uint32 TextureShift = VulkanBindingShifts.SHIFT_T;
	public uint32 SamplerShift = VulkanBindingShifts.SHIFT_S;
	public uint32 UAVShift = VulkanBindingShifts.SHIFT_U;

	public this(IDevice device, StringView shaderBasePath = "shaders")
	{
		mDevice = device;
		mShaderBasePath.Set(shaderBasePath);
		mCompiler = new HLSLCompiler();
	}

	/// Sets the base path for shader files.
	public void SetShaderPath(StringView path)
	{
		mShaderBasePath.Set(path);
	}

	/// Gets a shader module, loading and compiling it if not cached.
	public Result<ShaderModule> GetShader(StringView name, ShaderStage stage, ShaderFlags flags = .None)
	{
		let key = ShaderVariantKey(name, stage, flags);
		let hash = key.GetHashCode();

		// Check cache
		if (mShaderCache.TryGetValue(hash, let cached))
			return .Ok(cached);

		// Load and compile
		if (LoadAndCompileShader(name, stage, flags) case .Ok(let module))
		{
			mShaderCache[hash] = module;
			return .Ok(module);
		}

		return .Err;
	}

	/// Gets a vertex/fragment shader pair.
	public Result<(ShaderModule vert, ShaderModule frag)> GetShaderPair(StringView name, ShaderFlags flags = .None)
	{
		let vertResult = GetShader(name, .Vertex, flags);
		if (vertResult case .Err)
			return .Err;

		let fragResult = GetShader(name, .Fragment, flags);
		if (fragResult case .Err)
			return .Err;

		return .Ok((vertResult.Value, fragResult.Value));
	}

	/// Compiles a shader from source code directly.
	public Result<ShaderModule> CompileFromSource(StringView name, StringView source, ShaderStage stage, ShaderFlags flags = .None)
	{
		let key = ShaderVariantKey(name, stage, flags);
		let hash = key.GetHashCode();

		// Check cache
		if (mShaderCache.TryGetValue(hash, let cached))
			return .Ok(cached);

		// Compile
		if (CompileShader(source, stage, flags) case .Ok(let rhiModule))
		{
			let module = new ShaderModule(rhiModule, stage, flags, name);
			mShaderCache[hash] = module;
			return .Ok(module);
		}

		return .Err;
	}

	/// Clears the shader cache and releases all modules.
	public void ClearCache()
	{
		for (let kv in mShaderCache)
		{
			delete kv.value;
		}
		mShaderCache.Clear();
	}

	// ===== Internal Methods =====

	private Result<ShaderModule> LoadAndCompileShader(StringView name, ShaderStage stage, ShaderFlags flags)
	{
		// Build file path
		String path = scope .();
		path.Append(mShaderBasePath);
		path.Append("/");
		path.Append(name);

		switch (stage)
		{
		case .Vertex:   path.Append(".vert.hlsl");
		case .Fragment: path.Append(".frag.hlsl");
		case .Compute:  path.Append(".comp.hlsl");
		default:        return .Err;
		}

		// Read source file
		String source = scope .();
		if (!ReadTextFile(path, source))
		{
			Console.WriteLine(scope $"[ShaderLibrary] Failed to read shader: {path}");
			return .Err;
		}

		// Add preprocessor defines for flags
		String fullSource = scope .();
		AppendDefines(fullSource, flags);
		fullSource.Append(source);

		// Compile
		if (CompileShader(fullSource, stage, flags) case .Ok(let rhiModule))
		{
			return .Ok(new ShaderModule(rhiModule, stage, flags, name));
		}

		return .Err;
	}

	private Result<IShaderModule> CompileShader(StringView source, ShaderStage stage, ShaderFlags flags)
	{
		if (!mCompiler.IsInitialized)
		{
			Console.WriteLine("[ShaderLibrary] Shader compiler not initialized");
			return .Err;
		}

		ShaderCompileOptions options = .();
		options.EntryPoint = "main";
		options.Stage = stage;
		options.Target = .SPIRV;
		options.ConstantBufferShift = ConstantBufferShift;
		options.TextureShift = TextureShift;
		options.SamplerShift = SamplerShift;
		options.UAVShift = UAVShift;

		let result = mCompiler.Compile(source, options);
		defer delete result;

		if (!result.Success)
		{
			Console.WriteLine(scope $"[ShaderLibrary] Compilation failed: {result.Errors}");
			return .Err;
		}

		ShaderModuleDescriptor desc = .(result.Bytecode);
		if (mDevice.CreateShaderModule(&desc) case .Ok(let module))
			return .Ok(module);

		Console.WriteLine("[ShaderLibrary] Failed to create shader module");
		return .Err;
	}

	private void AppendDefines(String output, ShaderFlags flags)
	{
		if (flags.HasFlag(.Skinned))
			output.Append("#define SKINNED 1\n");
		if (flags.HasFlag(.Instanced))
			output.Append("#define INSTANCED 1\n");
		if (flags.HasFlag(.AlphaTest))
			output.Append("#define ALPHA_TEST 1\n");
		if (flags.HasFlag(.NormalMap))
			output.Append("#define NORMAL_MAP 1\n");
		if (flags.HasFlag(.Emissive))
			output.Append("#define EMISSIVE 1\n");
	}

	private static bool ReadTextFile(StringView path, String outContent)
	{
		let stream = scope FileStream();
		if (stream.Open(path, .Read, .Read) case .Err)
			return false;

		let reader = scope StreamReader(stream);
		if (reader.ReadToEnd(outContent) case .Err)
			return false;

		return true;
	}
}
