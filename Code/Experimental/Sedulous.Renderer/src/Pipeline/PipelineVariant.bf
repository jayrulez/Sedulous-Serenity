namespace Sedulous.Renderer;

using System;

/// Flags that produce distinct shader/pipeline variants.
/// Each flag maps to a #define during shader compilation.
public enum PipelineVariantFlags : uint32
{
	None            = 0,
	Instanced       = 1 << 0,
	Skinned         = 1 << 1,
	ReceiveShadows  = 1 << 2,
	AlphaTest       = 1 << 3,
	MotionVectors   = 1 << 4,
	DepthOnly       = 1 << 5,
	ShadowCaster    = 1 << 6,
	GPUDriven       = 1 << 7,
	HiZMip0         = 1 << 8,
	Passthrough     = 1 << 9,
}
