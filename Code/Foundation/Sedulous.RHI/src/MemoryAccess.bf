namespace Sedulous.RHI;

/// Memory access hints for resource allocation.
enum MemoryAccess
{
	/// Resource lives only on GPU. Fastest for GPU access.
	GpuOnly,
	/// Resource is optimized for CPU upload to GPU (staging buffer for uploads).
	Upload,
	/// Resource is optimized for GPU to CPU readback.
	Readback,
}
