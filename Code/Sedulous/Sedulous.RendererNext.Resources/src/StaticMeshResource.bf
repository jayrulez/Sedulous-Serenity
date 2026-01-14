namespace Sedulous.RendererNext.Resources;

using System;
using Sedulous.Resources;
using Sedulous.Geometry;
using Sedulous.Mathematics;

/// CPU-side static mesh resource wrapping a StaticMesh.
class StaticMeshResource : Resource
{
	private StaticMesh mMesh;
	private bool mOwnsMesh;

	/// The underlying mesh data.
	public StaticMesh Mesh => mMesh;

	public this()
	{
		mMesh = null;
		mOwnsMesh = false;
	}

	public this(StaticMesh mesh, bool ownsMesh = false)
	{
		mMesh = mesh;
		mOwnsMesh = ownsMesh;
	}

	public ~this()
	{
		if (mOwnsMesh && mMesh != null)
			delete mMesh;
	}

	/// Sets the mesh. Takes ownership if ownsMesh is true.
	public void SetMesh(StaticMesh mesh, bool ownsMesh = false)
	{
		if (mOwnsMesh && mMesh != null)
			delete mMesh;
		mMesh = mesh;
		mOwnsMesh = ownsMesh;
	}

	/// Creates a cube mesh resource.
	public static StaticMeshResource CreateCube(float size = 1.0f)
	{
		let mesh = StaticMesh.CreateCube(size);
		return new StaticMeshResource(mesh, true);
	}

	/// Creates a sphere mesh resource.
	public static StaticMeshResource CreateSphere(float radius = 0.5f, int32 segments = 32, int32 rings = 16)
	{
		let mesh = StaticMesh.CreateSphere(radius, segments, rings);
		return new StaticMeshResource(mesh, true);
	}

	/// Creates a plane mesh resource.
	public static StaticMeshResource CreatePlane(float width = 1.0f, float height = 1.0f, int32 segmentsX = 1, int32 segmentsZ = 1)
	{
		let mesh = StaticMesh.CreatePlane(width, height, segmentsX, segmentsZ);
		return new StaticMeshResource(mesh, true);
	}

	/// Creates a cylinder mesh resource.
	public static StaticMeshResource CreateCylinder(float radius = 0.5f, float height = 1.0f, int32 segments = 32)
	{
		let mesh = StaticMesh.CreateCylinder(radius, height, segments);
		return new StaticMeshResource(mesh, true);
	}
}
