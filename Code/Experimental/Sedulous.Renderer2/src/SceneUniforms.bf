namespace Sedulous.Renderer;

using Sedulous.Core.Mathematics;
using System;

/// GPU-uploadable per-frame scene uniforms.
/// Must match scene_uniforms.hlsli exactly.
/// Must match Serenity's SceneUniforms in FrameContext.bf.
[CRepr]
public struct SceneUniforms
{
	public Matrix ViewMatrix;
	public Matrix ProjectionMatrix;
	public Matrix ViewProjectionMatrix;
	public Matrix InverseViewMatrix;
	public Matrix InverseProjectionMatrix;
	public Matrix PrevViewProjectionMatrix;

	public Vector3 CameraPosition;
	public float Time;

	public Vector3 CameraForward;
	public float DeltaTime;

	public Vector2 ScreenSize;
	public float NearPlane;
	public float FarPlane;

	// Hardcoded to match Serenity — do NOT use sizeof(Self)
	public const uint64 Size = 464;

	public static Self Identity => .()
	{
		ViewMatrix = .Identity,
		ProjectionMatrix = .Identity,
		ViewProjectionMatrix = .Identity,
		InverseViewMatrix = .Identity,
		InverseProjectionMatrix = .Identity,
		PrevViewProjectionMatrix = .Identity,
		CameraPosition = .Zero,
		CameraForward = .(0, 0, -1),
	};
}
