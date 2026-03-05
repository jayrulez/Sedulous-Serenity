namespace Sedulous.Render;

using Sedulous.Core.Mathematics;
using Sedulous.RHI;

/// Proxy for a water plane in the render world.
/// Animated waves, screen-space refraction, Fresnel reflection, depth-based absorption, and shore foam.
public struct WaterProxy
{
	/// World-space center of the water plane.
	public Vector3 Position;

	/// XZ extent in world units.
	public Vector2 Size;

	/// Deep water color (linear).
	public Vector4 WaterColor;

	/// Wave animation speed.
	public float WaveSpeed;

	/// UV tiling scale for wave normal map.
	public float WaveScale;

	/// Wave normal intensity.
	public float NormalStrength;

	/// Schlick R0 (typically 0.02 for water).
	public float FresnelR0;

	/// Screen-space refraction distortion amount.
	public float RefractionStrength;

	/// Blinn-Phong specular exponent.
	public float SpecularPower;

	/// Depth at which water becomes fully opaque.
	public float MaxVisibleDepth;

	/// Depth threshold for foam rendering.
	public float FoamDepthThreshold;

	/// Foam brightness.
	public float FoamIntensity;

	/// PBR roughness for probes/IBL.
	public float Roughness;

	/// Wave scroll direction (normalized).
	public Vector2 FlowDirection;

	/// Wave normal/height map (RGBA8, non-owning).
	public ITextureView NormalMapView;

	/// Foam texture (non-owning, optional).
	public ITextureView FoamTextureView;

	/// Whether this water plane is active (slot in use).
	public bool IsActive;

	/// Generation counter for handle validation.
	public uint32 Generation;

	/// World-space bounding box.
	public BoundingBox WorldBounds;

	/// Creates a default water proxy.
	public static Self CreateDefault()
	{
		var water = Self();
		water.Position = .Zero;
		water.Size = .(256, 256);
		water.WaterColor = .(0.0f, 0.05f, 0.1f, 1.0f);
		water.WaveSpeed = 1.0f;
		water.WaveScale = 8.0f;
		water.NormalStrength = 0.5f;
		water.FresnelR0 = 0.02f;
		water.RefractionStrength = 0.03f;
		water.SpecularPower = 256.0f;
		water.MaxVisibleDepth = 10.0f;
		water.FoamDepthThreshold = 0.5f;
		water.FoamIntensity = 0.8f;
		water.Roughness = 0.1f;
		water.FlowDirection = .(1.0f, 0.0f);
		water.IsActive = true;
		return water;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		Position = .Zero;
		Size = .(256, 256);
		WaterColor = .(0.0f, 0.05f, 0.1f, 1.0f);
		WaveSpeed = 1.0f;
		WaveScale = 8.0f;
		NormalStrength = 0.5f;
		FresnelR0 = 0.02f;
		RefractionStrength = 0.03f;
		SpecularPower = 256.0f;
		MaxVisibleDepth = 10.0f;
		FoamDepthThreshold = 0.5f;
		FoamIntensity = 0.8f;
		Roughness = 0.1f;
		FlowDirection = .(1.0f, 0.0f);
		NormalMapView = null;
		FoamTextureView = null;
		IsActive = false;
		Generation = 0;
		WorldBounds = default;
	}
}
