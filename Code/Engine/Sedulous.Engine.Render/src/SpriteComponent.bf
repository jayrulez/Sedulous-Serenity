namespace Sedulous.Engine.Render;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Textures.Resources;
using static Sedulous.Resources.ResourceSerializerExtensions;

/// Component for sprite entities.
/// Stores sprite configuration for serialization and proxy creation.
[Component]
struct SpriteComponent : ISerializableComponent
{
	/// Billboard size (width, height).
	[Property] public Vector2 Size;
	/// Tint color (RGBA).
	[Property] public Vector4 Color;
	/// UV rect for atlas sub-region (minU, minV, maxU, maxV).
	[Property] public Vector4 UVRect;
	/// Render layer mask.
	[Property] public uint32 LayerMask;
	/// Whether this sprite is enabled.
	[Property] public bool Enabled;
	/// The texture resource handle (runtime, not serialized).
	public ResourceHandle<TextureResource> Texture;
	/// Serializable reference to the texture resource.
	[Property] public ResourceRef TextureRef;

	public void Dispose() mut
	{
		TextureRef.Dispose();
	}

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.ResourceRef("texture", ref TextureRef);
		s.FixedFloatArray("size", &Size.X, 2);
		s.FixedFloatArray("color", &Color.X, 4);
		s.FixedFloatArray("uvRect", &UVRect.X, 4);
		s.UInt32("layerMask", ref LayerMask);
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static SpriteComponent Default => .() {
		Size = .(1, 1),
		Color = .(1, 1, 1, 1),
		UVRect = .(0, 0, 1, 1),
		LayerMask = 0xFFFFFFFF,
		Enabled = true,
		Texture = default,
		TextureRef = .()
	};
}
