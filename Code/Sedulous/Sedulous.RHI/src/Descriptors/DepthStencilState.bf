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
	/// Enable depth testing.
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

	/// Depth test without writing.
	public static Self ReadOnly => .() { DepthWriteEnabled = false };
}
