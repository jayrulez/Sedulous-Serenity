namespace Sedulous.Renderer;

using Sedulous.Core.Mathematics;

/// Proxy for a reflection probe in the render world.
/// Captures local environment as a prefiltered cubemap for spatially-varying specular reflections.
public struct ReflectionProbeProxy
{
	/// World-space position of the probe center.
	public Vector3 Position;

	/// Radius of the probe's sphere of influence.
	public float Radius;

	/// Whether this probe is enabled.
	public bool IsEnabled;

	/// Whether this probe is active (slot in use).
	public bool IsActive;

	/// Generation counter for handle validation.
	public uint32 Generation;

	/// Layer index in the cubemap array (-1 = not yet assigned).
	public int32 ArrayLayer;

	/// Whether the probe needs rebaking.
	public bool IsDirty;

	// Source configuration for baking (gradient sky colors)
	/// Zenith (top) color for CPU-baked cubemap.
	public Color ZenithColor;

	/// Horizon color for CPU-baked cubemap.
	public Color HorizonColor;

	/// Ground color for CPU-baked cubemap.
	public Color GroundColor;

	/// SH9 irradiance coefficients (pre-convolved). Set by BakeProbe.
	public Vector4[9] IrradianceSH;

	/// Creates a default reflection probe proxy.
	public static Self CreateDefault()
	{
		var probe = Self();
		probe.Position = .Zero;
		probe.Radius = 10.0f;
		probe.IsEnabled = true;
		probe.IsActive = true;
		probe.ArrayLayer = -1;
		probe.IsDirty = true;
		probe.ZenithColor = .(0.2f, 0.3f, 0.5f);
		probe.HorizonColor = .(0.5f, 0.5f, 0.5f);
		probe.GroundColor = .(0.1f, 0.1f, 0.1f);
		return probe;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		Position = .Zero;
		Radius = 10.0f;
		IsEnabled = false;
		IsActive = false;
		Generation = 0;
		ArrayLayer = -1;
		IsDirty = false;
		ZenithColor = .(0.2f, 0.3f, 0.5f);
		HorizonColor = .(0.5f, 0.5f, 0.5f);
		GroundColor = .(0.1f, 0.1f, 0.1f);
	}
}
