namespace Sedulous.Framework.Renderer;

using Sedulous.Mathematics;
using System;

/// Per-instance GPU data (80 bytes) - transform matrix rows + color.
[CRepr]
struct RenderSceneInstanceData
{
	public Vector4 Row0;
	public Vector4 Row1;
	public Vector4 Row2;
	public Vector4 Row3;
	public Vector4 Color;

	public this(Matrix transform, Vector4 color)
	{
		Row0 = .(transform.M11, transform.M12, transform.M13, transform.M14);
		Row1 = .(transform.M21, transform.M22, transform.M23, transform.M24);
		Row2 = .(transform.M31, transform.M32, transform.M33, transform.M34);
		Row3 = .(transform.M41, transform.M42, transform.M43, transform.M44);
		Color = color;
	}
}
