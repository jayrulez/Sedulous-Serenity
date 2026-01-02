using System;

namespace Sedulous.Mathematics.Tests;

class VectorTests
{
	// ---- Vector2 Tests ----

	[Test]
	public static void TestVector2Construction()
	{
		let v1 = Vector2(3.0f);
		Test.Assert(v1.X == 3.0f && v1.Y == 3.0f);

		let v2 = Vector2(1.0f, 2.0f);
		Test.Assert(v2.X == 1.0f && v2.Y == 2.0f);
	}

	[Test]
	public static void TestVector2StaticProperties()
	{
		Test.Assert(Vector2.Zero == Vector2(0, 0));
		Test.Assert(Vector2.One == Vector2(1, 1));
		Test.Assert(Vector2.UnitX == Vector2(1, 0));
		Test.Assert(Vector2.UnitY == Vector2(0, 1));
	}

	[Test]
	public static void TestVector2Length()
	{
		let v = Vector2(3.0f, 4.0f);
		Test.Assert(MathUtil.Approximately(v.Length, 5.0f));
		Test.Assert(MathUtil.Approximately(v.LengthSquared, 25.0f));
	}

	[Test]
	public static void TestVector2Normalize()
	{
		let v = Vector2(3.0f, 4.0f);
		let normalized = v.Normalized;
		Test.Assert(MathUtil.Approximately(normalized.Length, 1.0f));
		Test.Assert(MathUtil.Approximately(normalized.X, 0.6f));
		Test.Assert(MathUtil.Approximately(normalized.Y, 0.8f));
	}

	[Test]
	public static void TestVector2Operators()
	{
		let a = Vector2(1.0f, 2.0f);
		let b = Vector2(3.0f, 4.0f);

		let add = a + b;
		Test.Assert(add == Vector2(4.0f, 6.0f));

		let sub = b - a;
		Test.Assert(sub == Vector2(2.0f, 2.0f));

		let mul = a * b;
		Test.Assert(mul == Vector2(3.0f, 8.0f));

		let scale = a * 2.0f;
		Test.Assert(scale == Vector2(2.0f, 4.0f));

		let neg = -a;
		Test.Assert(neg == Vector2(-1.0f, -2.0f));
	}

	[Test]
	public static void TestVector2Dot()
	{
		let a = Vector2(1.0f, 2.0f);
		let b = Vector2(3.0f, 4.0f);
		Test.Assert(MathUtil.Approximately(Vector2.Dot(a, b), 11.0f));
	}

	[Test]
	public static void TestVector2Distance()
	{
		let a = Vector2(0.0f, 0.0f);
		let b = Vector2(3.0f, 4.0f);
		Test.Assert(MathUtil.Approximately(Vector2.Distance(a, b), 5.0f));
	}

	[Test]
	public static void TestVector2Lerp()
	{
		let a = Vector2(0.0f, 0.0f);
		let b = Vector2(10.0f, 20.0f);
		let mid = Vector2.Lerp(a, b, 0.5f);
		Test.Assert(mid == Vector2(5.0f, 10.0f));
	}

	// ---- Vector3 Tests ----

	[Test]
	public static void TestVector3Construction()
	{
		let v1 = Vector3(3.0f);
		Test.Assert(v1.X == 3.0f && v1.Y == 3.0f && v1.Z == 3.0f);

		let v2 = Vector3(1.0f, 2.0f, 3.0f);
		Test.Assert(v2.X == 1.0f && v2.Y == 2.0f && v2.Z == 3.0f);

		let v3 = Vector3(Vector2(1.0f, 2.0f), 3.0f);
		Test.Assert(v3 == Vector3(1.0f, 2.0f, 3.0f));
	}

	[Test]
	public static void TestVector3StaticProperties()
	{
		Test.Assert(Vector3.Zero == Vector3(0, 0, 0));
		Test.Assert(Vector3.One == Vector3(1, 1, 1));
		Test.Assert(Vector3.UnitX == Vector3(1, 0, 0));
		Test.Assert(Vector3.UnitY == Vector3(0, 1, 0));
		Test.Assert(Vector3.UnitZ == Vector3(0, 0, 1));
		Test.Assert(Vector3.Up == Vector3(0, 1, 0));
		Test.Assert(Vector3.Forward == Vector3(0, 0, -1));
	}

	[Test]
	public static void TestVector3Length()
	{
		let v = Vector3(2.0f, 3.0f, 6.0f);
		Test.Assert(MathUtil.Approximately(v.Length, 7.0f));
		Test.Assert(MathUtil.Approximately(v.LengthSquared, 49.0f));
	}

	[Test]
	public static void TestVector3Normalize()
	{
		let v = Vector3(0.0f, 0.0f, 5.0f);
		let normalized = v.Normalized;
		Test.Assert(MathUtil.Approximately(normalized.Length, 1.0f));
		Test.Assert(normalized == Vector3(0, 0, 1));
	}

	[Test]
	public static void TestVector3Cross()
	{
		let x = Vector3.UnitX;
		let y = Vector3.UnitY;
		let z = Vector3.Cross(x, y);
		Test.Assert(z == Vector3.UnitZ);

		let negX = Vector3.Cross(y, z);
		Test.Assert(negX == Vector3.UnitX);
	}

	[Test]
	public static void TestVector3Dot()
	{
		let a = Vector3(1.0f, 2.0f, 3.0f);
		let b = Vector3(4.0f, 5.0f, 6.0f);
		Test.Assert(MathUtil.Approximately(Vector3.Dot(a, b), 32.0f));
	}

	[Test]
	public static void TestVector3Reflect()
	{
		let incoming = Vector3(1.0f, -1.0f, 0.0f);
		let normal = Vector3.Up;
		let reflected = Vector3.Reflect(incoming, normal);
		Test.Assert(MathUtil.Approximately(reflected.X, 1.0f));
		Test.Assert(MathUtil.Approximately(reflected.Y, 1.0f));
		Test.Assert(MathUtil.Approximately(reflected.Z, 0.0f));
	}

	[Test]
	public static void TestVector3Project()
	{
		let v = Vector3(3.0f, 4.0f, 0.0f);
		let onto = Vector3.UnitX;
		let projected = Vector3.Project(v, onto);
		Test.Assert(projected == Vector3(3.0f, 0.0f, 0.0f));
	}

	// ---- Vector4 Tests ----

	[Test]
	public static void TestVector4Construction()
	{
		let v1 = Vector4(3.0f);
		Test.Assert(v1.X == 3.0f && v1.Y == 3.0f && v1.Z == 3.0f && v1.W == 3.0f);

		let v2 = Vector4(1.0f, 2.0f, 3.0f, 4.0f);
		Test.Assert(v2.X == 1.0f && v2.Y == 2.0f && v2.Z == 3.0f && v2.W == 4.0f);

		let v3 = Vector4(Vector3(1.0f, 2.0f, 3.0f), 4.0f);
		Test.Assert(v3 == Vector4(1.0f, 2.0f, 3.0f, 4.0f));
	}

	[Test]
	public static void TestVector4Length()
	{
		let v = Vector4(1.0f, 2.0f, 2.0f, 0.0f);
		Test.Assert(MathUtil.Approximately(v.Length, 3.0f));
	}

	[Test]
	public static void TestVector4Swizzle()
	{
		let v = Vector4(1.0f, 2.0f, 3.0f, 4.0f);
		Test.Assert(v.XY == Vector2(1.0f, 2.0f));
		Test.Assert(v.XYZ == Vector3(1.0f, 2.0f, 3.0f));
	}

	[Test]
	public static void TestVector4Dot()
	{
		let a = Vector4(1.0f, 2.0f, 3.0f, 4.0f);
		let b = Vector4(5.0f, 6.0f, 7.0f, 8.0f);
		// 1*5 + 2*6 + 3*7 + 4*8 = 5 + 12 + 21 + 32 = 70
		Test.Assert(MathUtil.Approximately(Vector4.Dot(a, b), 70.0f));
	}
}
