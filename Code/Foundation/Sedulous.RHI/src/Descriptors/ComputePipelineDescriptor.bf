using System;
namespace Sedulous.RHI;

/// Describes a compute pipeline.
struct ComputePipelineDescriptor
{
	/// Pipeline layout (bind group layouts).
	public IPipelineLayout Layout;
	/// Compute shader stage.
	public ProgrammableStage Compute;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Layout = null;
		Compute = .();
		Label = default;
	}

	public this(IPipelineLayout layout, IShaderModule shader, StringView entryPoint = "main")
	{
		Layout = layout;
		Compute = .(shader, entryPoint);
		Label = default;
	}
}
