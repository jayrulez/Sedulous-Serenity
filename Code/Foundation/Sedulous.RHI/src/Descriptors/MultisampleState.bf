namespace Sedulous.RHI;

/// Describes multisample state for a render pipeline.
struct MultisampleState
{
	/// Number of samples per pixel.
	public uint32 Count;
	/// Sample mask.
	public uint32 Mask;
	/// Enable alpha-to-coverage.
	public bool AlphaToCoverageEnabled;

	public this()
	{
		Count = 1;
		Mask = 0xFFFFFFFF;
		AlphaToCoverageEnabled = false;
	}

	/// No multisampling.
	public static Self None => .();

	/// 4x MSAA.
	public static Self MSAA4x => .() { Count = 4 };
}
