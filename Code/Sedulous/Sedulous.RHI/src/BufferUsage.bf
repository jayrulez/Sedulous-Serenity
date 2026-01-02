namespace Sedulous.RHI;

/// Flags describing how a buffer will be used.
//[Flags]
enum BufferUsage
{
	None = 0,
	/// Buffer can be used as source for copy operations.
	CopySrc = 1 << 0,
	/// Buffer can be used as destination for copy operations.
	CopyDst = 1 << 1,
	/// Buffer can be used as a vertex buffer.
	Vertex = 1 << 2,
	/// Buffer can be used as an index buffer.
	Index = 1 << 3,
	/// Buffer can be used as a uniform buffer.
	Uniform = 1 << 4,
	/// Buffer can be used as a storage buffer.
	Storage = 1 << 5,
	/// Buffer can be used for indirect draw/dispatch commands.
	Indirect = 1 << 6,
	/// Buffer can be mapped for reading.
	MapRead = 1 << 7,
	/// Buffer can be mapped for writing.
	MapWrite = 1 << 8,
}
