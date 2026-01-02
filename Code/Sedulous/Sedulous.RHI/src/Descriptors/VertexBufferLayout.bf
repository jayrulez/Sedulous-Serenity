namespace Sedulous.RHI;

using System;

/// Describes a vertex attribute within a vertex buffer.
struct VertexAttribute
{
	/// Attribute format.
	public VertexFormat Format;
	/// Byte offset within the vertex.
	public uint64 Offset;
	/// Shader location this attribute maps to.
	public uint32 ShaderLocation;

	public this()
	{
		Format = .Float3;
		Offset = 0;
		ShaderLocation = 0;
	}

	public this(VertexFormat format, uint64 offset, uint32 shaderLocation)
	{
		Format = format;
		Offset = offset;
		ShaderLocation = shaderLocation;
	}
}

/// Describes a vertex buffer layout.
struct VertexBufferLayout
{
	/// Byte stride between consecutive vertices.
	public uint64 ArrayStride;
	/// Whether data advances per vertex or per instance.
	public VertexStepMode StepMode;
	/// Vertex attributes in this buffer.
	public Span<VertexAttribute> Attributes;

	public this()
	{
		ArrayStride = 0;
		StepMode = .Vertex;
		Attributes = default;
	}

	public this(uint64 arrayStride, Span<VertexAttribute> attributes, VertexStepMode stepMode = .Vertex)
	{
		ArrayStride = arrayStride;
		StepMode = stepMode;
		Attributes = attributes;
	}
}
