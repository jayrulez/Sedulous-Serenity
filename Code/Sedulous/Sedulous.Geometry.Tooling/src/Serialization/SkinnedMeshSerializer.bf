using System;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Mathematics;
using Sedulous.Geometry;

namespace Sedulous.Geometry.Tooling;

/// Serialization helper for SkinnedMesh data.
static class SkinnedMeshSerializer
{
	/// Serialize a SkinnedMesh to a serializer.
	public static SerializationResult Serialize(Serializer s, StringView name, SkinnedMesh mesh)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return result;

		if (s.IsWriting)
		{
			int32 vertexCount = mesh.VertexCount;
			result = s.Int32("vertexCount", ref vertexCount);
			if (result != .Ok) { s.EndObject(); return result; }

			if (vertexCount > 0)
			{
				result = s.BeginObject("vertices");
				if (result != .Ok) { s.EndObject(); return result; }

				// Build lists
				let positions = new List<float>();
				let normals = new List<float>();
				let uvs = new List<float>();
				let colors = new List<int32>();
				let tangents = new List<float>();
				let joints = new List<int32>();
				let weights = new List<float>();
				defer { delete positions; delete normals; delete uvs; delete colors;
					delete tangents; delete joints; delete weights; }

				for (int32 i = 0; i < vertexCount; i++)
				{
					let v = mesh.GetVertex(i);
					positions.Add(v.Position.X); positions.Add(v.Position.Y); positions.Add(v.Position.Z);
					normals.Add(v.Normal.X); normals.Add(v.Normal.Y); normals.Add(v.Normal.Z);
					uvs.Add(v.TexCoord.X); uvs.Add(v.TexCoord.Y);
					colors.Add((int32)v.Color);
					tangents.Add(v.Tangent.X); tangents.Add(v.Tangent.Y); tangents.Add(v.Tangent.Z);
					joints.Add((int32)v.Joints[0]); joints.Add((int32)v.Joints[1]);
					joints.Add((int32)v.Joints[2]); joints.Add((int32)v.Joints[3]);
					weights.Add(v.Weights.X); weights.Add(v.Weights.Y);
					weights.Add(v.Weights.Z); weights.Add(v.Weights.W);
				}

				s.ArrayFloat("positions", positions);
				s.ArrayFloat("normals", normals);
				s.ArrayFloat("uvs", uvs);
				s.ArrayInt32("colors", colors);
				s.ArrayFloat("tangents", tangents);
				s.ArrayInt32("joints", joints);
				s.ArrayFloat("weights", weights);

				s.EndObject();
			}

			// Write indices
			int32 indexCount = mesh.IndexCount;
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
			int32 submeshCount = (int32)mesh.SubMeshes.Count;
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

	/// Deserialize a SkinnedMesh from a serializer.
	public static Result<SkinnedMesh> Deserialize(Serializer s, StringView name)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return .Err;

		let mesh = new SkinnedMesh();

		int32 vertexCount = 0;
		result = s.Int32("vertexCount", ref vertexCount);
		if (result != .Ok) { delete mesh; s.EndObject(); return .Err; }

		if (vertexCount > 0)
		{
			mesh.ResizeVertices(vertexCount);

			result = s.BeginObject("vertices");
			if (result != .Ok) { delete mesh; s.EndObject(); return .Err; }

			let positions = new List<float>();
			let normals = new List<float>();
			let uvs = new List<float>();
			let colors = new List<int32>();
			let tangents = new List<float>();
			let joints = new List<int32>();
			let weights = new List<float>();
			defer { delete positions; delete normals; delete uvs; delete colors;
				delete tangents; delete joints; delete weights; }

			s.ArrayFloat("positions", positions);
			s.ArrayFloat("normals", normals);
			s.ArrayFloat("uvs", uvs);
			s.ArrayInt32("colors", colors);
			s.ArrayFloat("tangents", tangents);
			s.ArrayInt32("joints", joints);
			s.ArrayFloat("weights", weights);

			for (int32 i = 0; i < vertexCount; i++)
			{
				SkinnedVertex v = .();
				if (i * 3 + 2 < positions.Count)
					v.Position = .(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]);
				if (i * 3 + 2 < normals.Count)
					v.Normal = .(normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2]);
				if (i * 2 + 1 < uvs.Count)
					v.TexCoord = .(uvs[i * 2], uvs[i * 2 + 1]);
				if (i < colors.Count)
					v.Color = (uint32)colors[i];
				if (i * 3 + 2 < tangents.Count)
					v.Tangent = .(tangents[i * 3], tangents[i * 3 + 1], tangents[i * 3 + 2]);
				if (i * 4 + 3 < joints.Count)
					v.Joints = .((uint16)joints[i * 4], (uint16)joints[i * 4 + 1],
						(uint16)joints[i * 4 + 2], (uint16)joints[i * 4 + 3]);
				if (i * 4 + 3 < weights.Count)
					v.Weights = .(weights[i * 4], weights[i * 4 + 1],
						weights[i * 4 + 2], weights[i * 4 + 3]);
				mesh.SetVertex(i, v);
			}

			s.EndObject();
		}

		// Read indices
		int32 indexCount = 0;
		result = s.Int32("indexCount", ref indexCount);
		if (result == .Ok && indexCount > 0)
		{
			mesh.ReserveIndices(indexCount);
			let indices = new List<int32>();
			defer delete indices;
			s.ArrayInt32("indices", indices);
			for (int32 i = 0; i < Math.Min(indexCount, (int32)indices.Count); i++)
				mesh.AddIndex((uint32)indices[i]);
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

		mesh.CalculateBounds();
		s.EndObject();
		return .Ok(mesh);
	}
}
