namespace Sedulous.RendererNG;

using System;
using Sedulous.Mathematics;

/// Factory methods for creating primitive meshes.
static class MeshPrimitives
{
	/// Creates a unit cube centered at origin.
	public static StaticMesh CreateCube(StringView name = "Cube")
	{
		let mesh = new StaticMesh(name, .PositionNormalUV, 24, 36, false);

		var vertices = mesh.GetVertices<VertexLayouts.VertexPNU>();
		var indices = mesh.GetIndices16();

		// Front face (Z+)
		vertices[0] = .() { Position = .(-0.5f, -0.5f,  0.5f), Normal = .(0, 0, 1), TexCoord = .(0, 1) };
		vertices[1] = .() { Position = .( 0.5f, -0.5f,  0.5f), Normal = .(0, 0, 1), TexCoord = .(1, 1) };
		vertices[2] = .() { Position = .( 0.5f,  0.5f,  0.5f), Normal = .(0, 0, 1), TexCoord = .(1, 0) };
		vertices[3] = .() { Position = .(-0.5f,  0.5f,  0.5f), Normal = .(0, 0, 1), TexCoord = .(0, 0) };

		// Back face (Z-)
		vertices[4] = .() { Position = .( 0.5f, -0.5f, -0.5f), Normal = .(0, 0, -1), TexCoord = .(0, 1) };
		vertices[5] = .() { Position = .(-0.5f, -0.5f, -0.5f), Normal = .(0, 0, -1), TexCoord = .(1, 1) };
		vertices[6] = .() { Position = .(-0.5f,  0.5f, -0.5f), Normal = .(0, 0, -1), TexCoord = .(1, 0) };
		vertices[7] = .() { Position = .( 0.5f,  0.5f, -0.5f), Normal = .(0, 0, -1), TexCoord = .(0, 0) };

		// Right face (X+)
		vertices[8]  = .() { Position = .(0.5f, -0.5f,  0.5f), Normal = .(1, 0, 0), TexCoord = .(0, 1) };
		vertices[9]  = .() { Position = .(0.5f, -0.5f, -0.5f), Normal = .(1, 0, 0), TexCoord = .(1, 1) };
		vertices[10] = .() { Position = .(0.5f,  0.5f, -0.5f), Normal = .(1, 0, 0), TexCoord = .(1, 0) };
		vertices[11] = .() { Position = .(0.5f,  0.5f,  0.5f), Normal = .(1, 0, 0), TexCoord = .(0, 0) };

		// Left face (X-)
		vertices[12] = .() { Position = .(-0.5f, -0.5f, -0.5f), Normal = .(-1, 0, 0), TexCoord = .(0, 1) };
		vertices[13] = .() { Position = .(-0.5f, -0.5f,  0.5f), Normal = .(-1, 0, 0), TexCoord = .(1, 1) };
		vertices[14] = .() { Position = .(-0.5f,  0.5f,  0.5f), Normal = .(-1, 0, 0), TexCoord = .(1, 0) };
		vertices[15] = .() { Position = .(-0.5f,  0.5f, -0.5f), Normal = .(-1, 0, 0), TexCoord = .(0, 0) };

		// Top face (Y+)
		vertices[16] = .() { Position = .(-0.5f, 0.5f,  0.5f), Normal = .(0, 1, 0), TexCoord = .(0, 1) };
		vertices[17] = .() { Position = .( 0.5f, 0.5f,  0.5f), Normal = .(0, 1, 0), TexCoord = .(1, 1) };
		vertices[18] = .() { Position = .( 0.5f, 0.5f, -0.5f), Normal = .(0, 1, 0), TexCoord = .(1, 0) };
		vertices[19] = .() { Position = .(-0.5f, 0.5f, -0.5f), Normal = .(0, 1, 0), TexCoord = .(0, 0) };

		// Bottom face (Y-)
		vertices[20] = .() { Position = .(-0.5f, -0.5f, -0.5f), Normal = .(0, -1, 0), TexCoord = .(0, 1) };
		vertices[21] = .() { Position = .( 0.5f, -0.5f, -0.5f), Normal = .(0, -1, 0), TexCoord = .(1, 1) };
		vertices[22] = .() { Position = .( 0.5f, -0.5f,  0.5f), Normal = .(0, -1, 0), TexCoord = .(1, 0) };
		vertices[23] = .() { Position = .(-0.5f, -0.5f,  0.5f), Normal = .(0, -1, 0), TexCoord = .(0, 0) };

		// Indices (two triangles per face)
		for (int face = 0; face < 6; face++)
		{
			let baseVertex = (uint16)(face * 4);
			let baseIndex = face * 6;
			indices[baseIndex + 0] = baseVertex + 0;
			indices[baseIndex + 1] = baseVertex + 1;
			indices[baseIndex + 2] = baseVertex + 2;
			indices[baseIndex + 3] = baseVertex + 0;
			indices[baseIndex + 4] = baseVertex + 2;
			indices[baseIndex + 5] = baseVertex + 3;
		}

		mesh.ComputeBounds();
		mesh.AddSubmesh(0, 36, 0);
		return mesh;
	}

	/// Creates a plane in the XZ plane.
	public static StaticMesh CreatePlane(float width = 1, float depth = 1, StringView name = "Plane")
	{
		let mesh = new StaticMesh(name, .PositionNormalUV, 4, 6, false);

		var vertices = mesh.GetVertices<VertexLayouts.VertexPNU>();
		var indices = mesh.GetIndices16();

		let hw = width * 0.5f;
		let hd = depth * 0.5f;

		vertices[0] = .() { Position = .(-hw, 0, -hd), Normal = .(0, 1, 0), TexCoord = .(0, 0) };
		vertices[1] = .() { Position = .( hw, 0, -hd), Normal = .(0, 1, 0), TexCoord = .(1, 0) };
		vertices[2] = .() { Position = .( hw, 0,  hd), Normal = .(0, 1, 0), TexCoord = .(1, 1) };
		vertices[3] = .() { Position = .(-hw, 0,  hd), Normal = .(0, 1, 0), TexCoord = .(0, 1) };

		indices[0] = 0; indices[1] = 2; indices[2] = 1;
		indices[3] = 0; indices[4] = 3; indices[5] = 2;

		mesh.ComputeBounds();
		mesh.AddSubmesh(0, 6, 0);
		return mesh;
	}

	/// Creates a UV sphere.
	public static StaticMesh CreateSphere(int segments = 16, int rings = 16, float radius = 0.5f, StringView name = "Sphere")
	{
		let vertexCount = (uint32)((segments + 1) * (rings + 1));
		let indexCount = (uint32)(segments * rings * 6);
		let mesh = new StaticMesh(name, .PositionNormalUV, vertexCount, indexCount, false);

		var vertices = mesh.GetVertices<VertexLayouts.VertexPNU>();
		var indices = mesh.GetIndices16();

		int vertexIndex = 0;
		for (int ring = 0; ring <= rings; ring++)
		{
			let v = (float)ring / rings;
			let phi = v * Math.PI_f;

			for (int seg = 0; seg <= segments; seg++)
			{
				let u = (float)seg / segments;
				let theta = u * Math.PI_f * 2;

				let x = Math.Sin(phi) * Math.Cos(theta);
				let y = Math.Cos(phi);
				let z = Math.Sin(phi) * Math.Sin(theta);

				vertices[vertexIndex] = .() {
					Position = .(x * radius, y * radius, z * radius),
					Normal = .(x, y, z),
					TexCoord = .(u, v)
				};
				vertexIndex++;
			}
		}

		int indexIndex = 0;
		for (int ring = 0; ring < rings; ring++)
		{
			for (int seg = 0; seg < segments; seg++)
			{
				let current = (uint16)(ring * (segments + 1) + seg);
				let next = (uint16)(current + segments + 1);

				indices[indexIndex++] = current;
				indices[indexIndex++] = (uint16)(current + 1);
				indices[indexIndex++] = next;

				indices[indexIndex++] = (uint16)(current + 1);
				indices[indexIndex++] = (uint16)(next + 1);
				indices[indexIndex++] = next;
			}
		}

		mesh.ComputeBounds();
		mesh.AddSubmesh(0, indexCount, 0);
		return mesh;
	}

	/// Creates a cylinder along the Y axis.
	public static StaticMesh CreateCylinder(int segments = 16, float radius = 0.5f, float height = 1.0f, StringView name = "Cylinder")
	{
		// Side vertices + top cap + bottom cap
		let sideVerts = (segments + 1) * 2;
		let capVerts = (segments + 1) * 2; // Top and bottom center + ring
		let vertexCount = (uint32)(sideVerts + capVerts + 2); // +2 for cap centers

		let sideIndices = segments * 6;
		let capIndices = segments * 3 * 2; // Top and bottom caps
		let indexCount = (uint32)(sideIndices + capIndices);

		let mesh = new StaticMesh(name, .PositionNormalUV, vertexCount, indexCount, false);

		var vertices = mesh.GetVertices<VertexLayouts.VertexPNU>();
		var indices = mesh.GetIndices16();

		let halfHeight = height * 0.5f;
		int vi = 0;
		int ii = 0;

		// Side vertices
		for (int i = 0; i <= segments; i++)
		{
			let u = (float)i / segments;
			let theta = u * Math.PI_f * 2;
			let x = Math.Cos(theta);
			let z = Math.Sin(theta);

			// Bottom ring
			vertices[vi++] = .() {
				Position = .(x * radius, -halfHeight, z * radius),
				Normal = .(x, 0, z),
				TexCoord = .(u, 1)
			};

			// Top ring
			vertices[vi++] = .() {
				Position = .(x * radius, halfHeight, z * radius),
				Normal = .(x, 0, z),
				TexCoord = .(u, 0)
			};
		}

		// Side indices
		for (int i = 0; i < segments; i++)
		{
			let bl = (uint16)(i * 2);
			let tl = (uint16)(i * 2 + 1);
			let br = (uint16)((i + 1) * 2);
			let tr = (uint16)((i + 1) * 2 + 1);

			indices[ii++] = bl; indices[ii++] = br; indices[ii++] = tl;
			indices[ii++] = tl; indices[ii++] = br; indices[ii++] = tr;
		}

		// Top cap center
		let topCenter = (uint16)vi;
		vertices[vi++] = .() {
			Position = .(0, halfHeight, 0),
			Normal = .(0, 1, 0),
			TexCoord = .(0.5f, 0.5f)
		};

		// Top cap ring
		let topRingStart = (uint16)vi;
		for (int i = 0; i <= segments; i++)
		{
			let u = (float)i / segments;
			let theta = u * Math.PI_f * 2;
			let x = Math.Cos(theta);
			let z = Math.Sin(theta);

			vertices[vi++] = .() {
				Position = .(x * radius, halfHeight, z * radius),
				Normal = .(0, 1, 0),
				TexCoord = .((x + 1) * 0.5f, (z + 1) * 0.5f)
			};
		}

		// Top cap indices
		for (int i = 0; i < segments; i++)
		{
			indices[ii++] = topCenter;
			indices[ii++] = (uint16)(topRingStart + i + 1);
			indices[ii++] = (uint16)(topRingStart + i);
		}

		// Bottom cap center
		let bottomCenter = (uint16)vi;
		vertices[vi++] = .() {
			Position = .(0, -halfHeight, 0),
			Normal = .(0, -1, 0),
			TexCoord = .(0.5f, 0.5f)
		};

		// Bottom cap ring
		let bottomRingStart = (uint16)vi;
		for (int i = 0; i <= segments; i++)
		{
			let u = (float)i / segments;
			let theta = u * Math.PI_f * 2;
			let x = Math.Cos(theta);
			let z = Math.Sin(theta);

			vertices[vi++] = .() {
				Position = .(x * radius, -halfHeight, z * radius),
				Normal = .(0, -1, 0),
				TexCoord = .((x + 1) * 0.5f, (z + 1) * 0.5f)
			};
		}

		// Bottom cap indices
		for (int i = 0; i < segments; i++)
		{
			indices[ii++] = bottomCenter;
			indices[ii++] = (uint16)(bottomRingStart + i);
			indices[ii++] = (uint16)(bottomRingStart + i + 1);
		}

		mesh.ComputeBounds();
		mesh.AddSubmesh(0, indexCount, 0);
		return mesh;
	}
}
