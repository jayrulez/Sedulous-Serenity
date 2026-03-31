namespace Sedulous.Renderer;

using System;
using System.IO;
using System.Collections;
using Sedulous.RHI;

/// Registered shader source entry.
class ShaderEntry
{
	public String Name ~ delete _;
	public String Source ~ delete _;
	public uint32 NameHash;
}

/// Shader source registry with on-demand variant compilation and caching.
/// Compiles shader variants lazily — each unique (shader + stage + flags)
/// combination produces a cached IShaderModule.
///
/// Supports search paths: call AddSearchPath() to register directories
/// where .hlsl files can be found. RegisterShader(name) will search
/// those paths for {name}.hlsl automatically.
public class ShaderLibrary
{
	private IDevice mDevice;
	private IShaderCompiler mCompiler;

	/// Registered shader sources, keyed by name hash.
	private Dictionary<uint32, ShaderEntry> mSources = new .() ~ DeleteDictionaryAndValues!(_);

	/// Compiled shader modules, keyed by variant key.
	private Dictionary<ShaderVariantKey, IShaderModule> mModules = new .() ~ delete _;

	/// Temporary bytecode buffer, reused across compilations.
	private List<uint8> mBytecodeBuffer = new .() ~ delete _;

	/// Directories to search for shader files.
	private List<String> mSearchPaths = new .() ~ DeleteContainerAndItems!(_);

	/// Sets the device used for creating shader modules.
	public void Initialize(IDevice device)
	{
		mDevice = device;
	}

	/// Sets the shader compiler implementation.
	public void SetCompiler(IShaderCompiler compiler)
	{
		mCompiler = compiler;
	}

	/// Adds a directory to the shader search path list.
	/// When RegisterShader(name) is called without source, these
	/// directories are searched for {name}.hlsl.
	public void AddSearchPath(StringView path)
	{
		// Avoid duplicates
		for (let existing in mSearchPaths)
		{
			if (existing == path)
				return;
		}
		mSearchPaths.Add(new String(path));
	}

	/// Registers a shader by name, searching the configured search paths
	/// for {name}.hlsl. Returns .Err if the file is not found in any path.
	public Result<void> RegisterShader(StringView name)
	{
		let hash = HashName(name);
		if (mSources.ContainsKey(hash))
			return .Ok; // Already registered

		let filePath = scope String();
		if (FindShaderFile(name, filePath))
		{
			let source = scope String();
			if (File.ReadAllText(filePath, source) case .Err)
			{
				Console.WriteLine(scope $"ERROR: Failed to read shader file: {filePath}");
				return .Err;
			}
			RegisterShader(name, source);
			return .Ok;
		}

		Console.WriteLine(scope $"ERROR: Shader '{name}' not found in search paths");
		return .Err;
	}

	/// Registers an HLSL shader source by name (inline source).
	public void RegisterShader(StringView name, StringView hlslSource)
	{
		let hash = HashName(name);

		if (mSources.ContainsKey(hash))
		{
			// Update existing
			let entry = mSources[hash];
			entry.Source.Set(hlslSource);
			return;
		}

		let entry = new ShaderEntry();
		entry.Name = new String(name);
		entry.Source = new String(hlslSource);
		entry.NameHash = hash;
		mSources[hash] = entry;
	}

	/// Gets a compiled shader module for the given variant.
	/// Compiles on first request, then returns the cached module.
	public Result<IShaderModule> GetCompiledShader(StringView name, ShaderStage stage, PipelineVariantFlags flags = .None)
	{
		if (mCompiler == null)
			return .Err;

		let nameHash = HashName(name);
		let key = ShaderVariantKey()
		{
			ShaderNameHash = nameHash,
			Stage = stage,
			Flags = flags
		};

		// Check cache
		if (mModules.TryGetValue(key, let existing))
			return .Ok(existing);

		// Find source
		ShaderEntry source;
		if (!mSources.TryGetValue(nameHash, out source))
			return .Err;

		// Build defines from variant flags
		ShaderDefine[8] defines = .();
		int defineCount = 0;
		BuildVariantDefines(flags, ref defines, ref defineCount);

		// Compile
		mBytecodeBuffer.Clear();
		let entryPoint = GetDefaultEntryPoint(stage);
		if (mCompiler.Compile(source.Source, entryPoint, stage, Span<ShaderDefine>(&defines[0], defineCount), mBytecodeBuffer) case .Err)
			return .Err;

		// Create shader module
		let moduleResult = mDevice.CreateShaderModule(ShaderModuleDesc()
		{
			Code = Span<uint8>(mBytecodeBuffer.Ptr, mBytecodeBuffer.Count),
			Label = source.Name
		});

		if (moduleResult case .Err)
			return .Err;

		let module = moduleResult.Value;
		mModules[key] = module;
		return .Ok(module);
	}

	/// Invalidates all compiled modules (e.g., after hot-reload).
	public void InvalidateAll()
	{
		for (let kv in mModules)
		{
			var module = kv.value;
			mDevice.DestroyShaderModule(ref module);
		}
		mModules.Clear();
	}

	/// Shuts down and releases all resources.
	public void Shutdown()
	{
		InvalidateAll();
		for (let kv in mSources)
			delete kv.value;
		mSources.Clear();
	}

	// --- Internal helpers ---

	/// Searches all registered paths for {name}.hlsl.
	private bool FindShaderFile(StringView name, String outPath)
	{
		for (let searchPath in mSearchPaths)
		{
			outPath.Clear();
			Path.InternalCombine(outPath, searchPath, scope $"{name}.hlsl");
			if (File.Exists(outPath))
				return true;
		}
		outPath.Clear();
		return false;
	}

	private static uint32 HashName(StringView name)
	{
		uint32 hash = 2166136261;
		for (let c in name.RawChars)
		{
			hash ^= (uint32)c;
			hash *= 16777619;
		}
		return hash;
	}

	private static StringView GetDefaultEntryPoint(ShaderStage stage)
	{
		switch (stage)
		{
		case .Vertex:   return "VSMain";
		case .Fragment:  return "PSMain";
		case .Compute:   return "CSMain";
		default:         return "main";
		}
	}

	private static void BuildVariantDefines(PipelineVariantFlags flags, ref ShaderDefine[8] defines, ref int count)
	{
		count = 0;
		if (flags.HasFlag(.Instanced))
			defines[count++] = .() { Name = "INSTANCED", Value = "1" };
		if (flags.HasFlag(.Skinned))
			defines[count++] = .() { Name = "SKINNED", Value = "1" };
		if (flags.HasFlag(.ReceiveShadows))
			defines[count++] = .() { Name = "RECEIVE_SHADOWS", Value = "1" };
		if (flags.HasFlag(.AlphaTest))
			defines[count++] = .() { Name = "ALPHA_TEST", Value = "1" };
		if (flags.HasFlag(.MotionVectors))
			defines[count++] = .() { Name = "MOTION_VECTORS", Value = "1" };
		if (flags.HasFlag(.DepthOnly))
			defines[count++] = .() { Name = "DEPTH_ONLY", Value = "1" };
		if (flags.HasFlag(.ShadowCaster))
			defines[count++] = .() { Name = "SHADOW_CASTER", Value = "1" };
		if (flags.HasFlag(.GPUDriven))
			defines[count++] = .() { Name = "GPU_DRIVEN", Value = "1" };
		if (flags.HasFlag(.HiZMip0))
			defines[count++] = .() { Name = "HIZ_MIP0", Value = "1" };
		if (flags.HasFlag(.Passthrough))
			defines[count++] = .() { Name = "PASSTHROUGH", Value = "1" };
	}
}
