namespace Sedulous.RHI;

using System;

/// Describes a pipeline layout.
struct PipelineLayoutDescriptor
{
	/// Bind group layouts used by this pipeline.
	public Span<IBindGroupLayout> BindGroupLayouts;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		BindGroupLayouts = default;
		Label = default;
	}

	public this(Span<IBindGroupLayout> bindGroupLayouts)
	{
		BindGroupLayouts = bindGroupLayouts;
		Label = default;
	}
}
