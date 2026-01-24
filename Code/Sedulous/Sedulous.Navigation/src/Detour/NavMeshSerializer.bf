using System;
using System.IO;
using System.Collections;

namespace Sedulous.Navigation.Detour;

/// Serializes and deserializes NavMesh data to/from binary format.
static class NavMeshSerializer
{
	private const uint32 Magic = 0x4E41564D; // "NAVM"
	private const int32 Version = 1;

	/// Saves a NavMesh to a byte array.
	public static Result<uint8[]> Save(NavMesh navMesh)
	{
		if (navMesh == null)
			return .Err;

		let stream = scope MemoryStream();

		// Header
		WriteUInt32(stream, Magic);
		WriteInt32(stream, Version);

		// Params
		let p = navMesh.Params;
		WriteFloat(stream, p.Origin[0]);
		WriteFloat(stream, p.Origin[1]);
		WriteFloat(stream, p.Origin[2]);
		WriteFloat(stream, p.TileWidth);
		WriteFloat(stream, p.TileHeight);
		WriteInt32(stream, p.MaxTiles);
		WriteInt32(stream, p.MaxPolys);

		// Tile count
		WriteInt32(stream, navMesh.TileCount);

		// Tiles
		for (int32 ti = 0; ti < navMesh.MaxTiles; ti++)
		{
			let tile = navMesh.GetTile(ti);
			if (tile == null) continue;

			WriteInt32(stream, tile.Salt);
			WriteInt32(stream, tile.X);
			WriteInt32(stream, tile.Z);
			WriteInt32(stream, tile.Layer);

			// Bounds
			WriteFloat(stream, tile.BMin[0]);
			WriteFloat(stream, tile.BMin[1]);
			WriteFloat(stream, tile.BMin[2]);
			WriteFloat(stream, tile.BMax[0]);
			WriteFloat(stream, tile.BMax[1]);
			WriteFloat(stream, tile.BMax[2]);

			// Vertices
			WriteInt32(stream, tile.VertexCount);
			for (int32 i = 0; i < tile.VertexCount * 3; i++)
				WriteFloat(stream, tile.Vertices[i]);

			// Polygons
			WriteInt32(stream, tile.PolyCount);
			for (int32 i = 0; i < tile.PolyCount; i++)
			{
				ref NavPoly poly = ref tile.Polygons[i];
				for (int32 j = 0; j < NavMeshConstants.MaxVertsPerPoly; j++)
					WriteUInt16(stream, poly.VertexIndices[j]);
				for (int32 j = 0; j < NavMeshConstants.MaxVertsPerPoly; j++)
					WriteUInt16(stream, poly.Neighbors[j]);
				stream.Write(Span<uint8>((uint8*)&poly.VertexCount, 1));
				stream.Write(Span<uint8>((uint8*)&poly.Area, 1));
				WriteUInt16(stream, poly.Flags);
				stream.Write(Span<uint8>((uint8*)&poly.Type, 1));
			}
		}

		let data = new uint8[stream.Length];
		stream.Position = 0;
		stream.TryRead(Span<uint8>(data.Ptr, data.Count));
		return .Ok(data);
	}

	/// Loads a NavMesh from a byte array.
	public static Result<NavMesh> Load(uint8[] data)
	{
		if (data == null || data.Count < 8)
			return .Err;

		let stream = scope MemoryStream();
		stream.Write(Span<uint8>(data.Ptr, data.Count));
		stream.Position = 0;

		// Header
		uint32 magic = ReadUInt32(stream);
		if (magic != Magic) return .Err;

		int32 version = ReadInt32(stream);
		if (version != Version) return .Err;

		// Params
		NavMeshParams @params = .();
		@params.Origin[0] = ReadFloat(stream);
		@params.Origin[1] = ReadFloat(stream);
		@params.Origin[2] = ReadFloat(stream);
		@params.TileWidth = ReadFloat(stream);
		@params.TileHeight = ReadFloat(stream);
		@params.MaxTiles = ReadInt32(stream);
		@params.MaxPolys = ReadInt32(stream);

		let navMesh = new NavMesh();
		if (navMesh.Init(@params) != .Success)
		{
			delete navMesh;
			return .Err;
		}

		int32 tileCount = ReadInt32(stream);

		for (int32 t = 0; t < tileCount; t++)
		{
			let tile = new NavMeshTile();
			tile.Salt = ReadInt32(stream);
			tile.X = ReadInt32(stream);
			tile.Z = ReadInt32(stream);
			tile.Layer = ReadInt32(stream);

			// Bounds
			tile.BMin[0] = ReadFloat(stream);
			tile.BMin[1] = ReadFloat(stream);
			tile.BMin[2] = ReadFloat(stream);
			tile.BMax[0] = ReadFloat(stream);
			tile.BMax[1] = ReadFloat(stream);
			tile.BMax[2] = ReadFloat(stream);

			// Vertices
			tile.VertexCount = ReadInt32(stream);
			tile.Vertices = new float[tile.VertexCount * 3];
			for (int32 i = 0; i < tile.VertexCount * 3; i++)
				tile.Vertices[i] = ReadFloat(stream);

			// Polygons
			tile.PolyCount = ReadInt32(stream);
			tile.Polygons = new NavPoly[tile.PolyCount];
			for (int32 i = 0; i < tile.PolyCount; i++)
			{
				ref NavPoly poly = ref tile.Polygons[i];
				poly = .();
				for (int32 j = 0; j < NavMeshConstants.MaxVertsPerPoly; j++)
					poly.VertexIndices[j] = ReadUInt16(stream);
				for (int32 j = 0; j < NavMeshConstants.MaxVertsPerPoly; j++)
					poly.Neighbors[j] = ReadUInt16(stream);

				uint8[1] buf = .();
				stream.TryRead(Span<uint8>(&buf, 1));
				poly.VertexCount = buf[0];
				stream.TryRead(Span<uint8>(&buf, 1));
				poly.Area = buf[0];
				poly.Flags = ReadUInt16(stream);
				stream.TryRead(Span<uint8>(&buf, 1));
				poly.Type = *(PolyType*)&buf[0];
				poly.FirstLink = -1;
			}

			PolyRef baseRef;
			navMesh.AddTile(tile, out baseRef);
		}

		return .Ok(navMesh);
	}

	// Binary I/O helpers
	private static void WriteInt32(MemoryStream stream, int32 value)
	{
		var value;
		stream.Write(Span<uint8>((uint8*)&value, 4));
	}

	private static void WriteUInt32(MemoryStream stream, uint32 value)
	{
		var value;
		stream.Write(Span<uint8>((uint8*)&value, 4));
	}

	private static void WriteUInt16(MemoryStream stream, uint16 value)
	{
		var value;
		stream.Write(Span<uint8>((uint8*)&value, 2));
	}

	private static void WriteFloat(MemoryStream stream, float value)
	{
		var value;
		stream.Write(Span<uint8>((uint8*)&value, 4));
	}

	private static int32 ReadInt32(MemoryStream stream)
	{
		int32 value = 0;
		stream.TryRead(Span<uint8>((uint8*)&value, 4));
		return value;
	}

	private static uint32 ReadUInt32(MemoryStream stream)
	{
		uint32 value = 0;
		stream.TryRead(Span<uint8>((uint8*)&value, 4));
		return value;
	}

	private static uint16 ReadUInt16(MemoryStream stream)
	{
		uint16 value = 0;
		stream.TryRead(Span<uint8>((uint8*)&value, 2));
		return value;
	}

	private static float ReadFloat(MemoryStream stream)
	{
		float value = 0;
		stream.TryRead(Span<uint8>((uint8*)&value, 4));
		return value;
	}
}
