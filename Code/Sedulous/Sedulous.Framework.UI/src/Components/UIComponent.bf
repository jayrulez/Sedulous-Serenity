using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.UI;
using Sedulous.Framework.Core;

namespace Sedulous.Framework.UI;

/// Entity component for attaching UI to entities.
/// Supports both screen-space overlay and world-space UI.
class UIComponent : IEntityComponent
{
	private Entity mEntity;
	private UIContext mUI ~ delete _;
	private bool mScreenSpace = true;
	private Vector3 mWorldPosition = .Zero;
	private float mWorldScale = 1.0f;
	private bool mBillboardMode = false;
	private bool mIsVisible = true;

	/// Gets the UI context for this component.
	public UIContext UI => mUI;

	/// Gets or sets whether this UI is screen-space (overlay) or world-space.
	public bool ScreenSpace
	{
		get => mScreenSpace;
		set => mScreenSpace = value;
	}

	/// Gets or sets the world position for world-space UI.
	public Vector3 WorldPosition
	{
		get => mWorldPosition;
		set => mWorldPosition = value;
	}

	/// Gets or sets the scale for world-space UI.
	public float WorldScale
	{
		get => mWorldScale;
		set => mWorldScale = value;
	}

	/// Gets or sets whether the UI should billboard (face the camera).
	public bool BillboardMode
	{
		get => mBillboardMode;
		set => mBillboardMode = value;
	}

	/// Gets or sets whether the UI is visible.
	public bool IsVisible
	{
		get => mIsVisible;
		set => mIsVisible = value;
	}

	/// Gets the entity this component is attached to.
	public Entity Entity => mEntity;

	/// Creates a UI component.
	public this()
	{
		mUI = new UIContext();
	}

	// ============ IEntityComponent Implementation ============

	public void OnAttach(Entity entity)
	{
		mEntity = entity;
	}

	public void OnDetach()
	{
		mEntity = null;
	}

	public void OnUpdate(float deltaTime)
	{
		if (!mIsVisible)
			return;

		// Update the UI context
		mUI.Update(deltaTime);

		// Update world position from entity transform if needed
		if (!mScreenSpace && mEntity != null)
		{
			// Entity transform access would be handled by the scene component
		}
	}

	// ============ ISerializable Implementation ============

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		serializer.Bool("ScreenSpace", ref mScreenSpace);
		serializer.Float("WorldScale", ref mWorldScale);
		serializer.Bool("BillboardMode", ref mBillboardMode);
		serializer.Bool("IsVisible", ref mIsVisible);

		// World position
		serializer.Float("WorldPositionX", ref mWorldPosition.X);
		serializer.Float("WorldPositionY", ref mWorldPosition.Y);
		serializer.Float("WorldPositionZ", ref mWorldPosition.Z);

		return .Ok;
	}

	/// Gets the screen-space bounds of this UI.
	public RectangleF GetScreenBounds()
	{
		if (mUI.Root == null)
			return RectangleF(0, 0, 0, 0);

		return mUI.Root.Bounds;
	}

	/// Transforms a screen point to local UI coordinates.
	public Vector2 ScreenToLocal(Vector2 screenPoint)
	{
		if (mUI.Root == null)
			return screenPoint;

		return mUI.Root.ScreenToLocal(screenPoint);
	}

	/// Checks if a screen point hits any widget in this UI.
	public Widget HitTest(Vector2 screenPoint)
	{
		if (mUI.Root == null || !mIsVisible)
			return null;

		return mUI.Root.HitTestRecursive(screenPoint);
	}
}
