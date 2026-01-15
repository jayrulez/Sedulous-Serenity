namespace RendererNGSandbox;

using System;

/// Test uniform data structure for transient buffer tests.
struct TestUniformData
{
	public float[16] Matrix;
	public float[4] Color;
}

extension RendererNGSandboxApp
{
	/// Tests the transient buffer pool system (Phase 1.3)
	private void TestTransientBuffers()
	{
		Console.WriteLine("\n--- Testing Transient Buffer Pool ---");

		let transient = mRenderer.TransientBuffers;

		// Simulate a frame begin (frame 0)
		transient.BeginFrame(0);
		Console.WriteLine("Frame 0 started");

		// Test vertex allocation
		Console.WriteLine("\nTesting vertex allocation...");
		float[12] vertices = .(
			-0.5f, -0.5f, 0.0f,
			 0.5f, -0.5f, 0.0f,
			 0.5f,  0.5f, 0.0f,
			-0.5f,  0.5f, 0.0f
		);
		let vertexAlloc = transient.AllocateVertices<float>(vertices);
		if (vertexAlloc.IsValid)
		{
			Console.WriteLine("  Vertex allocation: offset={0}, size={1}", vertexAlloc.Offset, vertexAlloc.Size);
			Console.WriteLine("  Buffer valid: {0}", vertexAlloc.Buffer != null);
		}
		else
		{
			Console.WriteLine("  ERROR: Vertex allocation failed");
		}

		// Test index allocation
		Console.WriteLine("\nTesting index allocation...");
		uint16[6] indices = .(0, 1, 2, 2, 3, 0);
		let indexAlloc = transient.AllocateIndices<uint16>(indices);
		if (indexAlloc.IsValid)
		{
			Console.WriteLine("  Index allocation: offset={0}, size={1}", indexAlloc.Offset, indexAlloc.Size);
		}
		else
		{
			Console.WriteLine("  ERROR: Index allocation failed");
		}

		// Test uniform allocation
		Console.WriteLine("\nTesting uniform allocation...");
		let uniformAlloc = transient.AllocateUniform<TestUniformData>();
		if (uniformAlloc.IsValid)
		{
			Console.WriteLine("  Uniform allocation: offset={0}, size={1}", uniformAlloc.Offset, uniformAlloc.Size);
			Console.WriteLine("  Offset aligned to 256: {0}", (uniformAlloc.Offset % 256) == 0);
		}
		else
		{
			Console.WriteLine("  ERROR: Uniform allocation failed");
		}

		// Print stats
		let stats = transient.GetStats();
		Console.WriteLine("\nTransient Buffer Stats (Frame 0):");
		Console.WriteLine("  Vertex: {0}/{1} bytes ({2:F1}%)", stats.VertexBytesUsed, stats.VertexBytesTotal, stats.VertexUsagePercent);
		Console.WriteLine("  Index: {0}/{1} bytes ({2:F1}%)", stats.IndexBytesUsed, stats.IndexBytesTotal, stats.IndexUsagePercent);
		Console.WriteLine("  Uniform: {0}/{1} bytes ({2:F1}%)", stats.UniformBytesUsed, stats.UniformBytesTotal, stats.UniformUsagePercent);

		// Test frame reset
		Console.WriteLine("\nTesting frame reset (Frame 1)...");
		transient.BeginFrame(1);
		let statsAfterReset = transient.GetStats();
		Console.WriteLine("  Vertex after reset: {0} bytes", statsAfterReset.VertexBytesUsed);
		Console.WriteLine("  Index after reset: {0} bytes", statsAfterReset.IndexBytesUsed);
		Console.WriteLine("  Uniform after reset: {0} bytes", statsAfterReset.UniformBytesUsed);

		// Verify all are zero
		let allReset = statsAfterReset.VertexBytesUsed == 0 &&
					   statsAfterReset.IndexBytesUsed == 0 &&
					   statsAfterReset.UniformBytesUsed == 0;
		Console.WriteLine("  All buffers reset: {0}", allReset);

		Console.WriteLine("\nTransient Buffer Pool tests complete!");
	}
}
