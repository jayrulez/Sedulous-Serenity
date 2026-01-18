namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// GPU-packed light data structure.
/// Matches the HLSL Light struct for direct upload.
[CRepr]
public struct GPULight
{
	/// Light position in world space.
	public Vector3 Position;
	/// Light range (for point/spot lights).
	public float Range;

	/// Light direction (normalized, for directional/spot).
	public Vector3 Direction;
	/// Spot light outer cone angle (cosine).
	public float SpotAngleCos;

	/// Light color (RGB).
	public Vector3 Color;
	/// Light intensity multiplier.
	public float Intensity;

	/// Light type: 0=Directional, 1=Point, 2=Spot, 3=Area.
	public uint32 Type;
	/// Shadow map index (-1 if no shadows).
	public int32 ShadowIndex;
	/// Padding for alignment.
	public float Padding0;
	public float Padding1;

	/// Size of this struct in bytes (must be 64 for alignment).
	public static int Size => 64;

	/// Creates a GPU light from a light proxy.
	public static Self FromProxy(LightProxy* proxy)
	{
		return .()
		{
			Position = proxy.Position,
			Range = proxy.Range,
			Direction = proxy.Direction,
			SpotAngleCos = Math.Cos(proxy.OuterConeAngle),
			Color = proxy.Color,
			Intensity = proxy.Intensity,
			Type = (uint32)proxy.Type,
			ShadowIndex = proxy.ShadowIndex
		};
	}
}

/// GPU uniform buffer for lighting parameters.
/// Layout MUST match forward.frag.hlsl LightingUniforms cbuffer.
[CRepr]
public struct LightingUniforms
{
	/// Ambient light color (rgb).
	public Vector3 AmbientColor;
	/// Ambient light intensity multiplier.
	public float AmbientIntensity;

	/// Number of active lights.
	public uint32 LightCount;
	/// Cluster grid dimensions (x, y, z).
	public uint32 ClusterDimensionX;
	public uint32 ClusterDimensionY;
	public uint32 ClusterDimensionZ;

	/// Cluster scale for index calculation.
	public Vector2 ClusterScale;
	/// Cluster bias for index calculation.
	public Vector2 ClusterBias;

	/// Size of this struct in bytes.
	public static int Size => 48;
}

/// Manages GPU light data for clustered forward rendering.
public class LightBuffer : IDisposable
{
	// Configuration
	private const int MAX_LIGHTS = 1024;

	// GPU resources
	private IDevice mDevice;
	private IBuffer mLightDataBuffer;     // Array of GPULight structs
	private IBuffer mLightingUniformBuffer; // LightingUniforms

	// CPU-side light data for upload
	private GPULight[] mLights ~ delete _;
	private int32 mLightCount = 0;

	// Lighting settings
	private Vector3 mAmbientColor = .(0.03f, 0.03f, 0.03f);
	private float mAmbientIntensity = 1.0f;
	private float mEnvironmentIntensity = 1.0f;
	private float mExposure = 1.0f;

	// Cluster info (set by ClusterGrid)
	private uint32 mClusterDimX = 16;
	private uint32 mClusterDimY = 9;
	private uint32 mClusterDimZ = 24;
	private Vector2 mClusterScale = .(1.0f, 1.0f);
	private Vector2 mClusterBias = .(0.0f, 0.0f);

	/// Gets the number of active lights.
	public int32 LightCount => mLightCount;

	/// Gets the maximum number of supported lights.
	public int32 MaxLights => MAX_LIGHTS;

	/// Gets or sets the ambient light color.
	public Vector3 AmbientColor
	{
		get => mAmbientColor;
		set => mAmbientColor = value;
	}

	/// Gets or sets the ambient light intensity.
	public float AmbientIntensity
	{
		get => mAmbientIntensity;
		set => mAmbientIntensity = value;
	}

	/// Sets cluster grid info for the lighting uniform buffer.
	public void SetClusterInfo(uint32 dimX, uint32 dimY, uint32 dimZ, Vector2 scale, Vector2 bias)
	{
		mClusterDimX = dimX;
		mClusterDimY = dimY;
		mClusterDimZ = dimZ;
		mClusterScale = scale;
		mClusterBias = bias;
	}

	/// Gets or sets the environment map intensity.
	public float EnvironmentIntensity
	{
		get => mEnvironmentIntensity;
		set => mEnvironmentIntensity = value;
	}

	/// Gets or sets the exposure value.
	public float Exposure
	{
		get => mExposure;
		set => mExposure = value;
	}

	/// Gets the light data buffer for binding.
	public IBuffer LightDataBuffer => mLightDataBuffer;

	/// Gets the lighting uniform buffer for binding.
	public IBuffer UniformBuffer => mLightingUniformBuffer;

	/// Whether the buffer has been initialized.
	public bool IsInitialized => mDevice != null && mLightDataBuffer != null;

	/// Initializes the light buffer.
	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create light data buffer (structured buffer)
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		BufferDescriptor lightDesc = .()
		{
			Label = "Light Data",
			Size = (uint64)(MAX_LIGHTS * GPULight.Size),
			Usage = .Storage,
			MemoryAccess = .Upload // CPU-mappable
		};

		switch (mDevice.CreateBuffer(&lightDesc))
		{
		case .Ok(let buf): mLightDataBuffer = buf;
		case .Err: return .Err;
		}

		// Create lighting uniform buffer
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		BufferDescriptor uniformDesc = .()
		{
			Label = "Lighting Uniforms",
			Size = (uint64)LightingUniforms.Size,
			Usage = .Uniform,
			MemoryAccess = .Upload // CPU-mappable
		};

		switch (mDevice.CreateBuffer(&uniformDesc))
		{
		case .Ok(let buf): mLightingUniformBuffer = buf;
		case .Err: return .Err;
		}

		// Allocate CPU-side light array
		mLights = new GPULight[MAX_LIGHTS];

		return .Ok;
	}

	/// Updates the light buffer from visible lights.
	public void Update(RenderWorld world, VisibilityResolver visibility)
	{
		mLightCount = 0;

		// Copy visible lights to CPU buffer
		for (let visibleLight in visibility.VisibleLights)
		{
			if (mLightCount >= MAX_LIGHTS)
				break;

			if (let proxy = world.GetLight(visibleLight.Handle))
			{
				mLights[mLightCount] = GPULight.FromProxy(proxy);
				mLightCount++;
			}
		}

		// Upload to GPU
		UploadLightData();
		UploadUniforms();
	}

	/// Updates the light buffer from a render world (all active lights).
	public void UpdateFromWorld(RenderWorld world)
	{
		mLightCount = 0;

		world.ForEachLight(scope [&](handle, proxy) =>
		{
			if (mLightCount >= MAX_LIGHTS)
				return;

			if (!proxy.IsActive || !proxy.IsEnabled)
				return;

			mLights[mLightCount] = GPULight.FromProxy(&proxy);
			mLightCount++;
		});

		// Upload to GPU
		UploadLightData();
		UploadUniforms();
	}

	/// Manually sets a light at the given index.
	public void SetLight(int32 index, GPULight light)
	{
		if (index >= 0 && index < MAX_LIGHTS)
		{
			mLights[index] = light;
			if (index >= mLightCount)
				mLightCount = index + 1;
		}
	}

	/// Clears all lights.
	public void Clear()
	{
		mLightCount = 0;
	}

	/// Uploads current light data to GPU.
	public void UploadLightData()
	{
		if (!IsInitialized || mLightCount == 0)
			return;

		// Use Map/Unmap to avoid command buffer creation
		if (let ptr = mLightDataBuffer.Map())
		{
			let uploadSize = mLightCount * GPULight.Size;
			Internal.MemCpy(ptr, &mLights[0], uploadSize);
			mLightDataBuffer.Unmap();
		}
	}

	/// Uploads lighting uniforms to GPU.
	public void UploadUniforms()
	{
		if (!IsInitialized)
			return;

		LightingUniforms uniforms = .()
		{
			AmbientColor = mAmbientColor,
			AmbientIntensity = mAmbientIntensity,
			LightCount = (uint32)mLightCount,
			ClusterDimensionX = mClusterDimX,
			ClusterDimensionY = mClusterDimY,
			ClusterDimensionZ = mClusterDimZ,
			ClusterScale = mClusterScale,
			ClusterBias = mClusterBias
		};

		// Use Map/Unmap to avoid command buffer creation
		if (let ptr = mLightingUniformBuffer.Map())
		{
			Internal.MemCpy(ptr, &uniforms, LightingUniforms.Size);
			mLightingUniformBuffer.Unmap();
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mLightDataBuffer != null) { delete mLightDataBuffer; mLightDataBuffer = null; }
		if (mLightingUniformBuffer != null) { delete mLightingUniformBuffer; mLightingUniformBuffer = null; }
	}
}
