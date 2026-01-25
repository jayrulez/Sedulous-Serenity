namespace Sedulous.Drawing.Renderer;

using System;

/// Interface for providing custom shaders to DrawingRenderer.
public interface IDrawingShaderProvider
{
	/// Get the vertex shader HLSL source.
	void GetVertexShaderSource(String outSource);

	/// Get the fragment shader HLSL source.
	void GetFragmentShaderSource(String outSource);
}
