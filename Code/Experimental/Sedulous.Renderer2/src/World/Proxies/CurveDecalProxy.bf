namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;

/// A control point on a curve decal.
public struct CurveDecalPoint
{
	/// World-space position.
	public Vector3 Position;

	/// Width of the decal at this point.
	public float Width;

	/// V coordinate along the curve (0 = start, 1 = end).
	public float UV_V;
}

/// Proxy for a curve-projected decal (e.g., tire tracks, road markings, rivers).
/// The decal is defined by a spline of control points; a triangle strip is generated
/// and projected onto the scene depth buffer.
public struct CurveDecalProxy
{
	/// Control points defining the curve path.
	public CurveDecalPoint[RenderConfig.MaxCurveDecalPoints] ControlPoints;

	/// Number of active control points (2 minimum for a valid curve).
	public int32 PointCount;

	/// Albedo texture applied along the curve strip.
	public ITextureView AlbedoTexture;

	/// Sampler for the albedo texture.
	public ISampler Sampler;

	/// Tint color (RGBA, A = opacity).
	public Vector4 Color;

	/// Blend mode for this decal.
	public DecalBlendMode BlendMode;

	/// Render order for sorting (lower = rendered first).
	public int32 SortOrder;

	/// UV tiling along the U axis (perpendicular to curve).
	public float UVTilingU;

	/// UV tiling along the V axis (along the curve).
	public float UVTilingV;

	/// Depth below/above surface for projection conformity.
	public float ProjectionDepth;

	/// Whether this decal is active.
	public bool IsActive;

	/// Generation counter for handle validation.
	public uint32 Generation;

	/// World-space bounding box enclosing all control points.
	public BoundingBox WorldBounds;

	/// Dirty flag — set when control points change, cleared after mesh rebuild.
	public bool MeshDirty;

	/// Creates a default curve decal proxy.
	public static Self CreateDefault()
	{
		var decal = Self();
		decal.PointCount = 0;
		decal.AlbedoTexture = null;
		decal.Sampler = null;
		decal.Color = .(1, 1, 1, 1);
		decal.BlendMode = .Alpha;
		decal.SortOrder = 0;
		decal.UVTilingU = 1.0f;
		decal.UVTilingV = 1.0f;
		decal.ProjectionDepth = 1.0f;
		decal.IsActive = true;
		decal.MeshDirty = true;
		return decal;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		PointCount = 0;
		AlbedoTexture = null;
		Sampler = null;
		Color = .(1, 1, 1, 1);
		BlendMode = .Alpha;
		SortOrder = 0;
		UVTilingU = 1.0f;
		UVTilingV = 1.0f;
		ProjectionDepth = 1.0f;
		IsActive = false;
		Generation = 0;
		WorldBounds = .(.Zero, .Zero);
		MeshDirty = true;
	}

	/// Recalculates the world bounding box from active control points.
	public void RecalculateBounds() mut
	{
		if (PointCount < 2)
		{
			WorldBounds = .(.Zero, .Zero);
			return;
		}

		var minPt = ControlPoints[0].Position;
		var maxPt = minPt;
		float maxWidth = ControlPoints[0].Width;

		for (int32 i = 1; i < PointCount; i++)
		{
			let p = ControlPoints[i].Position;
			minPt = Vector3.Min(minPt, p);
			maxPt = Vector3.Max(maxPt, p);
			maxWidth = Math.Max(maxWidth, ControlPoints[i].Width);
		}

		// Expand by max half-width + projection depth
		let expand = Vector3(maxWidth * 0.5f + ProjectionDepth);
		WorldBounds = .(minPt - expand, maxPt + expand);
	}
}
