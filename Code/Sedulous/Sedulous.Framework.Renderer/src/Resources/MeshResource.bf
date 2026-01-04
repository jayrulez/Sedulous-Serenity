using System;
using Sedulous.Resources;
using Sedulous.Geometry;

namespace Sedulous.Framework.Renderer;

/// CPU-side mesh resource wrapping a Mesh.
class MeshResource : Resource
{
	private Mesh mMesh;
	private bool mOwnsMesh;

	/// The underlying mesh data.
	public Mesh Mesh => mMesh;

	public this(Mesh mesh, bool ownsMesh = false)
	{
		mMesh = mesh;
		mOwnsMesh = ownsMesh;
	}

	public ~this()
	{
		if (mOwnsMesh && mMesh != null)
			delete mMesh;
	}

	/// Creates a cube mesh resource.
	public static MeshResource CreateCube(float size = 1.0f)
	{
		let mesh = Mesh.CreateCube(size);
		return new MeshResource(mesh, true);
	}

	/// Creates a sphere mesh resource.
	public static MeshResource CreateSphere(float radius = 0.5f, int32 segments = 32, int32 rings = 16)
	{
		let mesh = Mesh.CreateSphere(radius, segments, rings);
		return new MeshResource(mesh, true);
	}

	/// Creates a plane mesh resource.
	public static MeshResource CreatePlane(float width = 1.0f, float height = 1.0f, int32 segmentsX = 1, int32 segmentsZ = 1)
	{
		let mesh = Mesh.CreatePlane(width, height, segmentsX, segmentsZ);
		return new MeshResource(mesh, true);
	}

	/// Creates a cylinder mesh resource.
	public static MeshResource CreateCylinder(float radius = 0.5f, float height = 1.0f, int32 segments = 32)
	{
		let mesh = Mesh.CreateCylinder(radius, height, segments);
		return new MeshResource(mesh, true);
	}
}
