namespace Sedulous.Shaders;

using System;
using System.IO;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;

/// Manages shader loading, compilation, and caching.
/// Supports both in-memory caching and disk-based precompiled shader caching.
class OldShaderSystem
{
	private IDevice mDevice;
	private HLSLCompiler mCompiler ~ delete _;
	private Dictionary<int, ShaderModule> mShaderCache = new .() ~ DeleteDictionaryAndValues!(_);
	private String mShaderBasePath = new .() ~ delete _;
	private String mCachePath = new .() ~ delete _;

	/// Binding shifts for SPIRV compilation (Vulkan).
	public uint32 ConstantBufferShift = VulkanBindingShifts.SHIFT_B;
	public uint32 TextureShift = VulkanBindingShifts.SHIFT_T;
	public uint32 SamplerShift = VulkanBindingShifts.SHIFT_S;
	public uint32 UAVShift = VulkanBindingShifts.SHIFT_U;

	/// Target compilation format (SPIRV for Vulkan, DXIL for D3D12).
	public ShaderTarget Target = .SPIRV;

	public this(IDevice device, StringView shaderBasePath = "shaders")
	{
		mDevice = device;
		mShaderBasePath.Set(shaderBasePath);
		mCompiler = new HLSLCompiler();
	}

	public Result<void> Initialize(IDevice device, StringView shaderSourcePath, StringView cachePath = default)
	{
		mDevice = device;

		// Store shader source path
		delete mShaderBasePath;
		mShaderBasePath = new String(shaderSourcePath);

		return .Ok;
	}

	/// Sets the base path for shader source files.
	public void SetShaderPath(StringView path)
	{
		mShaderBasePath.Set(path);
	}

	/// Sets the cache path for precompiled shaders.
	/// If set, shaders are loaded from cache when available and saved after compilation.
	/// Set to empty string to disable disk caching.
	public void SetCachePath(StringView path)
	{
		mCachePath.Set(path);

		// Create cache directory if it doesn't exist
		if (mCachePath.Length > 0 && !Directory.Exists(mCachePath))
		{
			Directory.CreateDirectory(mCachePath).IgnoreError();
		}
	}

	/// Gets a shader module, loading from cache or compiling if not cached.
	public Result<ShaderModule> GetShader(StringView name, ShaderStage stage, ShaderFlags flags = .None)
	{
		let key = ShaderVariantKey(name, stage, flags);
		let hash = key.GetHashCode();

		// Check in-memory cache first
		if (mShaderCache.TryGetValue(hash, let cached))
			return .Ok(cached);

		// Try to load from disk cache
		if (mCachePath.Length > 0)
		{
			/*if (TryLoadFromDiskCache(key) case .Ok(let module))
			{
				mShaderCache[hash] = module;
				return .Ok(module);
			}*/
		}

		// Compile from source
		if (LoadAndCompileShader(name, stage, flags) case .Ok(let module))
		{
			mShaderCache[hash] = module;

			// Save to disk cache
			if (mCachePath.Length > 0)
			{
				SaveToDiskCache(key, module);
			}

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
	/*public Result<ShaderModule> CompileFromSource(StringView name, StringView source, ShaderStage stage, ShaderFlags flags = .None)
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
	}*/

	/// Clears the in-memory shader cache and releases all modules.
	public void ClearCache()
	{
		for (let kv in mShaderCache)
		{
			delete kv.value;
		}
		mShaderCache.Clear();
	}

	/// Clears the disk cache directory.
	public void ClearDiskCache()
	{
		if (mCachePath.Length == 0)
			return;

		for (let entry in Directory.EnumerateFiles(mCachePath))
		{
			String fileName = scope .();
			entry.GetFileName(fileName);
			if (fileName.EndsWith(".spv") || fileName.EndsWith(".dxil"))
			{
				String fullPath = scope .();
				entry.GetFilePath(fullPath);
				File.Delete(fullPath).IgnoreError();
			}
		}
	}

	// ===== Disk Cache Methods =====

	/*private Result<ShaderModule> TryLoadFromDiskCache(ShaderVariantKey key)
	{
		String cacheKey = scope .();
		key.GenerateCacheKey(cacheKey);

		String cachePath = scope .();
		cachePath.Append(mCachePath);
		cachePath.Append("/");
		cachePath.Append(cacheKey);
		cachePath.Append(Target == .SPIRV ? ".spv" : ".dxil");

		if (!File.Exists(cachePath))
			return .Err;

		// Read cached bytecode
		List<uint8> bytecode = scope .();
		if (File.ReadAll(cachePath, bytecode) case .Err)
			return .Err;

		// Create shader module from cached bytecode
		ShaderModuleDescriptor desc = .(.(bytecode.Ptr, bytecode.Count));
		if (mDevice.CreateShaderModule(&desc) case .Ok(let rhiModule))
		{
			return .Ok(new ShaderModule(rhiModule, key.Stage, key.Flags, key.ShaderName));
		}

		return .Err;
	}*/

	private void SaveToDiskCache(ShaderVariantKey key, ShaderModule module)
	{
		// We need to recompile to get the bytecode for saving
		// This is a limitation - we don't store bytecode in ShaderModule
		// For now, just skip disk caching for runtime-compiled shaders
		// A proper implementation would store bytecode in ShaderModule

		// Actually, let's compile again just to get the bytecode
		String path = scope .();
		path.Append(mShaderBasePath);
		path.Append("/");
		path.Append(key.ShaderName);

		switch (key.Stage)
		{
		case .Vertex:   path.Append(".vert.hlsl");
		case .Fragment: path.Append(".frag.hlsl");
		case .Compute:  path.Append(".comp.hlsl");
		default:        return;
		}

		String source = scope .();
		if (!ReadTextFile(path, source))
			return;

		String fullSource = scope .();
		key.Flags.AppendDefines(fullSource);
		fullSource.Append(source);

		// Compile to get bytecode
		if (!mCompiler.IsInitialized)
			return;

		ShaderCompileOptions options = .();
		options.EntryPoint = "main";
		options.Stage = key.Stage;
		options.Target = Target;
		options.ConstantBufferShift = ConstantBufferShift;
		options.TextureShift = TextureShift;
		options.SamplerShift = SamplerShift;
		options.UAVShift = UAVShift;

		let result = mCompiler.Compile(fullSource, options);
		defer delete result;

		if (!result.Success)
			return;

		// Save bytecode to cache
		String cacheKey = scope .();
		key.GenerateCacheKey(cacheKey);

		String cachePath = scope .();
		cachePath.Append(mCachePath);
		cachePath.Append("/");
		cachePath.Append(cacheKey);
		cachePath.Append(Target == .SPIRV ? ".spv" : ".dxil");

		File.WriteAll(cachePath, result.Bytecode).IgnoreError();
	}

	// ===== Compilation Methods =====

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
		flags.AppendDefines(fullSource);
		fullSource.Append(source);

		// Compile
		if (CompileShader(fullSource, stage, flags) case .Ok(let rhiModule))
		{
			var module = new ShaderModule(default, default);
			module.[Friend]mRhiModule = rhiModule;
			return .Ok(module);
			//return .Ok(new ShaderModule(key, rhiModule, stage, flags, name));
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
		options.Target = Target;
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
