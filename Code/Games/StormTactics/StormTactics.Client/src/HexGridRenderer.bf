namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.Foundation.Mathematics;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Render;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Resources;
using StormTactics.Battle;
using StormTactics.Core;

/// Renders the hex grid battlefield with tile meshes, grid lines, and highlights.
class HexGridRenderer
{
	private Scene mScene;
	private RenderSystem mRenderSystem;
	private OverlayRenderFeature mOverlayFeature;
	private HexGrid mGrid;
	private float mHexSize;

	// Mesh resource (shared by all tiles)
	private StaticMeshResource mHexMeshResource ~ _?.ReleaseRef();

	// Per-cell entities and materials
	private Dictionary<int64, EntityId> mTileEntities = new .() ~ delete _;
	private Dictionary<int64, MaterialInstance> mTileMaterials = new .() ~ { for (let m in _.Values) m.ReleaseRef(); delete _; };

	// Highlight state
	private Dictionary<int64, Color> mHighlights = new .() ~ delete _;

	// Colors
	private static readonly Color ATTACKER_TILE_COLOR = .(60, 35, 35, 255);
	private static readonly Color DEFENDER_TILE_COLOR = .(35, 35, 60, 255);
	private static readonly Color NEUTRAL_TILE_COLOR = .(40, 40, 40, 255);
	private static readonly Color GRID_LINE_COLOR = .(80, 80, 80, 255);

	public this(Scene scene, RenderSystem renderSystem, OverlayRenderFeature overlayFeature)
	{
		mScene = scene;
		mRenderSystem = renderSystem;
		mOverlayFeature = overlayFeature;
	}

	/// Create the hex grid visual from a battle grid.
	/// attackerMaxCol: columns 0..attackerMaxCol are attacker side.
	public void Initialize(HexGrid grid, float hexSize, int32 attackerMaxCol = -1)
	{
		mGrid = grid;
		mHexSize = hexSize;

		// Create the shared hex tile mesh
		mHexMeshResource = CreateHexMeshResource(hexSize * 0.92f); // Slightly smaller for gaps
		mHexMeshResource?.AddRef();

		let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial;
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Determine attacker/defender split (left half = attacker, right half = defender)
		let splitCol = attackerMaxCol >= 0 ? attackerMaxCol : grid.Columns / 2;

		// Create one entity per grid cell
		for (int32 row = 0; row < grid.Rows; row++)
		{
			for (int32 col = 0; col < grid.Columns; col++)
			{
				let hex = HexCoord.FromOffset(col, row);
				let key = HexKey(hex);
				let (wx, wz) = hex.ToWorld(hexSize);

				// Create entity
				let entity = mScene.CreateEntity();
				mTileEntities[key] = entity;

				// Position
				var transform = mScene.GetTransform(entity);
				transform.Position = .(wx, 0, wz);
				mScene.SetTransform(entity, transform);

				// Mesh component
				mScene.SetComponent<MeshRendererComponent>(entity, .Default);
				var comp = mScene.GetComponent<MeshRendererComponent>(entity);
				comp.Mesh = ResourceHandle<StaticMeshResource>(mHexMeshResource);

				// Material with team color
				Color tileColor;
				if (col < splitCol)
					tileColor = ATTACKER_TILE_COLOR;
				else if (col >= grid.Columns - splitCol)
					tileColor = DEFENDER_TILE_COLOR;
				else
					tileColor = NEUTRAL_TILE_COLOR;

				if (baseMaterial != null)
				{
					let mat = new MaterialInstance(baseMaterial);
					mat.SetColor("BaseColor", .(
						(float)tileColor.R / 255.0f,
						(float)tileColor.G / 255.0f,
						(float)tileColor.B / 255.0f,
						1.0f));
					mat.SetFloat("Roughness", 0.8f);
					mat.SetFloat("Metallic", 0.0f);
					mTileMaterials[key] = mat;
					comp.MaterialInstances[0] = mat;
					comp.MaterialInstances[0].AddRef();
					comp.MaterialRefs.Count = 1;
				}
				else if (defaultMaterial != null)
				{
					comp.MaterialInstances[0] = defaultMaterial;
					comp.MaterialInstances[0].AddRef();
					comp.MaterialRefs.Count = 1;
				}
			}
		}
	}

	/// Set a hex cell to a highlight color.
	public void SetHighlight(HexCoord hex, Color color)
	{
		let key = HexKey(hex);
		mHighlights[key] = color;
	}

	/// Clear all highlights.
	public void ClearHighlights()
	{
		mHighlights.Clear();
	}

	/// Draw per-frame overlays (grid lines, highlights).
	/// Must be called every frame before render.
	public void DrawOverlays()
	{
		if (mOverlayFeature == null || mGrid == null) return;

		for (int32 row = 0; row < mGrid.Rows; row++)
		{
			for (int32 col = 0; col < mGrid.Columns; col++)
			{
				let hex = HexCoord.FromOffset(col, row);
				let (cx, cz) = hex.ToWorld(mHexSize);
				let key = HexKey(hex);

				// Draw hex outline
				DrawHexOutline(cx, cz, mHexSize, GRID_LINE_COLOR);

				// Draw highlight overlay
				if (mHighlights.TryGetValue(key, let highlightColor))
				{
					DrawHexFilled(cx, cz, mHexSize * 0.85f, highlightColor);
				}
			}
		}
	}

	/// Draw a hex outline using debug lines.
	private void DrawHexOutline(float cx, float cz, float size, Color color)
	{
		let y = 0.02f; // Slightly above ground to avoid z-fighting
		for (int i = 0; i < 6; i++)
		{
			let angle0 = (float)i * Math.PI_f / 3.0f;
			let angle1 = (float)((i + 1) % 6) * Math.PI_f / 3.0f;

			let x0 = cx + size * Math.Cos(angle0);
			let z0 = cz + size * Math.Sin(angle0);
			let x1 = cx + size * Math.Cos(angle1);
			let z1 = cz + size * Math.Sin(angle1);

			mOverlayFeature.AddLine(.(x0, y, z0), .(x1, y, z1), color, .DepthTest);
		}
	}

	/// Draw a filled hex using debug triangles.
	private void DrawHexFilled(float cx, float cz, float size, Color color)
	{
		let y = 0.03f;
		let center = Vector3(cx, y, cz);

		for (int i = 0; i < 6; i++)
		{
			let angle0 = (float)i * Math.PI_f / 3.0f;
			let angle1 = (float)((i + 1) % 6) * Math.PI_f / 3.0f;

			let v0 = Vector3(cx + size * Math.Cos(angle0), y, cz + size * Math.Sin(angle0));
			let v1 = Vector3(cx + size * Math.Cos(angle1), y, cz + size * Math.Sin(angle1));

			mOverlayFeature.AddTriangle(center, v0, v1, color, .DepthTest);
		}
	}

	/// Get the world-space center and extent of the entire grid.
	public void GetGridBounds(out float centerX, out float centerZ, out float extent)
	{
		if (mGrid == null)
		{
			centerX = 0;
			centerZ = 0;
			extent = 10;
			return;
		}

		float minX = float.MaxValue, maxX = float.MinValue;
		float minZ = float.MaxValue, maxZ = float.MinValue;

		for (int32 row = 0; row < mGrid.Rows; row++)
		{
			for (int32 col = 0; col < mGrid.Columns; col++)
			{
				let hex = HexCoord.FromOffset(col, row);
				let (wx, wz) = hex.ToWorld(mHexSize);
				minX = Math.Min(minX, wx);
				maxX = Math.Max(maxX, wx);
				minZ = Math.Min(minZ, wz);
				maxZ = Math.Max(maxZ, wz);
			}
		}

		centerX = (minX + maxX) * 0.5f;
		centerZ = (minZ + maxZ) * 0.5f;
		extent = Math.Max(maxX - minX, maxZ - minZ) * 0.5f + mHexSize;
	}

	/// Cleanup all entities and materials.
	public void Shutdown()
	{
		// Destroy tile entities from the scene
		if (mScene != null)
		{
			for (let entry in mTileEntities)
				mScene.DestroyEntity(entry.value);
		}
		mTileEntities.Clear();
		mHighlights.Clear();
	}

	// --- Helpers ---

	/// Create a hex key from a HexCoord for dictionary lookup.
	private static int64 HexKey(HexCoord hex)
	{
		return ((int64)hex.Q << 32) | (int64)(uint32)hex.R;
	}

	/// Create a flat hexagonal tile mesh.
	private static StaticMeshResource CreateHexMeshResource(float radius)
	{
		let mesh = new StaticMesh();
		mesh.SetupCommonVertexFormat();

		// Top face: 7 vertices (center + 6 corners), 6 triangles
		// Bottom face: same (for underside visibility)
		// Total: 14 vertices, 12 triangles = 36 indices
		mesh.Vertices.Resize(14);
		mesh.Indices.Resize(36);

		let height = 0.04f; // Thin tile

		// Top face vertices
		mesh.SetPosition(0, .(0, height, 0));
		mesh.SetNormal(0, .(0, 1, 0));
		mesh.SetUV(0, .(0.5f, 0.5f));
		mesh.SetColor(0, 0xFFFFFFFF);

		for (int32 i = 0; i < 6; i++)
		{
			let angle = (float)i * Math.PI_f / 3.0f;
			let x = radius * Math.Cos(angle);
			let z = radius * Math.Sin(angle);

			mesh.SetPosition(i + 1, .(x, height, z));
			mesh.SetNormal(i + 1, .(0, 1, 0));
			mesh.SetUV(i + 1, .(0.5f + 0.5f * Math.Cos(angle), 0.5f + 0.5f * Math.Sin(angle)));
			mesh.SetColor(i + 1, 0xFFFFFFFF);
		}

		// Bottom face vertices (center at 7, corners at 8-13)
		mesh.SetPosition(7, .(0, 0, 0));
		mesh.SetNormal(7, .(0, -1, 0));
		mesh.SetUV(7, .(0.5f, 0.5f));
		mesh.SetColor(7, 0xFFFFFFFF);

		for (int32 i = 0; i < 6; i++)
		{
			let angle = (float)i * Math.PI_f / 3.0f;
			let x = radius * Math.Cos(angle);
			let z = radius * Math.Sin(angle);

			mesh.SetPosition(i + 8, .(x, 0, z));
			mesh.SetNormal(i + 8, .(0, -1, 0));
			mesh.SetUV(i + 8, .(0.5f + 0.5f * Math.Cos(angle), 0.5f + 0.5f * Math.Sin(angle)));
			mesh.SetColor(i + 8, 0xFFFFFFFF);
		}

		// Top face triangles (CCW winding when viewed from above/outside)
		for (int32 i = 0; i < 6; i++)
		{
			let next = (i + 1) % 6;
			mesh.Indices.SetIndex(i * 3, (uint32)0);
			mesh.Indices.SetIndex(i * 3 + 1, (uint32)(i + 1));
			mesh.Indices.SetIndex(i * 3 + 2, (uint32)(next + 1));
		}

		// Bottom face triangles (reversed winding for underside)
		for (int32 i = 0; i < 6; i++)
		{
			let next = (i + 1) % 6;
			let baseIdx = 18 + i * 3;
			mesh.Indices.SetIndex(baseIdx, (uint32)7);
			mesh.Indices.SetIndex(baseIdx + 1, (uint32)(next + 8));
			mesh.Indices.SetIndex(baseIdx + 2, (uint32)(i + 8));
		}

		// Generate tangents and add submesh
		mesh.GenerateTangents();
		mesh.AddSubMesh(SubMesh(0, 36));

		return new StaticMeshResource(mesh, true);
	}
}
