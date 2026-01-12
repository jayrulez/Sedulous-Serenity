namespace TowerDefense.Maps;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Renderer;
using TowerDefense.Data;

/// Builds map entities from a MapDefinition.
/// Creates tile meshes with appropriate materials for each tile type.
class MapBuilder
{
	private Scene mScene;
	private RendererService mRendererService;
	private MapDefinition mMap;

	// Shared mesh for all tiles
	private StaticMesh mTileMesh ~ delete _;

	// Materials for different tile types
	private MaterialHandle mPBRMaterial = .Invalid;
	private MaterialInstanceHandle mGrassMaterial = .Invalid;
	private MaterialInstanceHandle mPathMaterial = .Invalid;
	private MaterialInstanceHandle mWaterMaterial = .Invalid;
	private MaterialInstanceHandle mBlockedMaterial = .Invalid;
	private MaterialInstanceHandle mSpawnMaterial = .Invalid;
	private MaterialInstanceHandle mExitMaterial = .Invalid;

	// Created tile entities (for cleanup)
	private List<Entity> mTileEntities = new .() ~ delete _;

	/// Creates a new MapBuilder for the given scene.
	public this(Scene scene, RendererService rendererService)
	{
		mScene = scene;
		mRendererService = rendererService;
	}

	/// Initializes materials for tile rendering.
	/// Call this once before building any maps.
	public void InitializeMaterials()
	{
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null)
			return;

		// Create shared tile mesh (flat cube)
		mTileMesh = StaticMesh.CreateCube(1.0f);

		// Create PBR material template
		let pbrMaterial = Material.CreatePBR("TileMaterial");
		mPBRMaterial = materialSystem.RegisterMaterial(pbrMaterial);

		if (!mPBRMaterial.IsValid)
		{
			Console.WriteLine("MapBuilder: Failed to create PBR material");
			return;
		}

		// Create material instances for each tile type
		mGrassMaterial = CreateTileMaterial(.(0.3f, 0.55f, 0.25f, 1.0f), 0.0f, 0.85f);   // Green grass
		mPathMaterial = CreateTileMaterial(.(0.5f, 0.45f, 0.35f, 1.0f), 0.0f, 0.9f);     // Brown dirt path
		mWaterMaterial = CreateTileMaterial(.(0.2f, 0.4f, 0.7f, 1.0f), 0.0f, 0.3f);      // Blue water
		mBlockedMaterial = CreateTileMaterial(.(0.4f, 0.4f, 0.4f, 1.0f), 0.0f, 0.95f);   // Gray rocks
		mSpawnMaterial = CreateTileMaterial(.(0.7f, 0.2f, 0.2f, 1.0f), 0.0f, 0.7f);      // Red spawn
		mExitMaterial = CreateTileMaterial(.(0.2f, 0.7f, 0.2f, 1.0f), 0.0f, 0.7f);       // Green exit

		Console.WriteLine("MapBuilder: Materials initialized");
	}

	private MaterialInstanceHandle CreateTileMaterial(Vector4 color, float metallic, float roughness)
	{
		let materialSystem = mRendererService.MaterialSystem;
		let handle = materialSystem.CreateInstance(mPBRMaterial);

		if (handle.IsValid)
		{
			let instance = materialSystem.GetInstance(handle);
			if (instance != null)
			{
				instance.SetFloat4("baseColor", color);
				instance.SetFloat("metallic", metallic);
				instance.SetFloat("roughness", roughness);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(handle);
			}
		}

		return handle;
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
		let entity = mScene.CreateEntity(scope $"Tile_{gridX}_{gridY}");

		// Position tile (flat on ground, scaled to tile size)
		// Y position varies slightly by type for visual depth
		float yOffset = GetTileYOffset(tileType);
		entity.Transform.SetPosition(.(worldPos.X, yOffset, worldPos.Z));
		entity.Transform.SetScale(.(tileSize * 0.95f, 0.2f, tileSize * 0.95f));  // Slight gap between tiles

		// Add mesh component
		let meshComp = new StaticMeshComponent();
		entity.AddComponent(meshComp);
		meshComp.SetMesh(mTileMesh);
		meshComp.SetMaterialInstance(0, GetMaterialForTileType(tileType));

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

	private MaterialInstanceHandle GetMaterialForTileType(TileType tileType)
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
			mScene.DestroyEntity(entity.Id);
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

		let materialSystem = mRendererService?.MaterialSystem;
		if (materialSystem != null)
		{
			if (mGrassMaterial.IsValid) materialSystem.ReleaseInstance(mGrassMaterial);
			if (mPathMaterial.IsValid) materialSystem.ReleaseInstance(mPathMaterial);
			if (mWaterMaterial.IsValid) materialSystem.ReleaseInstance(mWaterMaterial);
			if (mBlockedMaterial.IsValid) materialSystem.ReleaseInstance(mBlockedMaterial);
			if (mSpawnMaterial.IsValid) materialSystem.ReleaseInstance(mSpawnMaterial);
			if (mExitMaterial.IsValid) materialSystem.ReleaseInstance(mExitMaterial);
			if (mPBRMaterial.IsValid) materialSystem.ReleaseMaterial(mPBRMaterial);
		}

		mGrassMaterial = .Invalid;
		mPathMaterial = .Invalid;
		mWaterMaterial = .Invalid;
		mBlockedMaterial = .Invalid;
		mSpawnMaterial = .Invalid;
		mExitMaterial = .Invalid;
		mPBRMaterial = .Invalid;
	}
}
