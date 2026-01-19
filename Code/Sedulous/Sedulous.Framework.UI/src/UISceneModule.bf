namespace Sedulous.Framework.UI;

using System;
using Sedulous.Framework.Scenes;

/// Scene module for managing UI elements in the scene.
/// Created automatically by UISubsystem for each scene.
/// UI integration with Sedulous.UI will be added later.
class UISceneModule : SceneModule
{
	private UISubsystem mSubsystem;
	private Scene mScene;

	/// Creates a UISceneModule linked to the given subsystem.
	public this(UISubsystem subsystem)
	{
		mSubsystem = subsystem;
	}

	/// Gets the UI subsystem.
	public UISubsystem Subsystem => mSubsystem;

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
		// TODO: Integrate with Sedulous.UI
	}
}
