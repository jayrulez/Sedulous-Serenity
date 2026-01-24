using System;
using Sedulous.Navigation;
using Sedulous.Navigation.Recast;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Tests;

class SerializationTests
{
	[Test]
	public static void TestSaveAndLoad()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		if (!result.Success || result.NavMesh == null)
		{
			if (result.NavMesh != null) delete result.NavMesh;
			return;
		}

		// Save
		let saveResult = NavMeshSerializer.Save(result.NavMesh);
		delete result.NavMesh;
		result.NavMesh = null;

		Test.Assert(saveResult case .Ok, "Save should succeed");

		if (saveResult case .Ok(let data))
		{
			Test.Assert(data.Count > 0, "Saved data should not be empty");

			// Load
			let loadResult = NavMeshSerializer.Load(data);
			delete data;

			Test.Assert(loadResult case .Ok, "Load should succeed");

			if (loadResult case .Ok(let loadedMesh))
			{
				Test.Assert(loadedMesh.TileCount > 0, "Loaded mesh should have tiles");

				let tile = loadedMesh.GetTile(0);
				Test.Assert(tile != null, "Should have tile at index 0");
				if (tile != null)
				{
					Test.Assert(tile.PolyCount > 0, "Tile should have polygons");
					Test.Assert(tile.VertexCount > 0, "Tile should have vertices");
				}

				delete loadedMesh;
			}
		}
	}

	[Test]
	public static void TestInvalidDataReturnsError()
	{
		let badData = new uint8[](0, 0, 0, 0, 0, 0, 0, 0);
		defer delete badData;

		let loadResult = NavMeshSerializer.Load(badData);
		Test.Assert(loadResult case .Err, "Loading invalid data should fail");
	}
}
