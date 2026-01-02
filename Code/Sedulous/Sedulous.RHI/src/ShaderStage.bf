namespace Sedulous.RHI;

/// Shader stages in the graphics pipeline.
//[Flags]
enum ShaderStage
{
	None = 0,
	/// Vertex shader stage.
	Vertex = 1 << 0,
	/// Fragment (pixel) shader stage.
	Fragment = 1 << 1,
	/// Compute shader stage.
	Compute = 1 << 2,
}
