namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;
using Sedulous.Renderer;

/// Entity component that renders a billboard sprite.
class SpriteComponent : IEntityComponent
{
	private Entity mEntity;
	private RenderSceneComponent mRenderScene;
	private ProxyHandle mProxyHandle = .Invalid;

	/// Sprite size in world units.
	public Vector2 Size = .(1, 1);

	/// UV rectangle (minU, minV, maxU, maxV).
	public Vector4 UVRect = .(0, 0, 1, 1);

	/// Sprite tint color.
	public Color Color = .White;

	/// Texture for this sprite (null = solid color).
	public ITextureView Texture = null;

	/// Whether the sprite is visible.
	public bool Visible = true;

	/// Gets the proxy handle for this sprite.
	public ProxyHandle ProxyHandle => mProxyHandle;

	/// Creates a new SpriteComponent.
	public this()
	{
	}

	/// Creates a sprite with specified size.
	public this(Vector2 size)
	{
		Size = size;
	}

	/// Creates a sprite with size and color.
	public this(Vector2 size, Color color)
	{
		Size = size;
		Color = color;
	}

	// ==================== IEntityComponent Implementation ====================

	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		if (entity.Scene != null)
		{
			mRenderScene = entity.Scene.GetSceneComponent<RenderSceneComponent>();
			CreateProxy();
		}
	}

	public void OnDetach()
	{
		DestroyProxy();
		mEntity = null;
		mRenderScene = null;
	}

	public void OnUpdate(float deltaTime)
	{
		// Update proxy properties if changed
		UpdateProxy();
	}

	/// Creates the render proxy for this sprite.
	private void CreateProxy()
	{
		if (mRenderScene == null || mEntity == null)
			return;

		let position = mEntity.Transform.WorldPosition;
		mProxyHandle = mRenderScene.CreateSpriteProxy(mEntity.Id, position, Size, UVRect, Color);

		// Set initial properties on the proxy
		if (mProxyHandle.IsValid && mRenderScene.RenderWorld != null)
		{
			if (let proxy = mRenderScene.RenderWorld.GetSpriteProxy(mProxyHandle))
			{
				// Set texture
				proxy.Texture = Texture;

				// Set visibility flag
				if (Visible)
					proxy.Flags |= .Visible;
				else
					proxy.Flags &= ~.Visible;
			}
		}
	}

	/// Destroys the render proxy for this sprite.
	private void DestroyProxy()
	{
		if (mRenderScene != null && mEntity != null)
			mRenderScene.DestroySpriteProxy(mEntity.Id);
		mProxyHandle = .Invalid;
	}

	/// Updates the proxy with current sprite properties.
	private void UpdateProxy()
	{
		if (!mProxyHandle.IsValid || mRenderScene?.RenderWorld == null)
			return;

		if (let proxy = mRenderScene.RenderWorld.GetSpriteProxy(mProxyHandle))
		{
			// Update size if changed
			if (proxy.Size != Size)
				proxy.SetSize(Size);

			// Update UV rect if changed
			if (proxy.UVRect != UVRect)
				proxy.UVRect = UVRect;

			// Update color if changed
			if (proxy.Color != Color)
				proxy.Color = Color;

			// Update texture if changed
			if (proxy.Texture != Texture)
				proxy.Texture = Texture;

			// Update visibility
			if (Visible && !proxy.Flags.HasFlag(.Visible))
				proxy.Flags |= .Visible;
			else if (!Visible && proxy.Flags.HasFlag(.Visible))
				proxy.Flags &= ~.Visible;
		}
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// Size
		float[2] sizeArr = .(Size.X, Size.Y);
		result = serializer.FixedFloatArray("size", &sizeArr, 2);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			Size = .(sizeArr[0], sizeArr[1]);

		// UV Rect
		float[4] uvArr = .(UVRect.X, UVRect.Y, UVRect.Z, UVRect.W);
		result = serializer.FixedFloatArray("uvRect", &uvArr, 4);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			UVRect = .(uvArr[0], uvArr[1], uvArr[2], uvArr[3]);

		// Color
		int32 colorVal = (int32)Color.ToArgb();
		result = serializer.Int32("color", ref colorVal);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			Color = Sedulous.Mathematics.Color.FromArgb((uint32)colorVal);

		// Visible
		int32 flags = Visible ? 1 : 0;
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			Visible = (flags & 1) != 0;

		return .Ok;
	}
}
