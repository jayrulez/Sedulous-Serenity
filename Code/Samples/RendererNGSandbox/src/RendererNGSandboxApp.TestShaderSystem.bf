namespace RendererNGSandbox;

using System;
using System.IO;
using Sedulous.RHI;
using Sedulous.RendererNG;
using Sedulous.Shaders;

extension RendererNGSandboxApp
{
	/// Tests the shader system (Phase 1.6)
	private void TestShaderSystem()
	{
		Console.WriteLine("\n--- Testing Shader System ---");

		// Test ShaderFlags
		Console.WriteLine("\nTesting ShaderFlags...");
		let flags = ShaderFlags.Skinned | .NormalMap | .DepthTest | .ReceiveShadows;
		String defines = scope .();
		flags.AppendDefines(defines);
		Console.WriteLine("  Flags: Skinned | NormalMap | DepthTest | ReceiveShadows");
		Console.WriteLine("  Generated defines ({} chars):", defines.Length);
		for (let line in defines.Split('\n'))
		{
			if (!line.IsEmpty)
				Console.WriteLine("    {}", line);
		}

		String keyStr = scope .();
		flags.AppendKeyString(keyStr);
		Console.WriteLine("  Key string: {}", keyStr);

		// Test ShaderVariantKey
		Console.WriteLine("\nTesting ShaderVariantKey...");
		let key = ShaderVariantKey("mesh", .Vertex, flags);
		Console.WriteLine("  Key: name=mesh, stage=Vertex, flags={}", (uint32)flags);
		Console.WriteLine("  Hash: {}", key.GetHashCode());

		String filename = scope .();
		key.GenerateCacheFilename(filename, true);
		Console.WriteLine("  Cache filename: {}", filename);

		String profile = scope .();
		key.GetTargetProfile(profile);
		Console.WriteLine("  Target profile: {}", profile);

		String entryPoint = scope .();
		key.GetDefaultEntryPoint(entryPoint);
		Console.WriteLine("  Entry point: {}", entryPoint);

		// Test ShaderCompiler initialization
		Console.WriteLine("\nTesting ShaderCompiler...");
		let compiler = scope ShaderCompiler();
		if (compiler.Initialize() case .Ok)
		{
			Console.WriteLine("  DXC compiler initialized successfully");
			Console.WriteLine("  Row-major matrices: {}", compiler.RowMajorMatrices);
			Console.WriteLine("  Optimization level: {}", compiler.OptimizationLevel);

			// Try compiling a simple shader
			Console.WriteLine("\nCompiling test shader...");
			let testSource = """
				struct VSInput
				{
					float3 Position : POSITION;
					float2 TexCoord : TEXCOORD0;
				};

				struct VSOutput
				{
					float4 Position : SV_POSITION;
					float2 TexCoord : TEXCOORD0;
				};

				cbuffer FrameConstants : register(b0)
				{
					float4x4 ViewProjection;
				};

				VSOutput VSMain(VSInput input)
				{
					VSOutput output;
					output.Position = mul(float4(input.Position, 1.0), ViewProjection);
					output.TexCoord = input.TexCoord;
					return output;
				}
				""";

			let simpleKey = ShaderVariantKey("test_shader", .Vertex, .None);
			var result = compiler.Compile(testSource, simpleKey, .SPIRV);
			defer result.Dispose();

			if (result.Success)
			{
				Console.WriteLine("  Compilation successful!");
				Console.WriteLine("  Bytecode size: {} bytes", result.Bytecode.Count);

				// Test ShaderModule creation
				Console.WriteLine("\nTesting ShaderModule...");
				let module = scope ShaderModule(simpleKey, result.Bytecode);
				Console.WriteLine("  Module valid: {}", module.IsValid);
				Console.WriteLine("  Stage: {}", module.Stage);
				Console.WriteLine("  Flags: {}", (uint32)module.Flags);
			}
			else
			{
				Console.WriteLine("  Compilation failed!");
				if (!result.Messages.IsEmpty)
					Console.WriteLine("  Messages: {}", result.Messages);
			}
		}
		else
		{
			Console.WriteLine("  ERROR: Failed to initialize DXC compiler");
			Console.WriteLine("  (This may be expected if dxcompiler.dll is not available)");
		}

		// Test ShaderCache
		Console.WriteLine("\nTesting ShaderCache...");
		let cache = scope ShaderCache();
		Console.WriteLine("  Memory cache count: {}", cache.MemoryCacheCount);
		Console.WriteLine("  Disk cache enabled: {}", cache.DiskCacheEnabled);

		// Set up a temporary cache path
		String cachePath = scope .("./shader_cache_test");

		if (cache.SetCachePath(cachePath) case .Ok)
		{
			Console.WriteLine("  Set cache path: {}", cachePath);
			Console.WriteLine("  Disk cache enabled: {}", cache.DiskCacheEnabled);
		}

		String stats = scope .();
		cache.GetStats(stats);
		Console.WriteLine("  Cache stats:\n{}", stats);

		Console.WriteLine("\nShader System tests complete!");
	}
}
