namespace Sedulous.Render;

using Sedulous.Core.Mathematics;
using Sedulous.RHI;

/// Proxy for a terrain in the render world.
/// Heightmap-based terrain rendered as a chunked grid with splatmap texture blending.
public struct TerrainProxy
{
	/// World-space origin (corner 0,0).
	public Vector3 Position;

	/// XZ extent in world units.
	public Vector2 WorldSize;

	/// Y multiplier for heightmap values.
	public float HeightScale;

	/// Heightmap texture view (R16Unorm or R32Float). Non-owning.
	public ITextureView HeightmapView;

	/// Normal map texture view (RGBA8, XYZ normal). Non-owning.
	public ITextureView NormalMapView;

	/// Splatmap texture view (RGBA8, 4 layer weights). Non-owning.
	public ITextureView SplatmapView;

	/// Per-layer albedo texture views. Non-owning.
	public ITextureView[4] LayerAlbedoViews;

	/// Heightmap width in texels.
	public uint32 HeightmapWidth;

	/// Heightmap height in texels.
	public uint32 HeightmapHeight;

	/// Number of patches in X direction.
	public int32 PatchCountX;

	/// Number of patches in Z direction.
	public int32 PatchCountZ;

	/// UV tiling scale per layer.
	public Vector4 LayerScales;

	/// Base roughness.
	public float Roughness;

	/// Base metallic.
	public float Metallic;

	/// Whether this terrain is active (slot in use).
	public bool IsActive;

	/// Generation counter for handle validation.
	public uint32 Generation;

	/// World-space bounding box.
	public BoundingBox WorldBounds;

	/// Creates a default terrain proxy.
	public static Self CreateDefault()
	{
		var terrain = Self();
		terrain.Position = .Zero;
		terrain.WorldSize = .(256, 256);
		terrain.HeightScale = 30.0f;
		terrain.HeightmapWidth = 512;
		terrain.HeightmapHeight = 512;
		terrain.PatchCountX = 8;
		terrain.PatchCountZ = 8;
		terrain.LayerScales = .(16.0f, 16.0f, 16.0f, 16.0f);
		terrain.Roughness = 0.85f;
		terrain.Metallic = 0.0f;
		terrain.IsActive = true;
		return terrain;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		Position = .Zero;
		WorldSize = .(256, 256);
		HeightScale = 30.0f;
		HeightmapView = null;
		NormalMapView = null;
		SplatmapView = null;
		LayerAlbedoViews = default;
		HeightmapWidth = 512;
		HeightmapHeight = 512;
		PatchCountX = 8;
		PatchCountZ = 8;
		LayerScales = .(16.0f, 16.0f, 16.0f, 16.0f);
		Roughness = 0.85f;
		Metallic = 0.0f;
		IsActive = false;
		Generation = 0;
		WorldBounds = default;
	}
}
