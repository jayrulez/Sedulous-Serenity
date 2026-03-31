namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

/// Post-processing settings for a view.
public struct PostProcessSettings
{
	public bool EnableTAA = true;
	public bool EnableBloom = true;
	public float BloomIntensity = 0.5f;
	public float BloomThreshold = 1.0f;
	public bool EnableAutoExposure = true;
	public float ManualExposure = 1.0f;
	public float ExposureCompensation = 0.0f;
	public bool EnableSSAO = true;
	public float SSAOIntensity = 1.0f;
	public bool EnableSSR = false;
	public bool EnableVolumetricFog = false;
	public bool EnableFXAA = true;

	public static Self Default => .();
}

/// TAA jitter state for sub-pixel sampling.
public struct TAAJitterState
{
	public Vector2 JitterOffset;
	public Vector2 JitterUV;
	public int32 SampleIndex;

	private const int32 HaltonSequenceLength = 16;

	public void Advance(uint32 screenWidth, uint32 screenHeight) mut
	{
		SampleIndex = (SampleIndex + 1) % HaltonSequenceLength;
		float x = Halton(SampleIndex + 1, 2);
		float y = Halton(SampleIndex + 1, 3);
		x -= 0.5f;
		y -= 0.5f;
		JitterOffset = .(x, y);
		JitterUV = .(x / (float)screenWidth, y / (float)screenHeight);
	}

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

	public void Reset() mut
	{
		SampleIndex = 0;
		JitterOffset = .Zero;
		JitterUV = .Zero;
	}
}

/// Represents a viewport/camera for rendering.
public class RenderView
{
	public String Name = new .("MainView") ~ delete _;
	public uint32 Width;
	public uint32 Height;
	public Vector3 CameraPosition;
	public Vector3 CameraForward = .(0, 0, -1);
	public Vector3 CameraUp = .(0, 1, 0);
	public float FieldOfView = Math.PI_f / 4.0f;
	public float NearPlane = 0.1f;
	public float FarPlane = 1000.0f;
	public float AspectRatio => Height > 0 ? (float)Width / (float)Height : 1.0f;
	public Matrix ViewMatrix = .Identity;
	public Matrix ProjectionMatrix = .Identity;
	public Matrix ViewProjectionMatrix = .Identity;
	public Plane[6] FrustumPlanes;
	public TAAJitterState TAAJitter;
	public PostProcessSettings PostProcess = .Default;
	public ITextureView OutputTarget;
	public bool IsSwapChainTarget = true;
	public uint32 ViewportX = 0;
	public uint32 ViewportY = 0;
	public int32 ViewIndex = 0;

	public void UpdateMatrices()
	{
		let target = CameraPosition + CameraForward;
		ViewMatrix = Matrix.CreateLookAt(CameraPosition, target, CameraUp);
		ProjectionMatrix = Matrix.CreatePerspectiveFieldOfView(FieldOfView, AspectRatio, NearPlane, FarPlane);

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

	private void ExtractFrustumPlanes()
	{
		let m = ViewProjectionMatrix;
		FrustumPlanes[0] = Plane.Normalize(Plane(m.M14 + m.M11, m.M24 + m.M21, m.M34 + m.M31, m.M44 + m.M41));
		FrustumPlanes[1] = Plane.Normalize(Plane(m.M14 - m.M11, m.M24 - m.M21, m.M34 - m.M31, m.M44 - m.M41));
		FrustumPlanes[2] = Plane.Normalize(Plane(m.M14 + m.M12, m.M24 + m.M22, m.M34 + m.M32, m.M44 + m.M42));
		FrustumPlanes[3] = Plane.Normalize(Plane(m.M14 - m.M12, m.M24 - m.M22, m.M34 - m.M32, m.M44 - m.M42));
		FrustumPlanes[4] = Plane.Normalize(Plane(m.M13, m.M23, m.M33, m.M43));
		FrustumPlanes[5] = Plane.Normalize(Plane(m.M14 - m.M13, m.M24 - m.M23, m.M34 - m.M33, m.M44 - m.M43));
	}

	public void AdvanceTAAJitter()
	{
		if (PostProcess.EnableTAA && Width > 0 && Height > 0)
			TAAJitter.Advance(Width, Height);
	}

	public bool IsVisible(BoundingBox bounds)
	{
		for (let plane in FrustumPlanes)
		{
			Vector3 positiveVertex = .(
				plane.Normal.X >= 0 ? bounds.Max.X : bounds.Min.X,
				plane.Normal.Y >= 0 ? bounds.Max.Y : bounds.Min.Y,
				plane.Normal.Z >= 0 ? bounds.Max.Z : bounds.Min.Z
			);
			if (Vector3.Dot(plane.Normal, positiveVertex) + plane.D < 0)
				return false;
		}
		return true;
	}

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

	public static void SetupSplitScreen(Span<RenderView> views, uint32 swapWidth, uint32 swapHeight, bool horizontal = false)
	{
		let count = (int32)views.Length;
		for (int32 i = 0; i < count; i++)
		{
			views[i].ViewIndex = i;
			if (horizontal)
			{
				views[i].ViewportX = (uint32)(i * (int32)swapWidth / count);
				views[i].ViewportY = 0;
				views[i].Width = swapWidth / (uint32)count;
				views[i].Height = swapHeight;
			}
			else
			{
				views[i].ViewportX = 0;
				views[i].ViewportY = (uint32)(i * (int32)swapHeight / count);
				views[i].Width = swapWidth;
				views[i].Height = swapHeight / (uint32)count;
			}
		}
	}
}
