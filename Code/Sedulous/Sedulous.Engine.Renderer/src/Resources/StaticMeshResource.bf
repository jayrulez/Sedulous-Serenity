using System;
using System.IO;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Geometry;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Mathematics;

namespace Sedulous.Engine.Renderer;

/// CPU-side mesh resource wrapping a Mesh.
class StaticMeshResource : Resource
{
	public const int32 FileVersion = 1;
	public const int32 FileType = 1; // ResourceFileType.Mesh

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

	// ---- Serialization ----

	public override int32 SerializationVersion => FileVersion;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		if (s.IsWriting)
		{
			if (mMesh == null)
				return .InvalidData;

			int32 vertexCount = mMesh.Vertices?.VertexCount ?? 0;
			s.Int32("vertexCount", ref vertexCount);

			if (vertexCount > 0)
			{
				s.BeginObject("vertices");

				let positions = scope List<float>();
				let normals = scope List<float>();
				let uvs = scope List<float>();
				let colors = scope List<int32>();
				let tangents = scope List<float>();

				for (int32 i = 0; i < vertexCount; i++)
				{
					let pos = mMesh.GetPosition(i);
					positions.Add(pos.X); positions.Add(pos.Y); positions.Add(pos.Z);

					let n = mMesh.GetNormal(i);
					normals.Add(n.X); normals.Add(n.Y); normals.Add(n.Z);

					let uv = mMesh.GetUV(i);
					uvs.Add(uv.X); uvs.Add(uv.Y);

					colors.Add((int32)mMesh.GetColor(i));

					let t = mMesh.GetTangent(i);
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
			int32 indexCount = mMesh.Indices?.IndexCount ?? 0;
			s.Int32("indexCount", ref indexCount);

			if (indexCount > 0)
			{
				let indices = scope List<int32>();
				for (int32 i = 0; i < indexCount; i++)
					indices.Add((int32)mMesh.Indices.GetIndex(i));
				s.ArrayInt32("indices", indices);
			}

			// Write submeshes
			int32 submeshCount = (int32)(mMesh.SubMeshes?.Count ?? 0);
			s.Int32("submeshCount", ref submeshCount);

			if (submeshCount > 0)
			{
				s.BeginObject("submeshes");

				for (int32 i = 0; i < submeshCount; i++)
				{
					let sm = mMesh.SubMeshes[i];
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
		else
		{
			// Reading
			let mesh = new StaticMesh();
			mesh.SetupCommonVertexFormat();

			int32 vertexCount = 0;
			s.Int32("vertexCount", ref vertexCount);

			if (vertexCount > 0)
			{
				mesh.Vertices.Resize(vertexCount);

				s.BeginObject("vertices");

				let positions = scope List<float>();
				let normals = scope List<float>();
				let uvs = scope List<float>();
				let colors = scope List<int32>();
				let tangents = scope List<float>();

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
			s.Int32("indexCount", ref indexCount);

			if (indexCount > 0)
			{
				mesh.Indices.Resize(indexCount);
				let indices = scope List<int32>();
				s.ArrayInt32("indices", indices);
				for (int32 i = 0; i < Math.Min(indexCount, (int32)indices.Count); i++)
					mesh.Indices.SetIndex(i, (uint32)indices[i]);
			}

			// Read submeshes
			int32 submeshCount = 0;
			s.Int32("submeshCount", ref submeshCount);

			if (submeshCount > 0)
			{
				s.BeginObject("submeshes");

				for (int32 i = 0; i < submeshCount; i++)
				{
					s.BeginObject(scope $"sm{i}");

					int32 startIndex = 0, idxCount = 0, materialIndex = 0;
					s.Int32("startIndex", ref startIndex);
					s.Int32("indexCount", ref idxCount);
					s.Int32("materialIndex", ref materialIndex);

					mesh.AddSubMesh(SubMesh(startIndex, idxCount, materialIndex));
					s.EndObject();
				}

				s.EndObject();
			}

			SetMesh(mesh, true);
		}

		return .Ok;
	}

	/// Save this mesh resource to a file.
	public Result<void> SaveToFile(StringView path)
	{
		if (mMesh == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = FileVersion;
		writer.Int32("version", ref version);

		int32 fileType = FileType;
		writer.Int32("type", ref fileType);

		Serialize(writer);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load a mesh resource from a file.
	public static Result<StaticMeshResource> LoadFromFile(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > FileVersion)
			return .Err;

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != FileType)
			return .Err;

		let resource = new StaticMeshResource();
		resource.Serialize(reader);

		return .Ok(resource);
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
