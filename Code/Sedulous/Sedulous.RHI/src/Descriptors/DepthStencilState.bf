namespace Sedulous.RHI;

/// Describes stencil face state.
struct StencilFaceState
{
	/// Comparison function.
	public CompareFunction Compare;
	/// Operation when stencil test fails.
	public StencilOperation FailOp;
	/// Operation when depth test fails.
	public StencilOperation DepthFailOp;
	/// Operation when both tests pass.
	public StencilOperation PassOp;

	public this()
	{
		Compare = .Always;
		FailOp = .Keep;
		DepthFailOp = .Keep;
		PassOp = .Keep;
	}
}

/// Describes depth/stencil state for a render pipeline.
struct DepthStencilState
{
	/// Depth/stencil texture format.
	public TextureFormat Format;
	/// Enable depth testing (comparison against depth buffer).
	public bool DepthTestEnabled;
	/// Enable depth writing (updating the depth buffer).
	public bool DepthWriteEnabled;
	/// Depth comparison function.
	public CompareFunction DepthCompare;
	/// Stencil state for front-facing triangles.
	public StencilFaceState StencilFront;
	/// Stencil state for back-facing triangles.
	public StencilFaceState StencilBack;
	/// Stencil read mask.
	public uint32 StencilReadMask;
	/// Stencil write mask.
	public uint32 StencilWriteMask;
	/// Depth bias constant factor.
	public int32 DepthBias;
	/// Depth bias slope factor.
	public float DepthBiasSlopeScale;
	/// Depth bias clamp.
	public float DepthBiasClamp;

	public this()
	{
		Format = .Depth24PlusStencil8;
		DepthTestEnabled = true;
		DepthWriteEnabled = true;
		DepthCompare = .Less;
		StencilFront = .();
		StencilBack = .();
		StencilReadMask = 0xFF;
		StencilWriteMask = 0xFF;
		DepthBias = 0;
		DepthBiasSlopeScale = 0.0f;
		DepthBiasClamp = 0.0f;
	}

	/// Default depth test (less-than, write enabled).
	public static Self Default => .();

	/// No depth testing or writing (no depth attachment).
	public static Self None => .() { Format = .Undefined, DepthTestEnabled = false, DepthWriteEnabled = false };

	/// Depth test without writing.
	public static Self ReadOnly => .() { DepthWriteEnabled = false };

	// ===== Common Presets =====

	/// Opaque geometry: depth test + write with less-than comparison.
	/// Use for solid objects that should write to and test against the depth buffer.
	public static Self Opaque => Default;

	/// Transparent geometry: depth test only, no writing.
	/// Use for blended objects - they should be depth-sorted but not occlude each other.
	public static Self Transparent => ReadOnly;

	/// Skybox/background: depth test with less-equal, no writing.
	/// Use for rendering at the far plane (z=1) after opaque geometry.
	public static Self Skybox => .() { DepthWriteEnabled = false, DepthCompare = .LessEqual };

	/// Creates a shadow map depth state with bias to reduce shadow acne.
	/// @param bias Constant depth bias (typically 1-4)
	/// @param slopeScale Slope-scaled depth bias (typically 1.0-4.0)
	public static Self Shadow(int32 bias = 2, float slopeScale = 2.0f) =>
		.() { Format = .Depth32Float, DepthBias = bias, DepthBiasSlopeScale = slopeScale };
}
