namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Post-processing settings for a view.
public struct PostProcessSettings
{
	/// Enable TAA (Temporal Anti-Aliasing).
	public bool EnableTAA = true;

	/// Enable bloom effect.
	public bool EnableBloom = true;

	/// Bloom intensity (0-1).
	public float BloomIntensity = 0.5f;

	/// Bloom threshold (HDR brightness to start blooming).
	public float BloomThreshold = 1.0f;

	/// Enable auto-exposure.
	public bool EnableAutoExposure = true;

	/// Manual exposure value (when auto-exposure disabled).
	public float ManualExposure = 1.0f;

	/// Exposure compensation (EV stops).
	public float ExposureCompensation = 0.0f;

	/// Enable ambient occlusion.
	public bool EnableSSAO = true;

	/// SSAO intensity.
	public float SSAOIntensity = 1.0f;

	/// Enable screen-space reflections.
	public bool EnableSSR = false;

	/// Enable volumetric fog.
	public bool EnableVolumetricFog = false;

	/// Enable FXAA (used when TAA is disabled).
	public bool EnableFXAA = true;

	/// Default settings.
	public static Self Default => .();
}

/// TAA jitter state for sub-pixel sampling.
public struct TAAJitterState
{
	/// Current jitter offset in pixels.
	public Vector2 JitterOffset;

	/// Jitter offset in UV space (-0.5 to 0.5 pixel).
	public Vector2 JitterUV;

	/// Current sample index in the jitter sequence.
	public int32 SampleIndex;

	/// Halton sequence for jitter pattern.
	private const int32 HaltonSequenceLength = 16;

	/// Advances to the next jitter sample.
	public void Advance(uint32 screenWidth, uint32 screenHeight) mut
	{
		SampleIndex = (SampleIndex + 1) % HaltonSequenceLength;

		// Halton(2,3) sequence for low-discrepancy sampling
		float x = Halton(SampleIndex + 1, 2);
		float y = Halton(SampleIndex + 1, 3);

		// Center around 0 (-0.5 to 0.5)
		x -= 0.5f;
		y -= 0.5f;

		JitterOffset = .(x, y);
		JitterUV = .(x / (float)screenWidth, y / (float)screenHeight);
	}

	/// Halton sequence generator.
	private static float Halton(int32 index, int32 base_)
	{
		float result = 0;
		float f = 1.0f / base_;
		int32 i = index;

		while (i > 0)
		{
			result += f * (i % base_);
			i /= base_;
			f /= base_;
		}

		return result;
	}

	/// Resets the jitter state.
	public void Reset() mut
	{
		SampleIndex = 0;
		JitterOffset = .Zero;
		JitterUV = .Zero;
	}
}

/// Represents a viewport/camera for rendering.
/// Contains camera parameters, render targets, and post-processing settings.
public class RenderView
{
	/// View name for debugging.
	public String Name = new .("MainView") ~ delete _;

	/// Render target width.
	public uint32 Width;

	/// Render target height.
	public uint32 Height;

	/// Camera position in world space.
	public Vector3 CameraPosition;

	/// Camera forward direction.
	public Vector3 CameraForward = .(0, 0, -1);

	/// Camera up direction.
	public Vector3 CameraUp = .(0, 1, 0);

	/// Field of view in radians.
	public float FieldOfView = Math.PI_f / 4.0f; // 45 degrees

	/// Near clipping plane.
	public float NearPlane = 0.1f;

	/// Far clipping plane.
	public float FarPlane = 1000.0f;

	/// Aspect ratio (width / height).
	public float AspectRatio => (float)Width / (float)Height;

	/// View matrix (computed).
	public Matrix ViewMatrix;

	/// Projection matrix (computed).
	public Matrix ProjectionMatrix;

	/// View-projection matrix (computed).
	public Matrix ViewProjectionMatrix;

	/// Frustum planes for culling (computed).
	public Plane[6] FrustumPlanes;

	/// TAA jitter state.
	public TAAJitterState TAAJitter;

	/// Post-processing settings.
	public PostProcessSettings PostProcess = .Default;

	/// Final output texture (swap chain backbuffer or offscreen target).
	public ITextureView OutputTarget;

	/// Whether this view renders to the swap chain.
	public bool IsSwapChainTarget = true;

	/// Updates computed matrices from camera parameters.
	public void UpdateMatrices(bool flipProjection = false)
	{
		let target = CameraPosition + CameraForward;
		ViewMatrix = Matrix.CreateLookAt(CameraPosition, target, CameraUp);

		ProjectionMatrix = Matrix.CreatePerspectiveFieldOfView(
			FieldOfView, AspectRatio, NearPlane, FarPlane);

		if (flipProjection)
			ProjectionMatrix.M22 = -ProjectionMatrix.M22;

		// Apply TAA jitter to projection
		if (PostProcess.EnableTAA)
		{
			var jitteredProj = ProjectionMatrix;
			jitteredProj.M31 += TAAJitter.JitterUV.X * 2.0f;
			jitteredProj.M32 += TAAJitter.JitterUV.Y * 2.0f;
			ViewProjectionMatrix = ViewMatrix * jitteredProj;
		}
		else
		{
			ViewProjectionMatrix = ViewMatrix * ProjectionMatrix;
		}

		ExtractFrustumPlanes();
	}

	/// Extracts frustum planes from the view-projection matrix.
	private void ExtractFrustumPlanes()
	{
		let m = ViewProjectionMatrix;

		// Left plane
		FrustumPlanes[0] = Plane(
			m.M14 + m.M11,
			m.M24 + m.M21,
			m.M34 + m.M31,
			m.M44 + m.M41
		);

		// Right plane
		FrustumPlanes[1] = Plane(
			m.M14 - m.M11,
			m.M24 - m.M21,
			m.M34 - m.M31,
			m.M44 - m.M41
		);

		// Bottom plane
		FrustumPlanes[2] = Plane(
			m.M14 + m.M12,
			m.M24 + m.M22,
			m.M34 + m.M32,
			m.M44 + m.M42
		);

		// Top plane
		FrustumPlanes[3] = Plane(
			m.M14 - m.M12,
			m.M24 - m.M22,
			m.M34 - m.M32,
			m.M44 - m.M42
		);

		// Near plane
		FrustumPlanes[4] = Plane(
			m.M13,
			m.M23,
			m.M33,
			m.M43
		);

		// Far plane
		FrustumPlanes[5] = Plane(
			m.M14 - m.M13,
			m.M24 - m.M23,
			m.M34 - m.M33,
			m.M44 - m.M43
		);

		// Normalize planes
		for (int i = 0; i < 6; i++)
		{
			FrustumPlanes[i] = Plane.Normalize(FrustumPlanes[i]);
		}
	}

	/// Advances the TAA jitter for the next frame.
	public void AdvanceTAAJitter()
	{
		if (PostProcess.EnableTAA)
			TAAJitter.Advance(Width, Height);
	}

	/// Tests if a bounding box is visible in the frustum.
	public bool IsVisible(BoundingBox bounds)
	{
		for (let plane in FrustumPlanes)
		{
			// Get the corner that's most in the direction of the plane normal
			Vector3 positiveVertex = .(
				plane.Normal.X >= 0 ? bounds.Max.X : bounds.Min.X,
				plane.Normal.Y >= 0 ? bounds.Max.Y : bounds.Min.Y,
				plane.Normal.Z >= 0 ? bounds.Max.Z : bounds.Min.Z
			);

			// If positive vertex is behind plane, box is outside frustum
			if (Vector3.Dot(plane.Normal, positiveVertex) + plane.D < 0)
				return false;
		}

		return true;
	}

	/// Tests if a bounding sphere is visible in the frustum.
	public bool IsVisible(BoundingSphere sphere)
	{
		for (let plane in FrustumPlanes)
		{
			let distance = Vector3.Dot(plane.Normal, sphere.Center) + plane.D;
			if (distance < -sphere.Radius)
				return false;
		}

		return true;
	}
}
