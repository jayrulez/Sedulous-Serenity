namespace Sedulous.Engine.Render;

using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Resources;
using Sedulous.Serialization;
using static Sedulous.Resources.ResourceSerializerExtensions;

/// Transient data struct for SpriteComponent serialization/deserialization.
/// Not stored on entities — only used by SpriteComponentSerializer during save/load.
struct SpriteComponentData : ISerializableComponentData
{
	[Property]
	public Vector2 Size;
	[Property(.Color)]
	public Vector4 Color;
	[Property]
	public Vector4 UVRect;
	[Property]
	public uint32 LayerMask;
	[Property]
	public bool Enabled;
	[Property]
	public ResourceRef TextureRef;

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

	public void Dispose() mut
	{
		TextureRef.Dispose();
	}
}
