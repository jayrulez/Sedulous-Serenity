namespace RendererNGSandbox;

using System;

extension RendererNGSandboxApp
{
	/// Tests the resource pool system (Phase 1.2)
	private void TestResourcePools()
	{
		Console.WriteLine("\n--- Testing Resource Pools ---");

		let resources = mRenderer.Resources;

		// Test buffer creation
		Console.WriteLine("Creating test buffer...");
		let bufferHandle = resources.CreateBuffer(1024, .Vertex | .CopyDst, "TestVertexBuffer");
		if (bufferHandle.HasValidIndex)
		{
			Console.WriteLine("  Buffer created: index={0}, gen={1}", bufferHandle.Index, bufferHandle.Generation);
			Console.WriteLine("  Size: {0} bytes", resources.Buffers.GetSize(bufferHandle));
			Console.WriteLine("  IsValid: {0}", resources.Buffers.IsValid(bufferHandle));
		}
		else
		{
			Console.WriteLine("  ERROR: Failed to create buffer");
		}

		// Test texture creation
		Console.WriteLine("Creating test texture...");
		let textureHandle = resources.CreateTexture2D(256, 256, .RGBA8Unorm, .Sampled | .CopyDst, 1, "TestTexture");
		if (textureHandle.HasValidIndex)
		{
			Console.WriteLine("  Texture created: index={0}, gen={1}", textureHandle.Index, textureHandle.Generation);
			let (w, h, d) = resources.Textures.GetDimensions(textureHandle);
			Console.WriteLine("  Dimensions: {0}x{1}", w, h);
			Console.WriteLine("  Format: {0}", resources.Textures.GetFormat(textureHandle));
			Console.WriteLine("  IsValid: {0}", resources.Textures.IsValid(textureHandle));
		}
		else
		{
			Console.WriteLine("  ERROR: Failed to create texture");
		}

		// Print pool stats
		let stats = resources.GetStats();
		Console.WriteLine("\nResource Pool Stats:");
		Console.WriteLine("  Buffers: {0} allocated, {1} slots, {2} free", stats.AllocatedBuffers, stats.TotalBufferSlots, stats.FreeBufferSlots);
		Console.WriteLine("  Textures: {0} allocated, {1} slots, {2} free", stats.AllocatedTextures, stats.TotalTextureSlots, stats.FreeTextureSlots);

		// Test handle release
		Console.WriteLine("\nTesting handle release...");
		resources.ReleaseBuffer(bufferHandle);
		Console.WriteLine("  Buffer released, IsValid after release: {0}", resources.Buffers.IsValid(bufferHandle));

		resources.ReleaseTexture(textureHandle);
		Console.WriteLine("  Texture released, IsValid after release: {0}", resources.Textures.IsValid(textureHandle));

		// Stats after release
		let statsAfter = resources.GetStats();
		Console.WriteLine("\nStats after release:");
		Console.WriteLine("  Buffers: {0} allocated, {1} free, {2} pending deletions",
			statsAfter.AllocatedBuffers, statsAfter.FreeBufferSlots, statsAfter.PendingDeletions);
		Console.WriteLine("  Textures: {0} allocated, {1} free",
			statsAfter.AllocatedTextures, statsAfter.FreeTextureSlots);

		Console.WriteLine("\nResource Pool tests complete!");
	}
}
