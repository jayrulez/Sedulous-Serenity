namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Configuration for cascaded shadow maps.
public struct CascadeConfig
{
	/// Number of cascades (1-4).
	public uint32 CascadeCount;

	/// Shadow map resolution per cascade.
	public uint32 Resolution;

	/// Cascade split ratios (logarithmic blend factor 0-1).
	public float SplitLambda;

	/// Shadow bias to prevent acne.
	public float Bias;

	/// Normal-based bias to reduce peter-panning.
	public float NormalBias;

	/// Softness for PCF filtering.
	public float Softness;

	/// Creates default configuration.
	public static Self Default => .()
	{
		CascadeCount = 4,
		Resolution = 2048,
		SplitLambda = 0.5f,
		Bias = 0.005f,
		NormalBias = 0.02f,
		Softness = 1.0f
	};
}

/// GPU uniform data for shadow rendering.
[CRepr]
public struct ShadowUniforms
{
	/// View-projection matrices for each cascade.
	public Matrix[4] CascadeViewProjection;

	/// Cascade split depths in view space.
	public Vector4 CascadeSplits;

	/// Shadow bias.
	public float ShadowBias;

	/// Shadow normal bias.
	public float ShadowNormalBias;

	/// Shadow softness (for PCF).
	public float ShadowSoftness;

	/// Padding.
	public float Padding;

	/// Size of this struct in bytes.
	public static int Size => 4 * 64 + 16 + 16; // 4 matrices + splits + params = 288
}

/// Per-cascade data.
public struct CascadeData
{
	/// View matrix for this cascade.
	public Matrix ViewMatrix;

	/// Projection matrix for this cascade.
	public Matrix ProjectionMatrix;

	/// Combined view-projection matrix.
	public Matrix ViewProjectionMatrix;

	/// World-space bounding sphere for the cascade.
	public BoundingSphere BoundingSphere;

	/// Near split distance in view space.
	public float NearSplit;

	/// Far split distance in view space.
	public float FarSplit;

	/// Texel size for stable shadow edges.
	public float TexelSize;
}

/// Manages cascaded shadow maps for directional lights.
public class CascadedShadowMaps : IDisposable
{
	// Configuration
	private CascadeConfig mConfig;

	// GPU resources
	private IDevice mDevice;
	private ITexture mShadowMapArray;
	private ITextureView mShadowMapArrayView;
	private ITextureView[4] mCascadeViews;
	private ISampler mShadowSampler;
	private IBuffer mShadowUniformBuffer;

	// Per-cascade data
	private CascadeData[4] mCascades;
	private float[4] mSplitDistances;

	// Current light
	private Vector3 mLightDirection;

	public ~this()
	{
		Dispose();
	}

	/// Gets the shadow map texture array.
	public ITexture ShadowMapArray => mShadowMapArray;

	/// Gets the shadow map array view (for sampling all cascades).
	public ITextureView ShadowMapArrayView => mShadowMapArrayView;

	/// Gets the shadow sampler (comparison sampler for PCF).
	public ISampler ShadowSampler => mShadowSampler;

	/// Gets the shadow uniform buffer.
	public IBuffer UniformBuffer => mShadowUniformBuffer;

	/// Gets a view for a specific cascade (for rendering).
	public ITextureView GetCascadeView(int cascade) => mCascadeViews[Math.Clamp(cascade, 0, 3)];

	/// Gets cascade data for a specific cascade.
	public CascadeData GetCascadeData(int cascade) => mCascades[Math.Clamp(cascade, 0, 3)];

	/// Gets the configuration.
	public CascadeConfig Config => mConfig;

	/// Whether the shadow maps are initialized.
	public bool IsInitialized => mDevice != null && mShadowMapArray != null;

	/// Initializes the cascaded shadow maps.
	public Result<void> Initialize(IDevice device, CascadeConfig config = .Default)
	{
		mDevice = device;
		mConfig = config;

		// Create shadow map array
		if (CreateShadowMapArray() case .Err)
			return .Err;

		// Create comparison sampler
		if (CreateShadowSampler() case .Err)
			return .Err;

		// Create uniform buffer
		if (CreateUniformBuffer() case .Err)
			return .Err;

		return .Ok;
	}

	/// Updates cascade matrices for the current frame.
	public void Update(CameraProxy* camera, Vector3 lightDirection)
	{
		if (!IsInitialized || camera == null)
			return;

		mLightDirection = Vector3.Normalize(lightDirection);

		// Calculate cascade splits
		CalculateSplitDistances(camera.NearPlane, camera.FarPlane);

		// Calculate matrices for each cascade
		for (int i = 0; i < mConfig.CascadeCount; i++)
		{
			CalculateCascadeMatrices(camera, i);
		}

		// Upload uniforms
		UploadUniforms();
	}

	/// Gets the view-projection matrix for rendering a cascade.
	public Matrix GetCascadeViewProjection(int cascade)
	{
		return mCascades[Math.Clamp(cascade, 0, 3)].ViewProjectionMatrix;
	}

	public void Dispose()
	{
		for (int i = 0; i < 4; i++)
		{
			if (mCascadeViews[i] != null)
			{
				delete mCascadeViews[i];
				mCascadeViews[i] = null;
			}
		}

		if (mShadowMapArrayView != null) { delete mShadowMapArrayView; mShadowMapArrayView = null; }
		if (mShadowMapArray != null) { delete mShadowMapArray; mShadowMapArray = null; }
		if (mShadowSampler != null) { delete mShadowSampler; mShadowSampler = null; }
		if (mShadowUniformBuffer != null) { delete mShadowUniformBuffer; mShadowUniformBuffer = null; }
	}

	private Result<void> CreateShadowMapArray()
	{
		// Create 2D array texture for cascades
		TextureDescriptor desc = .()
		{
			Label = "Cascaded Shadow Maps",
			Dimension = .Texture2D,
			Width = mConfig.Resolution,
			Height = mConfig.Resolution,
			Depth = 1,
			Format = .Depth32Float,
			MipLevelCount = 1,
			ArrayLayerCount = mConfig.CascadeCount,
			SampleCount = 1,
			Usage = .DepthStencil | .Sampled
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mShadowMapArray = tex;
		case .Err: return .Err;
		}

		// Create array view for sampling all cascades
		TextureViewDescriptor arrayViewDesc = .()
		{
			Label = "Shadow Map Array View",
			Format = .Depth32Float,
			Dimension = .Texture2DArray,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = mConfig.CascadeCount,
			Aspect = .DepthOnly
		};

		switch (mDevice.CreateTextureView(mShadowMapArray, &arrayViewDesc))
		{
		case .Ok(let view): mShadowMapArrayView = view;
		case .Err: return .Err;
		}

		// Create individual cascade views for rendering
		for (uint32 i = 0; i < mConfig.CascadeCount; i++)
		{
			TextureViewDescriptor cascadeViewDesc = .()
			{
				Label = "Shadow Cascade View",
				Format = .Depth32Float,
				Dimension = .Texture2D,
				BaseMipLevel = 0,
				MipLevelCount = 1,
				BaseArrayLayer = i,
				ArrayLayerCount = 1,
				Aspect = .DepthOnly
			};

			switch (mDevice.CreateTextureView(mShadowMapArray, &cascadeViewDesc))
			{
			case .Ok(let view): mCascadeViews[i] = view;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private Result<void> CreateShadowSampler()
	{
		SamplerDescriptor desc = .()
		{
			Label = "Shadow Comparison Sampler",
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			MagFilter = .Linear,
			MinFilter = .Linear,
			MipmapFilter = .Nearest,
			Compare = .LessEqual
		};

		switch (mDevice.CreateSampler(&desc))
		{
		case .Ok(let sampler): mShadowSampler = sampler;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateUniformBuffer()
	{
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		BufferDescriptor desc = .()
		{
			Label = "Shadow Uniforms",
			Size = (uint64)ShadowUniforms.Size,
			Usage = .Uniform,
			MemoryAccess = .Upload // CPU-mappable
		};

		switch (mDevice.CreateBuffer(&desc))
		{
		case .Ok(let buf): mShadowUniformBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private void CalculateSplitDistances(float nearPlane, float farPlane)
	{
		let lambda = mConfig.SplitLambda;
		let cascadeCount = mConfig.CascadeCount;

		for (uint32 i = 0; i < cascadeCount; i++)
		{
			let p = (float)(i + 1) / (float)cascadeCount;

			// Logarithmic split
			let logSplit = nearPlane * Math.Pow(farPlane / nearPlane, p);

			// Uniform split
			let uniformSplit = nearPlane + (farPlane - nearPlane) * p;

			// Blend between logarithmic and uniform
			mSplitDistances[i] = lambda * logSplit + (1.0f - lambda) * uniformSplit;
		}
	}

	private void CalculateCascadeMatrices(CameraProxy* camera, int cascadeIndex)
	{
		let nearSplit = cascadeIndex == 0 ? camera.NearPlane : mSplitDistances[cascadeIndex - 1];
		let farSplit = mSplitDistances[cascadeIndex];

		mCascades[cascadeIndex].NearSplit = nearSplit;
		mCascades[cascadeIndex].FarSplit = farSplit;

		// Calculate frustum corners for this cascade
		Vector3[8] frustumCorners = .();
		CalculateFrustumCorners(camera, nearSplit, farSplit, ref frustumCorners);

		// Calculate frustum center
		Vector3 frustumCenter = .Zero;
		for (let corner in frustumCorners)
			frustumCenter += corner;
		frustumCenter /= 8.0f;

		// Calculate bounding sphere radius
		float radius = 0;
		for (let corner in frustumCorners)
		{
			let dist = Vector3.Distance(corner, frustumCenter);
			radius = Math.Max(radius, dist);
		}

		// Round up to reduce shadow edge swimming
		radius = Math.Ceiling(radius * 16.0f) / 16.0f;

		mCascades[cascadeIndex].BoundingSphere = BoundingSphere(frustumCenter, radius);

		// Calculate texel size for stable shadows
		mCascades[cascadeIndex].TexelSize = (radius * 2.0f) / (float)mConfig.Resolution;

		// Calculate light view matrix
		let lightPos = frustumCenter - mLightDirection * radius;
		let viewMatrix = Matrix.CreateLookAt(lightPos, frustumCenter, .(0, 1, 0));

		// Calculate orthographic projection
		let projMatrix = Matrix.CreateOrthographic(radius * 2.0f, radius * 2.0f, 0.0f, radius * 2.0f);

		// Snap to texel grid to prevent shadow edge swimming
		var viewProj = viewMatrix * projMatrix;
		viewProj = SnapToTexelGrid(viewProj, mConfig.Resolution);

		mCascades[cascadeIndex].ViewMatrix = viewMatrix;
		mCascades[cascadeIndex].ProjectionMatrix = projMatrix;
		mCascades[cascadeIndex].ViewProjectionMatrix = viewProj;
	}

	private void CalculateFrustumCorners(CameraProxy* camera, float nearDist, float farDist, ref Vector3[8] corners)
	{
		let tanHalfFov = Math.Tan(camera.FieldOfView * 0.5f);
		let aspectRatio = camera.AspectRatio;

		let nearHeight = tanHalfFov * nearDist;
		let nearWidth = nearHeight * aspectRatio;
		let farHeight = tanHalfFov * farDist;
		let farWidth = farHeight * aspectRatio;

		let pos = camera.Position;
		let forward = camera.Forward;
		let right = camera.Right;
		let up = camera.Up;

		let nearCenter = pos + forward * nearDist;
		let farCenter = pos + forward * farDist;

		// Near plane corners
		corners[0] = nearCenter - right * nearWidth - up * nearHeight; // Bottom-left
		corners[1] = nearCenter + right * nearWidth - up * nearHeight; // Bottom-right
		corners[2] = nearCenter + right * nearWidth + up * nearHeight; // Top-right
		corners[3] = nearCenter - right * nearWidth + up * nearHeight; // Top-left

		// Far plane corners
		corners[4] = farCenter - right * farWidth - up * farHeight; // Bottom-left
		corners[5] = farCenter + right * farWidth - up * farHeight; // Bottom-right
		corners[6] = farCenter + right * farWidth + up * farHeight; // Top-right
		corners[7] = farCenter - right * farWidth + up * farHeight; // Top-left
	}

	private Matrix SnapToTexelGrid(Matrix viewProj, uint32 resolution)
	{
		// Transform origin to shadow map space
		var shadowOrigin = Vector4.Transform(Vector4(0, 0, 0, 1), viewProj);
		shadowOrigin *= (float)resolution / 2.0f;

		// Round to nearest texel
		let roundedOrigin = Vector4(
			Math.Round(shadowOrigin.X),
			Math.Round(shadowOrigin.Y),
			shadowOrigin.Z,
			shadowOrigin.W
		);

		// Calculate offset
		var offset = roundedOrigin - shadowOrigin;
		offset *= 2.0f / (float)resolution;

		// Apply offset to projection
		var result = viewProj;
		result.M41 += offset.X;
		result.M42 += offset.Y;

		return result;
	}

	private void UploadUniforms()
	{
		ShadowUniforms uniforms = .();

		for (int i = 0; i < 4; i++)
		{
			if (i < mConfig.CascadeCount)
				uniforms.CascadeViewProjection[i] = mCascades[i].ViewProjectionMatrix;
			else
				uniforms.CascadeViewProjection[i] = .Identity;
		}

		uniforms.CascadeSplits = Vector4(
			mSplitDistances[0],
			mSplitDistances[1],
			mSplitDistances[2],
			mSplitDistances[3]
		);

		uniforms.ShadowBias = mConfig.Bias;
		uniforms.ShadowNormalBias = mConfig.NormalBias;
		uniforms.ShadowSoftness = mConfig.Softness;

		// Use Map/Unmap to avoid command buffer creation
		if (let ptr = mShadowUniformBuffer.Map())
		{
			// Bounds check against actual buffer size
			Runtime.Assert(ShadowUniforms.Size <= (.)mShadowUniformBuffer.Size, scope $"ShadowUniforms copy size ({ShadowUniforms.Size}) exceeds buffer size ({mShadowUniformBuffer.Size})");
			Internal.MemCpy(ptr, &uniforms, ShadowUniforms.Size);
			mShadowUniformBuffer.Unmap();
		}
	}
}
