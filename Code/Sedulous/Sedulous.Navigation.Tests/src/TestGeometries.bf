using System;
using Sedulous.Navigation.Recast;

namespace Sedulous.Navigation.Tests;

/// Provides test geometry meshes for navigation tests.
static class TestGeometries
{
	/// Creates a flat 10x10 plane centered at origin.
	public static InputGeometry CreateFlatPlane()
	{
		float[12] vertices = .(
			-5, 0, -5,
			 5, 0, -5,
			 5, 0,  5,
			-5, 0,  5
		);

		int32[6] triangles = .(
			0, 1, 2,
			0, 2, 3
		);

		return new InputGeometry(Span<float>(&vertices, 12), Span<int32>(&triangles, 6));
	}

	/// Creates a 20x20 plane with a 4x4 box obstacle in the center.
	/// The box is 2 units tall.
	public static InputGeometry CreatePlaneWithBox()
	{
		// Floor vertices (4) + box vertices (8) = 12 vertices
		float[] vertices = new float[](
			// Floor
			-10, 0, -10,  // 0
			 10, 0, -10,  // 1
			 10, 0,  10,  // 2
			-10, 0,  10,  // 3
			// Box top
			-2, 2, -2,    // 4
			 2, 2, -2,    // 5
			 2, 2,  2,    // 6
			-2, 2,  2,    // 7
			// Box bottom (same as box area on floor)
			-2, 0, -2,    // 8
			 2, 0, -2,    // 9
			 2, 0,  2,    // 10
			-2, 0,  2     // 11
		);
		defer delete vertices;

		int32[] triangles = new int32[](
			// Floor (2 tris)
			0, 1, 2,
			0, 2, 3,
			// Box top (2 tris)
			4, 6, 5,
			4, 7, 6,
			// Box front face (z = -2)
			8, 5, 9,
			8, 4, 5,
			// Box back face (z = 2)
			10, 7, 11,
			10, 6, 7,
			// Box left face (x = -2)
			11, 4, 8,
			11, 7, 4,
			// Box right face (x = 2)
			9, 6, 10,
			9, 5, 6
		);
		defer delete triangles;

		return new InputGeometry(Span<float>(vertices.Ptr, vertices.Count), Span<int32>(triangles.Ptr, triangles.Count));
	}

	/// Creates an L-shaped corridor for testing pathfinding around corners.
	public static InputGeometry CreateLShapedCorridor()
	{
		// L-shaped floor: horizontal arm + vertical arm
		float[] vertices = new float[](
			// Horizontal arm (x: -10 to 2, z: -2 to 2)
			-10, 0, -2,   // 0
			  2, 0, -2,   // 1
			  2, 0,  2,   // 2
			-10, 0,  2,   // 3
			// Vertical arm (x: -2 to 2, z: 2 to 10)
			-2, 0,  2,    // 4
			 2, 0,  2,    // 5
			 2, 0,  10,   // 6
			-2, 0,  10    // 7
		);
		defer delete vertices;

		int32[] triangles = new int32[](
			// Horizontal arm
			0, 1, 2,
			0, 2, 3,
			// Vertical arm
			4, 5, 6,
			4, 6, 7
		);
		defer delete triangles;

		return new InputGeometry(Span<float>(vertices.Ptr, vertices.Count), Span<int32>(triangles.Ptr, triangles.Count));
	}

	/// Creates a staircase geometry for testing walkable climb.
	public static InputGeometry CreateStairs()
	{
		// 5 steps, each 0.3m high, 1m deep, 4m wide
		let stepCount = 5;
		let stepHeight = 0.3f;
		let stepDepth = 1.0f;
		let stepWidth = 4.0f;

		let vertCount = (stepCount + 1) * 4;
		let triCount = stepCount * 4; // top + front face per step
		float[] vertices = new float[vertCount * 3];
		int32[] triangles = new int32[triCount * 3];
		defer delete vertices;
		defer delete triangles;

		int32 vi = 0;
		int32 ti = 0;

		for (int32 i = 0; i <= stepCount; i++)
		{
			float y = (float)i * stepHeight;
			float z = (float)i * stepDepth;

			// Left-front, right-front, right-back, left-back
			vertices[vi * 3] = -stepWidth / 2; vertices[vi * 3 + 1] = y; vertices[vi * 3 + 2] = z; vi++;
			vertices[vi * 3] =  stepWidth / 2; vertices[vi * 3 + 1] = y; vertices[vi * 3 + 2] = z; vi++;
			vertices[vi * 3] =  stepWidth / 2; vertices[vi * 3 + 1] = y; vertices[vi * 3 + 2] = z + stepDepth; vi++;
			vertices[vi * 3] = -stepWidth / 2; vertices[vi * 3 + 1] = y; vertices[vi * 3 + 2] = z + stepDepth; vi++;
		}

		for (int32 i = 0; i < stepCount; i++)
		{
			int32 baseV = i * 4;
			// Top face
			triangles[ti * 3] = baseV; triangles[ti * 3 + 1] = baseV + 1; triangles[ti * 3 + 2] = baseV + 2; ti++;
			triangles[ti * 3] = baseV; triangles[ti * 3 + 1] = baseV + 2; triangles[ti * 3 + 2] = baseV + 3; ti++;
			// Front face (riser) - will be marked as non-walkable due to slope
			int32 nextBase = (i + 1) * 4;
			triangles[ti * 3] = baseV + 1; triangles[ti * 3 + 1] = nextBase + 1; triangles[ti * 3 + 2] = nextBase; ti++;
			triangles[ti * 3] = baseV + 1; triangles[ti * 3 + 1] = nextBase; triangles[ti * 3 + 2] = baseV; ti++;
		}

		return new InputGeometry(Span<float>(vertices.Ptr, vi * 3), Span<int32>(triangles.Ptr, ti * 3));
	}

	/// Creates a large flat plane for tiling tests.
	public static InputGeometry CreateLargePlane(float width, float depth)
	{
		float halfW = width * 0.5f;
		float halfD = depth * 0.5f;

		float[12] vertices = .(
			-halfW, 0, -halfD,
			 halfW, 0, -halfD,
			 halfW, 0,  halfD,
			-halfW, 0,  halfD
		);

		int32[6] triangles = .(
			0, 1, 2,
			0, 2, 3
		);

		return new InputGeometry(Span<float>(&vertices, 12), Span<int32>(&triangles, 6));
	}
}
