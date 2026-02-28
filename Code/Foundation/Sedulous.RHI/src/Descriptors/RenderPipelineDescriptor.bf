namespace Sedulous.RHI;

using System;

/// Describes a programmable shader stage.
struct ProgrammableStage
{
	/// Shader module containing the code.
	public IShaderModule Module;
	/// Entry point function name.
	public StringView EntryPoint;

	public this()
	{
		Module = null;
		EntryPoint = "main";
	}

	public this(IShaderModule module, StringView entryPoint = "main")
	{
		Module = module;
		EntryPoint = entryPoint;
	}
}

/// Describes vertex state for a render pipeline.
struct VertexState
{
	/// Vertex shader stage.
	public ProgrammableStage Shader;
	/// Vertex buffer layouts.
	public Span<VertexBufferLayout> Buffers;

	public this()
	{
		Shader = .();
		Buffers = default;
	}
}

/// Describes fragment state for a render pipeline.
struct FragmentState
{
	/// Fragment shader stage.
	public ProgrammableStage Shader;
	/// Color targets.
	public Span<ColorTargetState> Targets;

	public this()
	{
		Shader = .();
		Targets = default;
	}
}

/// Describes a render pipeline.
struct RenderPipelineDescriptor
{
	/// Pipeline layout (bind group layouts).
	public IPipelineLayout Layout;
	/// Vertex stage.
	public VertexState Vertex;
	/// Fragment stage (optional for depth-only passes).
	public FragmentState? Fragment;
	/// Primitive assembly state.
	public PrimitiveState Primitive;
	/// Depth/stencil state (optional).
	public DepthStencilState? DepthStencil;
	/// Multisample state.
	public MultisampleState Multisample;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Layout = null;
		Vertex = .();
		Fragment = null;
		Primitive = .();
		DepthStencil = null;
		Multisample = .();
		Label = default;
	}
}
