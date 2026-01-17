namespace RendererNGSandbox;

using System;
using Sedulous.RendererNG;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Materials;

extension RendererNGSandboxApp
{
	/// Tests the PipelineConfig system.
	public void TestPipelineConfig()
	{
		Console.WriteLine("\n=== Testing PipelineConfig ===\n");

		// Test factory methods
		var opaqueConfig = PipelineConfig.ForOpaqueMesh("pbr");
		Console.WriteLine("Opaque mesh config:");
		Console.WriteLine("  Shader: {}", opaqueConfig.ShaderName);
		Console.WriteLine("  BlendMode: {}", opaqueConfig.BlendMode);
		Console.WriteLine("  DepthMode: {}", opaqueConfig.DepthMode);
		Console.WriteLine("  VertexLayout: {}", opaqueConfig.VertexLayout);

		var transparentConfig = PipelineConfig.ForTransparentMesh("pbr");
		Console.WriteLine("\nTransparent mesh config:");
		Console.WriteLine("  BlendMode: {}", transparentConfig.BlendMode);
		Console.WriteLine("  DepthMode: {}", transparentConfig.DepthMode);

		var shadowConfig = PipelineConfig.ForShadow("shadow");
		Console.WriteLine("\nShadow config:");
		Console.WriteLine("  DepthOnly: {}", shadowConfig.DepthOnly);
		Console.WriteLine("  ColorTargetCount: {}", shadowConfig.ColorTargetCount);
		Console.WriteLine("  DepthBias: {}", shadowConfig.DepthBias);

		var skyboxConfig = PipelineConfig.ForSkybox("skybox");
		Console.WriteLine("\nSkybox config:");
		Console.WriteLine("  CullMode: {}", skyboxConfig.CullMode);
		Console.WriteLine("  DepthCompare: {}", skyboxConfig.DepthCompare);

		var fullscreenConfig = PipelineConfig.ForFullscreen("postprocess");
		Console.WriteLine("\nFullscreen config:");
		Console.WriteLine("  VertexLayout: {}", fullscreenConfig.VertexLayout);
		Console.WriteLine("  DepthMode: {}", fullscreenConfig.DepthMode);

		// Test hashing
		var config1 = PipelineConfig.ForOpaqueMesh("test");
		var config2 = PipelineConfig.ForOpaqueMesh("test");
		var config3 = PipelineConfig.ForOpaqueMesh("other");

		Console.WriteLine("\nHash tests:");
		Console.WriteLine("  Same config hash match: {}", config1.GetHashCode() == config2.GetHashCode());
		Console.WriteLine("  Different config hash differ: {}", config1.GetHashCode() != config3.GetHashCode());
		Console.WriteLine("  Equality test: {}", config1.Equals(config2));

		Console.WriteLine("\nPipelineConfig tests passed!");
	}

	/// Tests the BindGroupLayoutCache.
	public void TestBindGroupLayoutCache()
	{
		Console.WriteLine("\n=== Testing BindGroupLayoutCache ===\n");

		let cache = scope BindGroupLayoutCache();
		cache.Initialize(mDevice);

		// Test per-frame layout (cache owns the layouts, don't delete)
		switch (cache.GetPerFrameLayout())
		{
		case .Ok(let layout):
			Console.WriteLine("Created per-frame layout successfully");
		case .Err:
			Console.WriteLine("ERROR: Failed to create per-frame layout");
		}

		// Test per-object layout
		switch (cache.GetPerObjectLayout())
		{
		case .Ok(let layout):
			Console.WriteLine("Created per-object layout successfully");
		case .Err:
			Console.WriteLine("ERROR: Failed to create per-object layout");
		}

		// Test per-material layout
		switch (cache.GetPerMaterialLayout())
		{
		case .Ok(let layout):
			Console.WriteLine("Created per-material layout successfully");
		case .Err:
			Console.WriteLine("ERROR: Failed to create per-material layout");
		}

		// Test custom layout
		BindGroupLayoutEntry[2] customEntries = .(
			.UniformBuffer(0, .Vertex | .Fragment),
			.SampledTexture(1, .Fragment)
		);

		switch (cache.GetOrCreate(customEntries))
		{
		case .Ok(let layout):
			Console.WriteLine("Created custom layout successfully");

			// Test caching - same layout should be reused
			switch (cache.GetOrCreate(customEntries))
			{
			case .Ok(let layout2):
				Console.WriteLine("Cache hit: {}", layout == layout2);
			case .Err:
				Console.WriteLine("ERROR: Failed second lookup");
			}
		case .Err:
			Console.WriteLine("ERROR: Failed to create custom layout");
		}

		Console.WriteLine("Layout count: {}", cache.Count);
		Console.WriteLine("\nBindGroupLayoutCache tests passed!");
	}

	/// Tests the BindGroupPool.
	public void TestBindGroupPool()
	{
		Console.WriteLine("\n=== Testing BindGroupPool ===\n");

		let pool = scope BindGroupPool();
		pool.Initialize(mDevice);
		pool.BeginFrame(1);

		// Create a simple layout for testing
		BindGroupLayoutEntry[1] layoutEntries = .(
			.UniformBuffer(0, .Vertex)
		);

		var layoutDesc = BindGroupLayoutDescriptor();
		layoutDesc.Entries = layoutEntries;

		switch (mDevice.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout):
			// Create a test buffer
			var bufferDesc = BufferDescriptor();
			bufferDesc.Size = 64;
			bufferDesc.Usage = .Uniform | .CopyDst;

			switch (mDevice.CreateBuffer(&bufferDesc))
			{
			case .Ok(let buffer):
				// Allocate bind group
				BindGroupEntry[1] entries = .(
					.Buffer(0, buffer)
				);

				switch (pool.Allocate(layout, entries))
				{
				case .Ok(let handle):
					Console.WriteLine("Allocated bind group - Index: {}, Gen: {}", handle.Index, handle.Generation);
					Console.WriteLine("  Pool total: {}", pool.TotalCount);
					Console.WriteLine("  Pool active: {}", pool.ActiveCount);

					// Get it back
					let bindGroup = pool.Get(handle);
					Console.WriteLine("  Retrieved bind group: {}", bindGroup != null);

					// Release it
					pool.Release(handle);
					Console.WriteLine("  Released bind group");
					Console.WriteLine("  Pool active after release: {}", pool.ActiveCount);

					// Test recycling
					pool.BeginFrame(2);
					switch (pool.Allocate(layout, entries))
					{
					case .Ok(let handle2):
						Console.WriteLine("  Reallocated - Index: {}, Gen: {}", handle2.Index, handle2.Generation);
						Console.WriteLine("  Generation increased: {}", handle2.Generation > handle.Generation);
					case .Err:
						Console.WriteLine("ERROR: Reallocation failed");
					}
				case .Err:
					Console.WriteLine("ERROR: Failed to allocate bind group");
				}

				delete buffer;
			case .Err:
				Console.WriteLine("ERROR: Failed to create test buffer");
			}

			delete layout;
		case .Err:
			Console.WriteLine("ERROR: Failed to create layout");
		}

		Console.WriteLine("\nBindGroupPool tests passed!");
	}

	/// Tests the Material and MaterialInstance system.
	public void TestMaterialSystem()
	{
		Console.WriteLine("\n=== Testing Material System ===\n");

		// Create a material using the builder
		let material = scope MaterialBuilder("TestMaterial")
			.Shader("pbr")
			.VertexLayout(.Mesh)
			.Color("BaseColor", .(1, 0.5f, 0.5f, 1))
			.Float("Metallic", 0.0f)
			.Float("Roughness", 0.5f)
			.Texture("AlbedoMap")
			.Sampler("MainSampler")
			.Build();

		Console.WriteLine("Material: {}", material.Name);
		Console.WriteLine("  Shader: {}", material.ShaderName);
		Console.WriteLine("  Properties: {}", material.PropertyCount);
		Console.WriteLine("  Uniform size: {} bytes", material.UniformDataSize);
		Console.WriteLine("  Valid: {}", material.IsValid);

		// List properties
		Console.WriteLine("  Property list:");
		for (let prop in material.Properties)
			Console.WriteLine("    - {} ({})", prop.Name, prop.Type);

		// Create an instance
		let instance = scope MaterialInstance(material);
		Console.WriteLine("\nMaterialInstance:");
		Console.WriteLine("  Uniform dirty: {}", instance.IsUniformDirty);
		Console.WriteLine("  Bind group dirty: {}", instance.IsBindGroupDirty);

		// Override a property
		instance.SetFloat("Roughness", 0.8f);
		Console.WriteLine("  After setting Roughness to 0.8:");
		Console.WriteLine("    Uniform dirty: {}", instance.IsUniformDirty);

		// Override color
		instance.SetColor("BaseColor", .(0, 1, 0, 1));
		Console.WriteLine("  After setting BaseColor to green:");
		Console.WriteLine("    Uniform dirty: {}", instance.IsUniformDirty);

		// Clear dirty
		instance.ClearUniformDirty();
		Console.WriteLine("  After clearing dirty: {}", instance.IsUniformDirty);

		// Reset to defaults
		instance.ResetAllProperties();
		Console.WriteLine("  After reset - Uniform dirty: {}", instance.IsUniformDirty);

		// Test factory materials
		let pbrMaterial = Materials.CreatePBR("StandardPBR");
		Console.WriteLine("\nFactory PBR material:");
		Console.WriteLine("  Shader: {}", pbrMaterial.ShaderName);
		Console.WriteLine("  Properties: {}", pbrMaterial.PropertyCount);

		let unlitMaterial = Materials.CreateUnlit("BasicUnlit");
		Console.WriteLine("\nFactory Unlit material:");
		Console.WriteLine("  Shader: {}", unlitMaterial.ShaderName);
		Console.WriteLine("  Properties: {}", unlitMaterial.PropertyCount);

		delete pbrMaterial;
		delete unlitMaterial;
		delete material;

		Console.WriteLine("\nMaterial system tests passed!");
	}

	/// Tests the VertexLayouts system.
	public void TestVertexLayouts()
	{
		Console.WriteLine("\n=== Testing VertexLayouts ===\n");

		// Test stride lookup
		Console.WriteLine("Vertex strides:");
		Console.WriteLine("  PositionOnly: {} bytes", VertexLayouts.GetStride(.PositionOnly));
		Console.WriteLine("  PositionUVColor: {} bytes", VertexLayouts.GetStride(.PositionUVColor));
		Console.WriteLine("  Mesh: {} bytes", VertexLayouts.GetStride(.Mesh));
		Console.WriteLine("  SkinnedMesh: {} bytes", VertexLayouts.GetStride(.SkinnedMesh));

		// Test attribute counts
		Console.WriteLine("\nAttribute counts:");
		Console.WriteLine("  PositionOnly: {}", VertexLayouts.GetAttributeCount(.PositionOnly));
		Console.WriteLine("  PositionUVColor: {}", VertexLayouts.GetAttributeCount(.PositionUVColor));
		Console.WriteLine("  Mesh: {}", VertexLayouts.GetAttributeCount(.Mesh));
		Console.WriteLine("  SkinnedMesh: {}", VertexLayouts.GetAttributeCount(.SkinnedMesh));

		// Test attribute filling
		VertexAttribute[8] attribs = default;
		let count = VertexLayouts.FillAttributes(.Mesh, Span<VertexAttribute>(&attribs[0], 8));
		Console.WriteLine("\nMesh attributes ({}):", count);
		for (int i = 0; i < count; i++)
			Console.WriteLine("  {}: Format={}, Offset={}", i, attribs[i].Format, attribs[i].Offset);

		Console.WriteLine("\nVertexLayouts tests passed!");
	}

	/// Runs all pipeline system tests.
	public void RunPipelineSystemTests()
	{
		Console.WriteLine("\n");
		Console.WriteLine("=====================================");
		Console.WriteLine("   PHASE 2: PIPELINE SYSTEM TESTS   ");
		Console.WriteLine("=====================================");

		TestPipelineConfig();
		TestVertexLayouts();
		TestBindGroupLayoutCache();
		TestBindGroupPool();
		TestMaterialSystem();

		Console.WriteLine("\n=====================================");
		Console.WriteLine("   ALL PIPELINE TESTS COMPLETED!    ");
		Console.WriteLine("=====================================\n");
	}
}
