using System;
using Sedulous.Geometry;
using Sedulous.Mathematics;

namespace Sedulous.Geometry.Tests;

class MeshTests
{
	[Test]
	public static void TestMeshCreation()
	{
		let mesh = new Mesh();
		defer delete mesh;

		mesh.SetupCommonVertexFormat();
		mesh.Vertices.Resize(3);
		mesh.Indices.Resize(3);

		Test.Assert(mesh.Vertices.VertexCount == 3);
		Test.Assert(mesh.Indices.IndexCount == 3);
	}

	[Test]
	public static void TestMeshVertexData()
	{
		let mesh = new Mesh();
		defer delete mesh;

		mesh.SetupCommonVertexFormat();
		mesh.Vertices.Resize(3);

		mesh.SetPosition(0, .(1, 2, 3));
		mesh.SetNormal(0, .(0, 1, 0));
		mesh.SetUV(0, .(0.5f, 0.5f));
		mesh.SetColor(0, 0xFF00FF00);

		let pos = mesh.GetPosition(0);
		Test.Assert(pos.X == 1 && pos.Y == 2 && pos.Z == 3);

		let normal = mesh.GetNormal(0);
		Test.Assert(normal.Y == 1);

		let uv = mesh.GetUV(0);
		Test.Assert(uv.X == 0.5f && uv.Y == 0.5f);

		let color = mesh.GetColor(0);
		Test.Assert(color == 0xFF00FF00);
	}

	[Test]
	public static void TestCreateTriangle()
	{
		let mesh = Mesh.CreateTriangle();
		defer delete mesh;

		Test.Assert(mesh.Vertices.VertexCount == 3);
		Test.Assert(mesh.Indices.IndexCount == 3);
		Test.Assert(mesh.SubMeshes.Count == 1);
	}

	[Test]
	public static void TestCreateQuad()
	{
		let mesh = Mesh.CreateQuad(2.0f, 2.0f);
		defer delete mesh;

		Test.Assert(mesh.Vertices.VertexCount == 4);
		Test.Assert(mesh.Indices.IndexCount == 6);
	}

	[Test]
	public static void TestCreateCube()
	{
		let mesh = Mesh.CreateCube(1.0f);
		defer delete mesh;

		Test.Assert(mesh.Vertices.VertexCount == 24);
		Test.Assert(mesh.Indices.IndexCount == 36);
	}

	[Test]
	public static void TestCreateSphere()
	{
		let mesh = Mesh.CreateSphere(0.5f, 16, 8);
		defer delete mesh;

		Test.Assert(mesh.Vertices.VertexCount > 0);
		Test.Assert(mesh.Indices.IndexCount > 0);
	}

	[Test]
	public static void TestCreatePlane()
	{
		let mesh = Mesh.CreatePlane(10.0f, 10.0f, 2, 2);
		defer delete mesh;

		Test.Assert(mesh.Vertices.VertexCount == 9); // (2+1) * (2+1)
		Test.Assert(mesh.Indices.IndexCount == 24); // 2 * 2 * 6
	}

	[Test]
	public static void TestMeshBounds()
	{
		let mesh = Mesh.CreateCube(2.0f);
		defer delete mesh;

		let bounds = mesh.GetBounds();

		// Cube size 2, so bounds should be -1 to 1
		Test.Assert(Math.Abs(bounds.Min.X - (-1.0f)) < 0.001f);
		Test.Assert(Math.Abs(bounds.Max.X - 1.0f) < 0.001f);
	}
}
