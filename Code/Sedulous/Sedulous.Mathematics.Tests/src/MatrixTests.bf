using System;

namespace Sedulous.Mathematics.Tests;

class MatrixTests
{
	// ---- Matrix3x3 Tests ----

	[Test]
	public static void TestMatrix3x3Identity()
	{
		let identity = Matrix3x3.Identity;
		Test.Assert(identity.M11 == 1.0f && identity.M22 == 1.0f && identity.M33 == 1.0f);
		Test.Assert(identity.M12 == 0.0f && identity.M13 == 0.0f);
		Test.Assert(identity.M21 == 0.0f && identity.M23 == 0.0f);
		Test.Assert(identity.M31 == 0.0f && identity.M32 == 0.0f);
	}

	[Test]
	public static void TestMatrix3x3ColumnMajorLayout()
	{
		// Verify column-major storage: columns are contiguous
		let m = Matrix3x3(
			1, 2, 3,
			4, 5, 6,
			7, 8, 9
		);

		// Column 0 should be (1, 4, 7)
		Test.Assert(m.Column0 == Vector3(1, 4, 7));
		// Column 1 should be (2, 5, 8)
		Test.Assert(m.Column1 == Vector3(2, 5, 8));
		// Column 2 should be (3, 6, 9)
		Test.Assert(m.Column2 == Vector3(3, 6, 9));

		// Row 0 should be (1, 2, 3)
		Test.Assert(m.Row0 == Vector3(1, 2, 3));
	}

	[Test]
	public static void TestMatrix3x3Determinant()
	{
		let identity = Matrix3x3.Identity;
		Test.Assert(MathUtil.Approximately(identity.Determinant, 1.0f));

		let scale = Matrix3x3.CreateScale(2.0f);
		Test.Assert(MathUtil.Approximately(scale.Determinant, 8.0f)); // 2^3 = 8
	}

	[Test]
	public static void TestMatrix3x3Transpose()
	{
		let m = Matrix3x3(
			1, 2, 3,
			4, 5, 6,
			7, 8, 9
		);

		let transposed = m.Transposed;
		Test.Assert(transposed.M11 == 1.0f && transposed.M12 == 4.0f && transposed.M13 == 7.0f);
		Test.Assert(transposed.M21 == 2.0f && transposed.M22 == 5.0f && transposed.M23 == 8.0f);
		Test.Assert(transposed.M31 == 3.0f && transposed.M32 == 6.0f && transposed.M33 == 9.0f);
	}

	[Test]
	public static void TestMatrix3x3Multiplication()
	{
		let identity = Matrix3x3.Identity;
		let m = Matrix3x3(
			1, 2, 3,
			4, 5, 6,
			7, 8, 9
		);

		// Multiply by identity should give same matrix
		let result = identity * m;
		Test.Assert(result == m);

		// Also test m * identity
		let result2 = m * identity;
		Test.Assert(result2 == m);
	}

	[Test]
	public static void TestMatrix3x3VectorTransform()
	{
		let scale = Matrix3x3.CreateScale(2.0f);
		let v = Vector3(1.0f, 2.0f, 3.0f);
		let transformed = scale * v;
		Test.Assert(transformed == Vector3(2.0f, 4.0f, 6.0f));
	}

	[Test]
	public static void TestMatrix3x3RotationX()
	{
		let rot = Matrix3x3.CreateRotationX(MathUtil.PiOver2);
		let v = Vector3.UnitY;
		let rotated = rot * v;
		// Rotating Y by 90 degrees around X should give Z
		Test.Assert(MathUtil.Approximately(rotated.X, 0.0f));
		Test.Assert(MathUtil.Approximately(rotated.Y, 0.0f));
		Test.Assert(MathUtil.Approximately(rotated.Z, 1.0f));
	}

	[Test]
	public static void TestMatrix3x3RotationY()
	{
		let rot = Matrix3x3.CreateRotationY(MathUtil.PiOver2);
		let v = Vector3.UnitZ;
		let rotated = rot * v;
		// Rotating Z by 90 degrees around Y should give X
		Test.Assert(MathUtil.Approximately(rotated.X, 1.0f));
		Test.Assert(MathUtil.Approximately(rotated.Y, 0.0f));
		Test.Assert(MathUtil.Approximately(rotated.Z, 0.0f));
	}

	[Test]
	public static void TestMatrix3x3RotationZ()
	{
		let rot = Matrix3x3.CreateRotationZ(MathUtil.PiOver2);
		let v = Vector3.UnitX;
		let rotated = rot * v;
		// Rotating X by 90 degrees around Z should give Y
		Test.Assert(MathUtil.Approximately(rotated.X, 0.0f));
		Test.Assert(MathUtil.Approximately(rotated.Y, 1.0f));
		Test.Assert(MathUtil.Approximately(rotated.Z, 0.0f));
	}

	[Test]
	public static void TestMatrix3x3Invert()
	{
		let scale = Matrix3x3.CreateScale(2.0f);
		let inverse = scale.Inverse();
		let product = scale * inverse;

		// Should be approximately identity
		Test.Assert(MathUtil.Approximately(product.M11, 1.0f));
		Test.Assert(MathUtil.Approximately(product.M22, 1.0f));
		Test.Assert(MathUtil.Approximately(product.M33, 1.0f));
		Test.Assert(MathUtil.Approximately(product.M12, 0.0f));
	}

	// ---- Matrix4x4 Tests ----

	[Test]
	public static void TestMatrix4x4Identity()
	{
		let identity = Matrix4x4.Identity;
		Test.Assert(identity.M11 == 1.0f && identity.M22 == 1.0f && identity.M33 == 1.0f && identity.M44 == 1.0f);
		Test.Assert(identity.M12 == 0.0f && identity.M13 == 0.0f && identity.M14 == 0.0f);
	}

	[Test]
	public static void TestMatrix4x4ColumnMajorLayout()
	{
		let m = Matrix4x4(
			1, 2, 3, 4,
			5, 6, 7, 8,
			9, 10, 11, 12,
			13, 14, 15, 16
		);

		// Column 0 should be (1, 5, 9, 13)
		Test.Assert(m.Column0 == Vector4(1, 5, 9, 13));
		// Column 3 should be (4, 8, 12, 16)
		Test.Assert(m.Column3 == Vector4(4, 8, 12, 16));

		// Row 0 should be (1, 2, 3, 4)
		Test.Assert(m.Row0 == Vector4(1, 2, 3, 4));
	}

	[Test]
	public static void TestMatrix4x4Translation()
	{
		let translation = Matrix4x4.CreateTranslation(10.0f, 20.0f, 30.0f);
		Test.Assert(translation.Translation == Vector3(10, 20, 30));

		let point = Vector3(1.0f, 2.0f, 3.0f);
		let transformed = translation.TransformPoint(point);
		Test.Assert(transformed == Vector3(11, 22, 33));
	}

	[Test]
	public static void TestMatrix4x4TranslationDirection()
	{
		// Directions should not be affected by translation
		let translation = Matrix4x4.CreateTranslation(100.0f, 100.0f, 100.0f);
		let direction = Vector3.UnitX;
		let transformed = translation.TransformDirection(direction);
		Test.Assert(transformed == Vector3.UnitX);
	}

	[Test]
	public static void TestMatrix4x4Scale()
	{
		let scale = Matrix4x4.CreateScale(2.0f, 3.0f, 4.0f);
		let point = Vector3(1.0f, 1.0f, 1.0f);
		let transformed = scale.TransformPoint(point);
		Test.Assert(transformed == Vector3(2, 3, 4));
	}

	[Test]
	public static void TestMatrix4x4RotationX()
	{
		let rot = Matrix4x4.CreateRotationX(MathUtil.PiOver2);
		let v = Vector3.UnitY;
		let rotated = rot.TransformDirection(v);
		Test.Assert(MathUtil.Approximately(rotated.X, 0.0f));
		Test.Assert(MathUtil.Approximately(rotated.Y, 0.0f));
		Test.Assert(MathUtil.Approximately(rotated.Z, 1.0f));
	}

	[Test]
	public static void TestMatrix4x4Multiplication()
	{
		let translation = Matrix4x4.CreateTranslation(10, 0, 0);
		let scale = Matrix4x4.CreateScale(2.0f);

		// Scale then translate
		let combined = translation * scale;
		let point = Vector3(1, 0, 0);
		let transformed = combined.TransformPoint(point);
		// Point scaled to (2, 0, 0) then translated to (12, 0, 0)
		Test.Assert(transformed == Vector3(12, 0, 0));
	}

	[Test]
	public static void TestMatrix4x4Determinant()
	{
		let identity = Matrix4x4.Identity;
		Test.Assert(MathUtil.Approximately(identity.Determinant, 1.0f));

		let scale = Matrix4x4.CreateScale(2.0f);
		Test.Assert(MathUtil.Approximately(scale.Determinant, 8.0f)); // 2^3 = 8 (w component is 1)
	}

	[Test]
	public static void TestMatrix4x4Transpose()
	{
		let m = Matrix4x4(
			1, 2, 3, 4,
			5, 6, 7, 8,
			9, 10, 11, 12,
			13, 14, 15, 16
		);

		let transposed = m.Transposed;
		// First row becomes first column
		Test.Assert(transposed.Column0 == Vector4(1, 2, 3, 4));
		// First column becomes first row
		Test.Assert(transposed.Row0 == Vector4(1, 5, 9, 13));
	}

	[Test]
	public static void TestMatrix4x4Invert()
	{
		let translation = Matrix4x4.CreateTranslation(10, 20, 30);
		let inverse = translation.Inverse();
		let product = translation * inverse;

		// Should be approximately identity
		Test.Assert(MathUtil.Approximately(product.M11, 1.0f));
		Test.Assert(MathUtil.Approximately(product.M22, 1.0f));
		Test.Assert(MathUtil.Approximately(product.M33, 1.0f));
		Test.Assert(MathUtil.Approximately(product.M44, 1.0f));
		Test.Assert(MathUtil.Approximately(product.M14, 0.0f));
		Test.Assert(MathUtil.Approximately(product.M24, 0.0f));
		Test.Assert(MathUtil.Approximately(product.M34, 0.0f));
	}

	[Test]
	public static void TestMatrix4x4LookAt()
	{
		let eye = Vector3(0, 0, 5);
		let target = Vector3.Zero;
		let up = Vector3.Up;
		let view = Matrix4x4.CreateLookAt(eye, target, up);

		// In OpenGL right-handed convention, camera looks down -Z
		// Origin is 5 units in front of camera, so Z = -5 in view space
		let originInView = view.TransformPoint(Vector3.Zero);
		Test.Assert(MathUtil.Approximately(originInView.X, 0.0f));
		Test.Assert(MathUtil.Approximately(originInView.Y, 0.0f));
		Test.Assert(MathUtil.Approximately(originInView.Z, -5.0f));
	}

	[Test]
	public static void TestMatrix4x4Upper3x3()
	{
		let rot = Matrix4x4.CreateRotationZ(MathUtil.PiOver2);
		let upper = rot.Upper3x3;

		// Should extract just the rotation part
		let v = Vector3.UnitX;
		let rotated = upper * v;
		Test.Assert(MathUtil.Approximately(rotated.X, 0.0f));
		Test.Assert(MathUtil.Approximately(rotated.Y, 1.0f));
		Test.Assert(MathUtil.Approximately(rotated.Z, 0.0f));
	}

	[Test]
	public static void TestMatrix4x4TRS()
	{
		let translation = Vector3(10, 20, 30);
		let rotation = Matrix3x3.CreateRotationZ(MathUtil.PiOver2);
		let scale = Vector3(2, 2, 2);

		let trs = Matrix4x4.CreateTRS(translation, rotation, scale);

		// Transform a point: first scale, then rotate, then translate
		let point = Vector3.UnitX;
		let transformed = trs.TransformPoint(point);
		// UnitX scaled by 2 = (2, 0, 0)
		// Rotated 90 around Z = (0, 2, 0)
		// Translated = (10, 22, 30)
		Test.Assert(MathUtil.Approximately(transformed.X, 10.0f));
		Test.Assert(MathUtil.Approximately(transformed.Y, 22.0f));
		Test.Assert(MathUtil.Approximately(transformed.Z, 30.0f));
	}

	[Test]
	public static void TestMatrix4x4VectorTransform()
	{
		let scale = Matrix4x4.CreateScale(2.0f);
		let v = Vector4(1, 2, 3, 1);
		let transformed = scale * v;
		Test.Assert(transformed == Vector4(2, 4, 6, 1));
	}
}
