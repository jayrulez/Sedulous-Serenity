namespace Sedulous.RHI;

/// Binding shifts for Vulkan to prevent resource binding slot conflicts.
/// These shifts separate different HLSL register types into non-overlapping Vulkan binding ranges.
///
/// When compiling HLSL to SPIRV and when creating Vulkan descriptor layouts,
/// the same shifts must be applied to ensure bindings match.
///
/// Usage:
/// - HLSL register(b0) -> Vulkan binding 0 (constant buffers)
/// - HLSL register(t0) -> Vulkan binding 1000 (textures/SRVs)
/// - HLSL register(u0) -> Vulkan binding 2000 (UAVs/storage)
/// - HLSL register(s0) -> Vulkan binding 3000 (samplers)
static class VulkanBindingShifts
{
	/// Shift for constant buffer (b) registers.
	/// HLSL: register(bN) -> Vulkan binding N + SHIFT_B
	public const uint32 SHIFT_B = 0;

	/// Shift for texture/SRV (t) registers.
	/// HLSL: register(tN) -> Vulkan binding N + SHIFT_T
	public const uint32 SHIFT_T = 1000;

	/// Shift for UAV (u) registers.
	/// HLSL: register(uN) -> Vulkan binding N + SHIFT_U
	public const uint32 SHIFT_U = 2000;

	/// Shift for sampler (s) registers.
	/// HLSL: register(sN) -> Vulkan binding N + SHIFT_S
	public const uint32 SHIFT_S = 3000;

	/// Gets the binding shift for a given binding type.
	public static uint32 GetShift(BindingType type)
	{
		switch (type)
		{
		case .UniformBuffer:
			return SHIFT_B;
		case .SampledTexture, .StorageBuffer:
			// Read-only resources use T (SRV) bindings
			return SHIFT_T;
		case .StorageBufferReadWrite, .StorageTexture, .StorageTextureReadWrite:
			// Read-write resources use U (UAV) bindings
			return SHIFT_U;
		case .Sampler, .ComparisonSampler:
			return SHIFT_S;
		}
	}
}
