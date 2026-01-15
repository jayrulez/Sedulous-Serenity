namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// GPU-compatible light data structure.
/// Must match shader cbuffer layout.
[CRepr]
struct LightData
{
	public Vector3 Position;      // World position (point/spot)
	public float Range;           // Attenuation range

	public Vector3 Direction;     // Light direction (directional/spot)
	public float SpotInnerAngle;  // Inner cone angle (radians)

	public Vector3 Color;         // Light color (linear RGB)
	public float Intensity;       // Light intensity multiplier

	public uint32 Type;           // Light type (0=dir, 1=point, 2=spot)
	public float SpotOuterAngle;  // Outer cone angle (radians)
	public uint32 ShadowIndex;    // Index into shadow atlas (-1 if no shadow)
	public uint32 Padding;

	public const uint32 Size = 64;

	/// Creates a directional light.
	public static Self Directional(Vector3 direction, Vector3 color, float intensity)
	{
		var light = Self();
		light.Type = 0; // Directional
		light.Direction = Vector3.Normalize(direction);
		light.Color = color;
		light.Intensity = intensity;
		light.Range = float.MaxValue;
		light.ShadowIndex = uint32.MaxValue;
		return light;
	}

	/// Creates a point light.
	public static Self Point(Vector3 position, float range, Vector3 color, float intensity)
	{
		var light = Self();
		light.Type = 1; // Point
		light.Position = position;
		light.Range = range;
		light.Color = color;
		light.Intensity = intensity;
		light.ShadowIndex = uint32.MaxValue;
		return light;
	}

	/// Creates a spot light.
	public static Self Spot(Vector3 position, Vector3 direction, float range,
							float innerAngle, float outerAngle, Vector3 color, float intensity)
	{
		var light = Self();
		light.Type = 2; // Spot
		light.Position = position;
		light.Direction = Vector3.Normalize(direction);
		light.Range = range;
		light.SpotInnerAngle = innerAngle;
		light.SpotOuterAngle = outerAngle;
		light.Color = color;
		light.Intensity = intensity;
		light.ShadowIndex = uint32.MaxValue;
		return light;
	}
}

/// Global lighting parameters for the scene.
[CRepr]
struct LightingParams
{
	public Vector3 AmbientColor;
	public float AmbientIntensity;

	public Vector3 SunDirection;
	public float SunIntensity;

	public Vector3 SunColor;
	public uint32 LightCount;

	public Vector4 FogParams; // x=start, y=end, z=density, w=mode (0=none, 1=linear, 2=exp, 3=exp2)
	public Vector3 FogColor;
	public float Padding;

	public const uint32 Size = 80;

	public static Self Default()
	{
		var result = Self();
		result.AmbientColor = .(0.1f, 0.1f, 0.15f);
		result.AmbientIntensity = 1.0f;
		result.SunDirection = Vector3.Normalize(.(0.5f, -1.0f, 0.3f));
		result.SunIntensity = 1.0f;
		result.SunColor = .(1.0f, 0.95f, 0.9f);
		result.LightCount = 0;
		result.FogParams = .(100, 500, 0.01f, 0);
		result.FogColor = .(0.5f, 0.6f, 0.7f);
		return result;
	}
}

/// Manages GPU light data for the renderer.
class LightBuffer : IDisposable
{
	private IDevice mDevice;

	// Light storage
	private List<LightData> mLights = new .() ~ delete _;
	private LightingParams mParams;

	// GPU buffers
	private IBuffer mLightDataBuffer ~ delete _;
	private IBuffer mLightingParamsBuffer ~ delete _;

	// Configuration
	public const uint32 MaxLights = 1024;

	// Dirty tracking
	private bool mLightsDirty = true;
	private bool mParamsDirty = true;

	/// Creates a new light buffer.
	public this()
	{
		mParams = .Default();
	}

	/// Initializes GPU buffers.
	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create light data buffer
		var lightDesc = BufferDescriptor(MaxLights * LightData.Size, .Uniform, .Upload);
		lightDesc.Label = "LightDataBuffer";

		switch (device.CreateBuffer(&lightDesc))
		{
		case .Ok(let buffer):
			mLightDataBuffer = buffer;
		case .Err:
			return .Err;
		}

		// Create lighting params buffer
		var paramsDesc = BufferDescriptor(LightingParams.Size, .Uniform, .Upload);
		paramsDesc.Label = "LightingParamsBuffer";

		switch (device.CreateBuffer(&paramsDesc))
		{
		case .Ok(let buffer):
			mLightingParamsBuffer = buffer;
		case .Err:
			return .Err;
		}

		return .Ok;
	}

	/// Clears all lights.
	public void Clear()
	{
		mLights.Clear();
		mLightsDirty = true;
	}

	/// Adds a light.
	public void AddLight(LightData light)
	{
		if (mLights.Count < MaxLights)
		{
			mLights.Add(light);
			mLightsDirty = true;
		}
	}

	/// Adds a directional light.
	public void AddDirectionalLight(Vector3 direction, Vector3 color, float intensity)
	{
		AddLight(.Directional(direction, color, intensity));
	}

	/// Adds a point light.
	public void AddPointLight(Vector3 position, float range, Vector3 color, float intensity)
	{
		AddLight(.Point(position, range, color, intensity));
	}

	/// Adds a spot light.
	public void AddSpotLight(Vector3 position, Vector3 direction, float range,
							 float innerAngle, float outerAngle, Vector3 color, float intensity)
	{
		AddLight(.Spot(position, direction, range, innerAngle, outerAngle, color, intensity));
	}

	/// Sets ambient lighting.
	public void SetAmbient(Vector3 color, float intensity)
	{
		mParams.AmbientColor = color;
		mParams.AmbientIntensity = intensity;
		mParamsDirty = true;
	}

	/// Sets sun (main directional) light.
	public void SetSun(Vector3 direction, Vector3 color, float intensity)
	{
		mParams.SunDirection = Vector3.Normalize(direction);
		mParams.SunColor = color;
		mParams.SunIntensity = intensity;
		mParamsDirty = true;
	}

	/// Sets fog parameters.
	public void SetFog(float start, float end, float density, int mode, Vector3 color)
	{
		mParams.FogParams = .(start, end, density, (float)mode);
		mParams.FogColor = color;
		mParamsDirty = true;
	}

	/// Uploads light data to GPU.
	public void Upload()
	{
		// Upload lighting params
		if (mParamsDirty && mLightingParamsBuffer != null)
		{
			mParams.LightCount = (uint32)mLights.Count;
			let ptr = mLightingParamsBuffer.Map();
			if (ptr != null)
			{
				*(LightingParams*)ptr = mParams;
				mLightingParamsBuffer.Unmap();
			}
			mParamsDirty = false;
		}

		// Upload light data
		if (mLightsDirty && mLightDataBuffer != null && mLights.Count > 0)
		{
			let ptr = mLightDataBuffer.Map();
			if (ptr != null)
			{
				Internal.MemCpy(ptr, mLights.Ptr, mLights.Count * LightData.Size);
				mLightDataBuffer.Unmap();
			}
			mLightsDirty = false;
		}
	}

	/// Gets light data for cluster assignment.
	public Span<LightData> Lights => mLights;

	/// Gets lighting parameters.
	public ref LightingParams Params => ref mParams;

	/// Gets GPU buffers.
	public IBuffer LightDataBuffer => mLightDataBuffer;
	public IBuffer LightingParamsBuffer => mLightingParamsBuffer;

	/// Gets light count.
	public int LightCount => mLights.Count;

	/// Gets statistics.
	public void GetStats(String outStats)
	{
		int directional = 0, point = 0, spot = 0;
		for (let light in mLights)
		{
			switch (light.Type)
			{
			case 0: directional++; // Directional
			case 1: point++;       // Point
			case 2: spot++;        // Spot
			default:
			}
		}
		outStats.AppendF("Lights: {} total ({} dir, {} point, {} spot)\n", mLights.Count, directional, point, spot);
	}

	public void Dispose()
	{
		// Buffers cleaned up by destructor
	}
}
