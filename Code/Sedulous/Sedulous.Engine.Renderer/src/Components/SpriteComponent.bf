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

	/// Sprite size in world units.
	public Vector2 Size = .(1, 1);

	/// UV rectangle (minU, minV, maxU, maxV).
	public Vector4 UVRect = .(0, 0, 1, 1);

	/// Sprite tint color.
	public Color Color = .White;

	/// Whether the sprite is visible.
	public bool Visible = true;

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

	/// Gets the sprite instance data for rendering.
	public SpriteInstance GetSpriteInstance()
	{
		var position = mEntity?.Transform.WorldPosition ?? .Zero;
		return .(position, Size, UVRect, Color);
	}

	// ==================== IEntityComponent Implementation ====================

	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		if (entity.Scene != null)
		{
			mRenderScene = entity.Scene.GetSceneComponent<RenderSceneComponent>();
			mRenderScene?.RegisterSprite(this);
		}
	}

	public void OnDetach()
	{
		mRenderScene?.UnregisterSprite(this);
		mEntity = null;
		mRenderScene = null;
	}

	public void OnUpdate(float deltaTime)
	{
		// Sprite position is updated from entity transform during render collection
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
