namespace Sedulous.Renderer;

using Sedulous.Core.Mathematics;
using Sedulous.RHI;

/// Proxy for instanced grass rendering in the render world.
/// Each proxy represents one grass type placed on terrain via CPU heightmap/splatmap data.
public struct GrassProxy
{
	// --- Terrain placement data ---

	/// World-space origin of the terrain this grass is placed on.
	public Vector3 TerrainOrigin;

	/// XZ extent of the terrain in world units.
	public Vector2 TerrainWorldSize;

	/// Height multiplier applied to heightmap values.
	public float HeightScale;

	/// CPU heightmap data (non-owning pointer, caller retains lifetime).
	/// Values in [0,1] range, multiplied by HeightScale for world Y.
	public float* HeightmapData;

	/// Heightmap dimensions in texels.
	public uint32 HeightmapWidth;
	public uint32 HeightmapHeight;

	/// CPU splatmap data (non-owning pointer, optional, RGBA8 packed).
	/// Used to gate grass placement by terrain layer.
	public uint8* SplatmapData;

	/// Splatmap dimensions in texels.
	public uint32 SplatmapWidth;
	public uint32 SplatmapHeight;

	/// Which RGBA channel (0-3) to gate placement on. -1 = place everywhere.
	public int32 SplatChannel;

	/// Minimum splatmap weight [0-255] to place a grass blade.
	public float SplatThreshold;

	// --- Appearance ---

	/// Base color tint for grass blades (linear).
	public Vector3 GrassColor;

	/// Alpha discard threshold.
	public float AlphaCutoff;

	/// PBR roughness.
	public float Roughness;

	/// Blade width in world units.
	public float BladeWidth;

	/// Blade height in world units.
	public float BladeHeight;

	// --- Placement ---

	/// Maximum render distance from camera.
	public float Distance;

	/// Blades per square world unit.
	public float Density;

	/// Random scale range minimum.
	public float MinScale;

	/// Random scale range maximum.
	public float MaxScale;

	// --- Wind ---

	/// Wind displacement strength.
	public float WindStrength;

	/// Wind oscillation frequency.
	public float WindFrequency;

	/// Wind direction (XZ, normalized).
	public Vector2 WindDirection;

	// --- Texture ---

	/// Grass blade albedo texture with alpha mask (non-owning).
	public ITextureView AlbedoView;

	// --- Proxy state ---

	/// Whether this proxy slot is active.
	public bool IsActive;

	/// Generation counter for handle validation.
	public uint32 Generation;

	/// World-space bounding box.
	public BoundingBox WorldBounds;

	/// Creates a default grass proxy with sensible defaults.
	public static Self CreateDefault()
	{
		var grass = Self();
		grass.TerrainOrigin = .Zero;
		grass.TerrainWorldSize = .(256, 256);
		grass.HeightScale = 30.0f;
		grass.HeightmapData = null;
		grass.HeightmapWidth = 0;
		grass.HeightmapHeight = 0;
		grass.SplatmapData = null;
		grass.SplatmapWidth = 0;
		grass.SplatmapHeight = 0;
		grass.SplatChannel = -1;
		grass.SplatThreshold = 0.3f;
		grass.GrassColor = .(0.3f, 0.5f, 0.15f);
		grass.AlphaCutoff = 0.5f;
		grass.Roughness = 0.8f;
		grass.BladeWidth = 0.15f;
		grass.BladeHeight = 0.6f;
		grass.Distance = 50.0f;
		grass.Density = 4.0f;
		grass.MinScale = 0.6f;
		grass.MaxScale = 1.2f;
		grass.WindStrength = 0.3f;
		grass.WindFrequency = 1.5f;
		grass.WindDirection = Vector2.Normalize(.(1.0f, 0.3f));
		grass.AlbedoView = null;
		grass.IsActive = true;
		return grass;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		TerrainOrigin = .Zero;
		TerrainWorldSize = .(256, 256);
		HeightScale = 30.0f;
		HeightmapData = null;
		HeightmapWidth = 0;
		HeightmapHeight = 0;
		SplatmapData = null;
		SplatmapWidth = 0;
		SplatmapHeight = 0;
		SplatChannel = -1;
		SplatThreshold = 0.3f;
		GrassColor = .(0.3f, 0.5f, 0.15f);
		AlphaCutoff = 0.5f;
		Roughness = 0.8f;
		BladeWidth = 0.15f;
		BladeHeight = 0.6f;
		Distance = 50.0f;
		Density = 4.0f;
		MinScale = 0.6f;
		MaxScale = 1.2f;
		WindStrength = 0.3f;
		WindFrequency = 1.5f;
		WindDirection = Vector2.Normalize(.(1.0f, 0.3f));
		AlbedoView = null;
		IsActive = false;
		Generation = 0;
		WorldBounds = default;
	}
}
