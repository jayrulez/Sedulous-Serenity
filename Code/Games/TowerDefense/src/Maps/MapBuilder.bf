namespace TowerDefense.Maps;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Resources;
using Sedulous.Materials;
using Sedulous.Render;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using TowerDefense.Data;

/// Builds map entities from a MapDefinition.
/// Creates tile meshes with appropriate materials for each tile type.
/// Ported to Sedulous.Framework architecture.
class MapBuilder
{
	private Scene mScene;
	private RenderSceneModule mRenderModule;
	private RenderSystem mRenderSystem;
	private MapDefinition mMap;

	// Shared mesh for all tiles
	private StaticMeshResource mTileMesh;

	// Materials for different tile types
	private MaterialInstance mGrassMaterial ~ delete _;
	private MaterialInstance mPathMaterial ~ delete _;
	private MaterialInstance mWaterMaterial ~ delete _;
	private MaterialInstance mBlockedMaterial ~ delete _;
	private MaterialInstance mSpawnMaterial ~ delete _;
	private MaterialInstance mExitMaterial ~ delete _;

	// Created tile entities (for cleanup)
	private List<EntityId> mTileEntities = new .() ~ delete _;

	/// Creates a new MapBuilder for the given scene.
	public this(Scene scene, RenderSceneModule renderModule, RenderSystem renderSystem, StaticMeshResource tileMesh)
	{
		mScene = scene;
		mRenderModule = renderModule;
		mRenderSystem = renderSystem;
		mTileMesh = tileMesh;
	}

	/// Initializes materials for tile rendering.
	/// Call this once before building any maps.
	public void InitializeMaterials()
	{
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMat == null)
		{
			Console.WriteLine("MapBuilder: Failed to get default material");
			return;
		}

		// Create material instances for each tile type
		mGrassMaterial = CreateTileMaterial(baseMat, .(0.3f, 0.55f, 0.25f, 1.0f), 0.0f, 0.85f);   // Green grass
		mPathMaterial = CreateTileMaterial(baseMat, .(0.5f, 0.45f, 0.35f, 1.0f), 0.0f, 0.9f);     // Brown dirt path
		mWaterMaterial = CreateTileMaterial(baseMat, .(0.2f, 0.4f, 0.7f, 1.0f), 0.0f, 0.3f);      // Blue water
		mBlockedMaterial = CreateTileMaterial(baseMat, .(0.4f, 0.4f, 0.4f, 1.0f), 0.0f, 0.95f);   // Gray rocks
		mSpawnMaterial = CreateTileMaterial(baseMat, .(0.7f, 0.2f, 0.2f, 1.0f), 0.0f, 0.7f);      // Red spawn
		mExitMaterial = CreateTileMaterial(baseMat, .(0.2f, 0.7f, 0.2f, 1.0f), 0.0f, 0.7f);       // Green exit

		Console.WriteLine("MapBuilder: Materials initialized");
	}

	private MaterialInstance CreateTileMaterial(Material baseMat, Vector4 color, float metallic, float roughness)
	{
		let mat = new MaterialInstance(baseMat);
		mat.SetColor("BaseColor", color);
		mat.SetFloat("Metallic", metallic);
		mat.SetFloat("Roughness", roughness);
		return mat;
	}

	/// Builds the map from the given definition.
	/// Creates tile entities for each grid cell.
	public void BuildMap(MapDefinition map)
	{
		// Clear any existing map
		ClearMap();

		mMap = map;

		Console.WriteLine($"MapBuilder: Building map '{map.Name}' ({map.Width}x{map.Height})");

		// Create tile entities
		for (int32 y = 0; y < map.Height; y++)
		{
			for (int32 x = 0; x < map.Width; x++)
			{
				let tileType = map.GetTile(x, y);
				let worldPos = map.GridToWorld(x, y);

				CreateTileEntity(x, y, tileType, worldPos, map.TileSize);
			}
		}

		Console.WriteLine($"MapBuilder: Created {mTileEntities.Count} tile entities");
	}

	private void CreateTileEntity(int32 gridX, int32 gridY, TileType tileType, Vector3 worldPos, float tileSize)
	{
		let entity = mScene.CreateEntity();

		// Position tile (flat on ground, scaled to tile size)
		// Y position varies slightly by type for visual depth
		float yOffset = GetTileYOffset(tileType);
		var transform = mScene.GetTransform(entity);
		transform.Position = .(worldPos.X, yOffset, worldPos.Z);
		transform.Scale = .(tileSize * 0.95f, 0.2f, tileSize * 0.95f);  // Slight gap between tiles
		mScene.SetTransform(entity, transform);

		// Add mesh renderer component
		mScene.SetComponent<MeshRendererComponent>(entity, .Default);
		var meshComp = mScene.GetComponent<MeshRendererComponent>(entity);
		meshComp.Mesh = ResourceHandle<StaticMeshResource>(mTileMesh);
		meshComp.Material = GetMaterialForTileType(tileType);

		mTileEntities.Add(entity);
	}

	private float GetTileYOffset(TileType tileType)
	{
		switch (tileType)
		{
		case .Water: return -0.15f;    // Water is lower
		case .Path, .Spawn, .Exit: return -0.05f;  // Paths slightly recessed
		case .Blocked: return 0.1f;    // Rocks slightly raised
		default: return 0.0f;          // Grass at ground level
		}
	}

	private MaterialInstance GetMaterialForTileType(TileType tileType)
	{
		switch (tileType)
		{
		case .Grass: return mGrassMaterial;
		case .Path: return mPathMaterial;
		case .Water: return mWaterMaterial;
		case .Blocked: return mBlockedMaterial;
		case .Spawn: return mSpawnMaterial;
		case .Exit: return mExitMaterial;
		}
	}

	/// Clears all tile entities from the scene.
	public void ClearMap()
	{
		for (let entity in mTileEntities)
		{
			mScene.DestroyEntity(entity);
		}
		mTileEntities.Clear();
		mMap = null;
	}

	/// Gets the current map definition.
	public MapDefinition CurrentMap => mMap;

	/// Checks if a tower can be placed at the given grid position.
	public bool CanPlaceTower(int32 gridX, int32 gridY)
	{
		if (mMap == null)
			return false;

		let tileType = mMap.GetTile(gridX, gridY);
		return tileType.IsBuildable;
	}

	/// Gets the world position for the center of a grid cell.
	public Vector3 GetTileWorldPosition(int32 gridX, int32 gridY)
	{
		if (mMap == null)
			return .Zero;
		return mMap.GridToWorld(gridX, gridY);
	}

	/// Releases all materials.
	public void Cleanup()
	{
		ClearMap();
	}
}
