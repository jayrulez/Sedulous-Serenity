using System;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Mathematics;
using Sedulous.Geometry;

namespace Sedulous.Geometry.Tooling;

/// Serialization helper for Mesh data.
static class MeshSerializer
{
	/// Serialize a Mesh to a serializer.
	public static SerializationResult Serialize(Serializer s, StringView name, Mesh mesh)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return result;

		if (s.IsWriting)
		{
			int32 vertexCount = mesh.Vertices?.VertexCount ?? 0;
			result = s.Int32("vertexCount", ref vertexCount);
			if (result != .Ok) { s.EndObject(); return result; }

			if (vertexCount > 0)
			{
				result = s.BeginObject("vertices");
				if (result != .Ok) { s.EndObject(); return result; }

				// Build lists for serialization
				let positions = new List<float>();
				let normals = new List<float>();
				let uvs = new List<float>();
				let colors = new List<int32>();
				let tangents = new List<float>();
				defer { delete positions; delete normals; delete uvs; delete colors; delete tangents; }

				for (int32 i = 0; i < vertexCount; i++)
				{
					let pos = mesh.GetPosition(i);
					positions.Add(pos.X); positions.Add(pos.Y); positions.Add(pos.Z);

					let n = mesh.GetNormal(i);
					normals.Add(n.X); normals.Add(n.Y); normals.Add(n.Z);

					let uv = mesh.GetUV(i);
					uvs.Add(uv.X); uvs.Add(uv.Y);

					colors.Add((int32)mesh.GetColor(i));

					let t = mesh.GetTangent(i);
					tangents.Add(t.X); tangents.Add(t.Y); tangents.Add(t.Z);
				}

				s.ArrayFloat("positions", positions);
				s.ArrayFloat("normals", normals);
				s.ArrayFloat("uvs", uvs);
				s.ArrayInt32("colors", colors);
				s.ArrayFloat("tangents", tangents);

				s.EndObject();
			}

			// Write indices
			int32 indexCount = mesh.Indices?.IndexCount ?? 0;
			result = s.Int32("indexCount", ref indexCount);
			if (result != .Ok) { s.EndObject(); return result; }

			if (indexCount > 0)
			{
				let indices = new List<int32>();
				defer delete indices;
				for (int32 i = 0; i < indexCount; i++)
					indices.Add((int32)mesh.Indices.GetIndex(i));
				s.ArrayInt32("indices", indices);
			}

			// Write submeshes
			int32 submeshCount = (int32)(mesh.SubMeshes?.Count ?? 0);
			result = s.Int32("submeshCount", ref submeshCount);
			if (result != .Ok) { s.EndObject(); return result; }

			if (submeshCount > 0)
			{
				result = s.BeginObject("submeshes");
				if (result != .Ok) { s.EndObject(); return result; }

				for (int32 i = 0; i < submeshCount; i++)
				{
					let sm = mesh.SubMeshes[i];
					s.BeginObject(scope $"sm{i}");

					int32 startIndex = sm.startIndex;
					int32 indexCnt = sm.indexCount;
					int32 materialIndex = sm.materialIndex;

					s.Int32("startIndex", ref startIndex);
					s.Int32("indexCount", ref indexCnt);
					s.Int32("materialIndex", ref materialIndex);

					s.EndObject();
				}

				s.EndObject();
			}
		}

		s.EndObject();
		return .Ok;
	}

	/// Deserialize a Mesh from a serializer.
	public static Result<Mesh> Deserialize(Serializer s, StringView name)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return .Err;

		let mesh = new Mesh();
		mesh.SetupCommonVertexFormat();

		int32 vertexCount = 0;
		result = s.Int32("vertexCount", ref vertexCount);
		if (result != .Ok) { delete mesh; s.EndObject(); return .Err; }

		if (vertexCount > 0)
		{
			mesh.Vertices.Resize(vertexCount);

			result = s.BeginObject("vertices");
			if (result != .Ok) { delete mesh; s.EndObject(); return .Err; }

			let positions = new List<float>();
			let normals = new List<float>();
			let uvs = new List<float>();
			let colors = new List<int32>();
			let tangents = new List<float>();
			defer { delete positions; delete normals; delete uvs; delete colors; delete tangents; }

			s.ArrayFloat("positions", positions);
			s.ArrayFloat("normals", normals);
			s.ArrayFloat("uvs", uvs);
			s.ArrayInt32("colors", colors);
			s.ArrayFloat("tangents", tangents);

			for (int32 i = 0; i < vertexCount; i++)
			{
				if (i * 3 + 2 < positions.Count)
					mesh.SetPosition(i, .(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]));
				if (i * 3 + 2 < normals.Count)
					mesh.SetNormal(i, .(normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2]));
				if (i * 2 + 1 < uvs.Count)
					mesh.SetUV(i, .(uvs[i * 2], uvs[i * 2 + 1]));
				if (i < colors.Count)
					mesh.SetColor(i, (uint32)colors[i]);
				if (i * 3 + 2 < tangents.Count)
					mesh.SetTangent(i, .(tangents[i * 3], tangents[i * 3 + 1], tangents[i * 3 + 2]));
			}

			s.EndObject();
		}

		// Read indices
		int32 indexCount = 0;
		result = s.Int32("indexCount", ref indexCount);
		if (result == .Ok && indexCount > 0)
		{
			mesh.Indices.Resize(indexCount);
			let indices = new List<int32>();
			defer delete indices;
			s.ArrayInt32("indices", indices);
			for (int32 i = 0; i < Math.Min(indexCount, (int32)indices.Count); i++)
				mesh.Indices.SetIndex(i, (uint32)indices[i]);
		}

		// Read submeshes
		int32 submeshCount = 0;
		result = s.Int32("submeshCount", ref submeshCount);
		if (result == .Ok && submeshCount > 0)
		{
			result = s.BeginObject("submeshes");
			if (result == .Ok)
			{
				for (int32 i = 0; i < submeshCount; i++)
				{
					result = s.BeginObject(scope $"sm{i}");
					if (result != .Ok) break;

					int32 startIndex = 0, idxCount = 0, materialIndex = 0;
					s.Int32("startIndex", ref startIndex);
					s.Int32("indexCount", ref idxCount);
					s.Int32("materialIndex", ref materialIndex);

					mesh.AddSubMesh(SubMesh(startIndex, idxCount, materialIndex));
					s.EndObject();
				}
				s.EndObject();
			}
		}

		s.EndObject();
		return .Ok(mesh);
	}
}
