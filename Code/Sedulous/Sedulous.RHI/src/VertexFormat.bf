namespace Sedulous.RHI;

/// Vertex attribute formats.
enum VertexFormat
{
	// 8-bit formats
	UByte2,
	UByte4,
	Byte2,
	Byte4,
	UByte2Normalized,
	UByte4Normalized,
	Byte2Normalized,
	Byte4Normalized,

	// 16-bit formats
	UShort2,
	UShort4,
	Short2,
	Short4,
	UShort2Normalized,
	UShort4Normalized,
	Short2Normalized,
	Short4Normalized,
	Half2,
	Half4,

	// 32-bit formats
	Float,
	Float2,
	Float3,
	Float4,
	UInt,
	UInt2,
	UInt3,
	UInt4,
	Int,
	Int2,
	Int3,
	Int4,
}
