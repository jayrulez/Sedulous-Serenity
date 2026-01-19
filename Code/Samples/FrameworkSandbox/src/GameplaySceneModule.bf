using System;
using Sedulous.Mathematics;
using Sedulous.Framework.Scenes;

namespace FrameworkSandbox;

/// Example component for custom game data - makes entity spin.
struct SpinComponent
{
	public float Speed;
	public float CurrentAngle;

	public static SpinComponent Default => .() {
		Speed = 1.0f,
		CurrentAngle = 0.0f
	};
}

/// Example component for bobbing up and down.
struct BobComponent
{
	public float Speed;
	public float Amplitude;
	public float BaseY;
	public float Phase;

	public static BobComponent Default => .() {
		Speed = 2.0f,
		Amplitude = 0.3f,
		BaseY = 0.5f,
		Phase = 0.0f
	};
}

/// Custom scene module demonstrating gameplay logic.
/// Processes SpinComponent and BobComponent each frame.
class GameplaySceneModule : SceneModule
{
	private Scene mScene;
	private float mTime = 0;

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
	}

	public override void OnSceneDestroy(Scene scene)
	{
		mScene = null;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		mTime += deltaTime;

		// Update spinning entities
		for (let (entity, spin) in scene.Query<SpinComponent>())
		{
			spin.CurrentAngle += spin.Speed * deltaTime;

			// Update entity rotation
			var transform = scene.GetTransform(entity);
			transform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), spin.CurrentAngle);
			scene.SetTransform(entity, transform);
		}

		// Update bobbing entities
		for (let (entity, bob) in scene.Query<BobComponent>())
		{
			var transform = scene.GetTransform(entity);
			transform.Position.Y = bob.BaseY + Math.Sin(mTime * bob.Speed + bob.Phase) * bob.Amplitude;
			scene.SetTransform(entity, transform);
		}
	}
}
