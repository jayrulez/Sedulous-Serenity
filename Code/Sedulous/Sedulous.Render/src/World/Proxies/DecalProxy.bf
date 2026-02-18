namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Blend mode for decal rendering.
[Reflect]
public enum DecalBlendMode
{
	/// Standard alpha blending.
	Alpha,
	/// Additive blending (glowing effects).
	Additive,
	/// Multiply blending (darkening effects).
	Multiply
}

/// Proxy for a projected decal in the render world.
public struct DecalProxy
{
	/// World-space position of the decal center.
	public Vector3 Position;

	/// Rotation of the decal volume.
	public Quaternion Rotation;

	/// Scale of the decal volume (width, height, depth of the projection box).
	public Vector3 Scale;

	/// Albedo texture projected by this decal.
	public ITextureView AlbedoTexture;

	/// Sampler for the albedo texture.
	public ISampler Sampler;

	/// Tint color (RGBA, A = opacity).
	public Vector4 Color;

	/// Angle (in radians) where fade starts (0 = facing surface, PI/2 = perpendicular).
	public float AngleFadeStart;

	/// Angle (in radians) where fade ends (fully transparent).
	public float AngleFadeEnd;

	/// Render order for sorting (lower = rendered first).
	public int32 SortOrder;

	/// Blend mode for this decal.
	public DecalBlendMode BlendMode;

	/// Whether this decal is active.
	public bool IsActive;

	/// Generation counter for handle validation.
	public uint32 Generation;

	/// Computes the world matrix for this decal (Scale * Rotation * Translation).
	public Matrix GetWorldMatrix()
	{
		return Matrix.CreateScale(Scale) *
			Matrix.CreateFromQuaternion(Rotation) *
			Matrix.CreateTranslation(Position);
	}

	/// Computes the inverse world matrix for projection.
	public Matrix GetInvWorldMatrix()
	{
		let world = GetWorldMatrix();
		return Matrix.Invert(world);
	}

	/// Creates a default decal proxy.
	public static Self CreateDefault()
	{
		var decal = Self();
		decal.Position = .Zero;
		decal.Rotation = .Identity;
		decal.Scale = .(1, 1, 1);
		decal.AlbedoTexture = null;
		decal.Sampler = null;
		decal.Color = .(1, 1, 1, 1);
		decal.AngleFadeStart = 0.0f;
		decal.AngleFadeEnd = Math.PI_f * 0.5f;
		decal.SortOrder = 0;
		decal.BlendMode = .Alpha;
		decal.IsActive = true;
		return decal;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		Position = .Zero;
		Rotation = .Identity;
		Scale = .(1, 1, 1);
		AlbedoTexture = null;
		Sampler = null;
		Color = .(1, 1, 1, 1);
		AngleFadeStart = 0.0f;
		AngleFadeEnd = Math.PI_f * 0.5f;
		SortOrder = 0;
		BlendMode = .Alpha;
		IsActive = false;
		Generation = 0;
	}
}
