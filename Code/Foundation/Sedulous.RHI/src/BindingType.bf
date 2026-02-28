namespace Sedulous.RHI;

/// Type of resource binding in a bind group.
enum BindingType
{
	/// Uniform buffer binding.
	UniformBuffer,
	/// Storage buffer binding (read-only).
	StorageBuffer,
	/// Storage buffer binding (read-write).
	StorageBufferReadWrite,
	/// Sampled texture binding.
	SampledTexture,
	/// Storage texture binding (read-only).
	StorageTexture,
	/// Storage texture binding (read-write).
	StorageTextureReadWrite,
	/// Sampler binding.
	Sampler,
	/// Comparison sampler binding (for shadow maps).
	ComparisonSampler,
}
