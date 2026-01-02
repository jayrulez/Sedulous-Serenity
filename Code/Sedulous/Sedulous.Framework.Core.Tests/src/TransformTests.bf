using System;
using Sedulous.Framework.Core;
using Sedulous.Mathematics;

namespace Sedulous.Framework.Core.Tests;

class TransformTests
{
	[Test]
	public static void TestIdentity()
	{
		var transform = Transform.Identity;
		Test.Assert(transform.Position == Vector3.Zero);
		Test.Assert(transform.Rotation == Quaternion.Identity);
		Test.Assert(transform.Scale == Vector3(1, 1, 1));
	}

	[Test]
	public static void TestSetPosition()
	{
		var transform = Transform.Identity;
		transform.SetPosition(.(10, 20, 30));

		Test.Assert(transform.Position.X == 10);
		Test.Assert(transform.Position.Y == 20);
		Test.Assert(transform.Position.Z == 30);
	}

	[Test]
	public static void TestSetScale()
	{
		var transform = Transform.Identity;
		transform.SetScale(.(2, 3, 4));

		Test.Assert(transform.Scale.X == 2);
		Test.Assert(transform.Scale.Y == 3);
		Test.Assert(transform.Scale.Z == 4);
	}

	[Test]
	public static void TestTranslate()
	{
		var transform = Transform.Identity;
		transform.SetPosition(.(5, 5, 5));
		transform.Translate(.(1, 2, 3));

		Test.Assert(transform.Position.X == 6);
		Test.Assert(transform.Position.Y == 7);
		Test.Assert(transform.Position.Z == 8);
	}

	[Test]
	public static void TestLocalMatrixIdentity()
	{
		var transform = Transform.Identity;
		let matrix = transform.LocalMatrix;

		// Should be identity matrix
		Test.Assert(Math.Abs(matrix.M11 - 1) < 0.0001f);
		Test.Assert(Math.Abs(matrix.M22 - 1) < 0.0001f);
		Test.Assert(Math.Abs(matrix.M33 - 1) < 0.0001f);
		Test.Assert(Math.Abs(matrix.M44 - 1) < 0.0001f);
	}

	[Test]
	public static void TestLocalMatrixTranslation()
	{
		var transform = Transform.Identity;
		transform.SetPosition(.(10, 20, 30));
		let matrix = transform.LocalMatrix;

		// Translation should be in M14, M24, M34 (column 4)
		Test.Assert(Math.Abs(matrix.M14 - 10) < 0.0001f);
		Test.Assert(Math.Abs(matrix.M24 - 20) < 0.0001f);
		Test.Assert(Math.Abs(matrix.M34 - 30) < 0.0001f);
	}

	[Test]
	public static void TestLocalMatrixScale()
	{
		var transform = Transform.Identity;
		transform.SetScale(.(2, 3, 4));
		let matrix = transform.LocalMatrix;

		// Scale should be on diagonal
		Test.Assert(Math.Abs(matrix.M11 - 2) < 0.0001f);
		Test.Assert(Math.Abs(matrix.M22 - 3) < 0.0001f);
		Test.Assert(Math.Abs(matrix.M33 - 4) < 0.0001f);
	}

	[Test]
	public static void TestWorldMatrixUpdate()
	{
		var transform = Transform.Identity;
		transform.SetPosition(.(5, 0, 0));

		let parentWorld = Matrix4x4.CreateTranslation(.(10, 0, 0));
		transform.UpdateWorldMatrix(parentWorld);

		// World position should combine local and parent
		let worldPos = transform.WorldPosition;
		Test.Assert(Math.Abs(worldPos.X - 15) < 0.0001f);
	}

	[Test]
	public static void TestForwardDirection()
	{
		var transform = Transform.Identity;

		// Default forward is -Z
		let forward = transform.Forward;
		Test.Assert(Math.Abs(forward.X) < 0.0001f);
		Test.Assert(Math.Abs(forward.Y) < 0.0001f);
		Test.Assert(Math.Abs(forward.Z + 1) < 0.0001f);
	}

	[Test]
	public static void TestRightDirection()
	{
		var transform = Transform.Identity;

		// Default right is +X
		let right = transform.Right;
		Test.Assert(Math.Abs(right.X - 1) < 0.0001f);
		Test.Assert(Math.Abs(right.Y) < 0.0001f);
		Test.Assert(Math.Abs(right.Z) < 0.0001f);
	}

	[Test]
	public static void TestUpDirection()
	{
		var transform = Transform.Identity;

		// Default up is +Y
		let up = transform.Up;
		Test.Assert(Math.Abs(up.X) < 0.0001f);
		Test.Assert(Math.Abs(up.Y - 1) < 0.0001f);
		Test.Assert(Math.Abs(up.Z) < 0.0001f);
	}

	[Test]
	public static void TestSetRotation()
	{
		var transform = Transform.Identity;
		let rotation = Quaternion.CreateFromYawPitchRoll(Math.PI_f / 2, 0, 0);
		transform.SetRotation(rotation);

		Test.Assert(transform.Rotation.X == rotation.X);
		Test.Assert(transform.Rotation.Y == rotation.Y);
		Test.Assert(transform.Rotation.Z == rotation.Z);
		Test.Assert(transform.Rotation.W == rotation.W);
	}
}
