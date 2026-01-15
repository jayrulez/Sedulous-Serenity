namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Per-cascade data for GPU.
[CRepr]
struct CascadeData
{
	public Matrix ViewProjection;  // Light's view-projection matrix
	public Vector4 SplitDepth;     // x=near, y=far, z=1/width, w=1/height
	public Vector4 Offset;         // xy=offset in atlas, zw=scale

	public const uint32 Size = 96; // 64 + 16 + 16
}

/// GPU uniform buffer for all cascades.
[CRepr]
struct CascadeShadowData
{
	public CascadeData[4] Cascades;
	public Vector4 ShadowParams;   // x=bias, y=normalBias, z=softness, w=cascadeCount
	public Vector4 LightDirection; // xyz=direction, w=unused

	public const uint32 Size = CascadeData.Size * 4 + 32; // 416 bytes
}

/// Manages cascaded shadow maps for directional lights.
/// Uses 4 cascades with practical split scheme (PSSM).
class CascadedShadowMaps : IDisposable
{
	private IDevice mDevice;

	// Configuration
	public readonly uint32 CascadeCount;
	public readonly uint32 ShadowMapSize;

	// Cascade data
	private CascadeData[4] mCascades;
	private float[5] mSplitDistances; // Near + 4 cascade boundaries
	private Matrix[4] mLightViewProjections;

	// Shadow map texture (array of 4 cascades)
	private ITexture mShadowMapArray ~ delete _;
	private ITextureView[4] mCascadeViews ~ { for (var v in _) delete v; };
	private ITextureView mArrayView ~ delete _;

	// GPU uniform buffer
	private IBuffer mCascadeBuffer ~ delete _;
	private CascadeShadowData mGpuData;

	// Shadow parameters
	public float ShadowBias = 0.001f;
	public float ShadowNormalBias = 0.02f;
	public float ShadowSoftness = 1.0f;
	public float SplitLambda = 0.75f; // Blend between logarithmic and uniform splits

	/// Creates cascaded shadow maps.
	public this(uint32 cascadeCount = 4, uint32 shadowMapSize = 2048)
	{
		CascadeCount = Math.Min(cascadeCount, 4);
		ShadowMapSize = shadowMapSize;
	}

	/// Initializes shadow map resources.
	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create shadow map texture array
		var texDesc = TextureDescriptor();
		texDesc.Width = ShadowMapSize;
		texDesc.Height = ShadowMapSize;
		texDesc.ArrayLayerCount = CascadeCount;
		texDesc.MipLevelCount = 1;
		texDesc.Format = .Depth32Float;
		texDesc.Usage = .DepthStencil | .Sampled;
		texDesc.Dimension = .Texture2D; // Array is specified by ArrayLayerCount > 1
		texDesc.Label = "CascadeShadowMaps";

		switch (device.CreateTexture(&texDesc))
		{
		case .Ok(let texture):
			mShadowMapArray = texture;
		case .Err:
			return .Err;
		}

		// Create per-cascade views for rendering
		for (uint32 i = 0; i < CascadeCount; i++)
		{
			var viewDesc = TextureViewDescriptor();
			viewDesc.Format = .Depth32Float;
			viewDesc.Dimension = .Texture2D;
			viewDesc.BaseArrayLayer = i;
			viewDesc.ArrayLayerCount = 1;
			viewDesc.BaseMipLevel = 0;
			viewDesc.MipLevelCount = 1;
			viewDesc.Aspect = .DepthOnly;

			switch (device.CreateTextureView(mShadowMapArray, &viewDesc))
			{
			case .Ok(let view):
				mCascadeViews[i] = view;
			case .Err:
				return .Err;
			}
		}

		// Create array view for shader sampling
		var arrayViewDesc = TextureViewDescriptor();
		arrayViewDesc.Format = .Depth32Float;
		arrayViewDesc.Dimension = .Texture2DArray;
		arrayViewDesc.BaseArrayLayer = 0;
		arrayViewDesc.ArrayLayerCount = CascadeCount;
		arrayViewDesc.BaseMipLevel = 0;
		arrayViewDesc.MipLevelCount = 1;
		arrayViewDesc.Aspect = .DepthOnly;

		switch (device.CreateTextureView(mShadowMapArray, &arrayViewDesc))
		{
		case .Ok(let view):
			mArrayView = view;
		case .Err:
			return .Err;
		}

		// Create cascade uniform buffer
		var bufDesc = BufferDescriptor(CascadeShadowData.Size, .Uniform, .Upload);
		bufDesc.Label = "CascadeDataBuffer";

		switch (device.CreateBuffer(&bufDesc))
		{
		case .Ok(let buffer):
			mCascadeBuffer = buffer;
		case .Err:
			return .Err;
		}

		return .Ok;
	}

	/// Updates cascade matrices for the given camera and light direction.
	public void Update(Matrix cameraView, Matrix cameraProj, float nearPlane, float farPlane, Vector3 lightDirection)
	{
		// Compute cascade split distances using practical split scheme
		ComputeSplitDistances(nearPlane, farPlane);

		// Get camera inverse view for frustum corners
		Matrix.Invert(cameraView, var invCameraView);
		Matrix.Invert(cameraProj, var invCameraProj);

		// Normalize light direction
		Vector3 lightDir = Vector3.Normalize(lightDirection);

		// Compute view-projection for each cascade
		for (uint32 i = 0; i < CascadeCount; i++)
		{
			float cascadeNear = mSplitDistances[i];
			float cascadeFar = mSplitDistances[i + 1];

			// Get frustum corners for this cascade
			Vector3[8] frustumCorners = GetFrustumCorners(invCameraView, invCameraProj, cascadeNear, cascadeFar, nearPlane, farPlane);

			// Compute frustum center
			Vector3 center = .Zero;
			for (let corner in frustumCorners)
				center += corner;
			center /= 8.0f;

			// Compute light view matrix looking at frustum center
			Matrix lightView = Matrix.CreateLookAt(center - lightDir * 100.0f, center, .UnitY);

			// Transform frustum corners to light space
			Vector3 minBounds = .(float.MaxValue);
			Vector3 maxBounds = .(float.MinValue);

			for (let corner in frustumCorners)
			{
				Vector4 lightSpaceCorner = Vector4.Transform(Vector4(corner, 1.0f), lightView);
				Vector3 ls = .(lightSpaceCorner.X, lightSpaceCorner.Y, lightSpaceCorner.Z);
				minBounds = Vector3.Min(minBounds, ls);
				maxBounds = Vector3.Max(maxBounds, ls);
			}

			// Add some padding to avoid edge artifacts
			float padding = (maxBounds.X - minBounds.X) * 0.1f;
			minBounds.X -= padding;
			minBounds.Y -= padding;
			maxBounds.X += padding;
			maxBounds.Y += padding;

			// Extend Z range for shadow casters behind the frustum
			minBounds.Z -= 200.0f;
			maxBounds.Z += 50.0f;

			// Create orthographic projection for this cascade
			Matrix lightProj = Matrix.CreateOrthographicOffCenter(
				minBounds.X, maxBounds.X,
				minBounds.Y, maxBounds.Y,
				minBounds.Z, maxBounds.Z
			);

			mLightViewProjections[i] = lightView * lightProj;

			// Store cascade data
			mCascades[i].ViewProjection = mLightViewProjections[i];
			mCascades[i].SplitDepth = .(cascadeNear, cascadeFar, 1.0f / ShadowMapSize, 1.0f / ShadowMapSize);
			mCascades[i].Offset = .(0, 0, 1, 1); // Full texture, no atlas offset
		}

		// Update GPU data
		mGpuData.Cascades = mCascades;
		mGpuData.ShadowParams = .(ShadowBias, ShadowNormalBias, ShadowSoftness, (float)CascadeCount);
		mGpuData.LightDirection = .(lightDir.X, lightDir.Y, lightDir.Z, 0);

		UploadCascadeData();
	}

	/// Computes split distances using practical split scheme (PSSM).
	private void ComputeSplitDistances(float nearPlane, float farPlane)
	{
		mSplitDistances[0] = nearPlane;

		for (uint32 i = 1; i <= CascadeCount; i++)
		{
			float p = (float)i / CascadeCount;

			// Logarithmic split
			float logSplit = nearPlane * Math.Pow(farPlane / nearPlane, p);

			// Uniform split
			float uniformSplit = nearPlane + (farPlane - nearPlane) * p;

			// Blend between log and uniform using lambda
			mSplitDistances[i] = SplitLambda * logSplit + (1.0f - SplitLambda) * uniformSplit;
		}
	}

	/// Gets the 8 corners of a frustum slice.
	private Vector3[8] GetFrustumCorners(Matrix invView, Matrix invProj, float nearDist, float farDist, float camNear, float camFar)
	{
		Vector3[8] corners = .();

		// NDC corners
		Vector3[4] ndcCorners = .(
			.(-1, -1, 0), // Near bottom-left
			.( 1, -1, 0), // Near bottom-right
			.(-1,  1, 0), // Near top-left
			.( 1,  1, 0)  // Near top-right
		);

		// NDC Z values
		float nearZ = 0.0f; // NDC near is 0
		float farZ = 1.0f;  // NDC far is 1

		for (int i = 0; i < 4; i++)
		{
			// Near plane corners
			Vector4 nearNDC = .(ndcCorners[i].X, ndcCorners[i].Y, nearZ, 1.0f);
			Vector4 nearView = Vector4.Transform(nearNDC, invProj);
			nearView /= nearView.W;

			// Scale to cascade near distance
			float nearScale = nearDist / (-nearView.Z);
			Vector3 nearWorld = Vector3.Transform(.(nearView.X * nearScale, nearView.Y * nearScale, -nearDist), invView);
			corners[i] = nearWorld;

			// Far plane corners
			Vector4 farNDC = .(ndcCorners[i].X, ndcCorners[i].Y, farZ, 1.0f);
			Vector4 farView = Vector4.Transform(farNDC, invProj);
			farView /= farView.W;

			// Scale to cascade far distance
			float farScale = farDist / (-farView.Z);
			Vector3 farWorld = Vector3.Transform(.(farView.X * farScale, farView.Y * farScale, -farDist), invView);
			corners[i + 4] = farWorld;
		}

		return corners;
	}

	/// Uploads cascade data to GPU.
	private void UploadCascadeData()
	{
		if (mCascadeBuffer == null)
			return;

		let ptr = mCascadeBuffer.Map();
		if (ptr != null)
		{
			*(CascadeShadowData*)ptr = mGpuData;
			mCascadeBuffer.Unmap();
		}
	}

	/// Gets the view-projection matrix for a cascade.
	public Matrix GetCascadeViewProjection(uint32 cascade)
	{
		if (cascade >= CascadeCount)
			return .Identity;
		return mLightViewProjections[cascade];
	}

	/// Gets the split distance for a cascade boundary.
	public float GetSplitDistance(uint32 index)
	{
		if (index > CascadeCount)
			return 0;
		return mSplitDistances[index];
	}

	/// Gets the cascade index for a given view-space depth.
	public uint32 GetCascadeIndex(float viewDepth)
	{
		for (uint32 i = 0; i < CascadeCount; i++)
		{
			if (viewDepth < mSplitDistances[i + 1])
				return i;
		}
		return CascadeCount - 1;
	}

	/// Gets the shadow map texture array.
	public ITexture ShadowMapArray => mShadowMapArray;

	/// Gets a per-cascade view for rendering.
	public ITextureView GetCascadeView(uint32 cascade) => cascade < CascadeCount ? mCascadeViews[cascade] : null;

	/// Gets the array view for shader sampling.
	public ITextureView ArrayView => mArrayView;

	/// Gets the cascade uniform buffer.
	public IBuffer CascadeBuffer => mCascadeBuffer;

	/// Gets statistics.
	public void GetStats(String outStats)
	{
		outStats.AppendF("Cascaded Shadow Maps:\n");
		outStats.AppendF("  Cascades: {}\n", CascadeCount);
		outStats.AppendF("  Resolution: {}x{}\n", ShadowMapSize, ShadowMapSize);
		outStats.AppendF("  Splits: ");
		for (uint32 i = 0; i <= CascadeCount; i++)
		{
			outStats.AppendF("{:.1f}", mSplitDistances[i]);
			if (i < CascadeCount) outStats.Append(", ");
		}
		outStats.Append("\n");
	}

	public void Dispose()
	{
		// Resources cleaned up by destructor
	}
}
