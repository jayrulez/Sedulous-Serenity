namespace Sedulous.Framework.Render;

using System;
using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Textures.Resources;
using static Sedulous.Resources.ResourceSerializerExtensions;

/// Component for decal entities.
/// Stores decal configuration for serialization and proxy creation.
[Component]
struct DecalComponent : ISerializableComponent
{
	/// Scale of the decal volume (width, height, depth of the projection box).
	[Property] public Vector3 Scale;
	/// Tint color (RGBA, A = opacity).
	[Property] public Vector4 Color;
	/// Angle (in radians) where fade starts (0 = facing surface).
	[Property] public float AngleFadeStart;
	/// Angle (in radians) where fade ends (fully transparent).
	[Property] public float AngleFadeEnd;
	/// Render order for sorting (lower = rendered first).
	[Property] public int32 SortOrder;
	/// Blend mode for this decal.
	[Property] public DecalBlendMode BlendMode;
	/// Whether this decal is enabled.
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
		s.FixedFloatArray("scale", &Scale.X, 3);
		s.FixedFloatArray("color", &Color.X, 4);
		s.Float("angleFadeStart", ref AngleFadeStart);
		s.Float("angleFadeEnd", ref AngleFadeEnd);
		s.Int32("sortOrder", ref SortOrder);
		var blendModeInt = (int32)BlendMode;
		s.Int32("blendMode", ref blendModeInt);
		BlendMode = (DecalBlendMode)blendModeInt;
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static DecalComponent Default => .() {
		Scale = .(1, 1, 1),
		Color = .(1, 1, 1, 1),
		AngleFadeStart = 0.0f,
		AngleFadeEnd = Math.PI_f * 0.5f,
		SortOrder = 0,
		BlendMode = .Alpha,
		Enabled = true,
		Texture = default,
		TextureRef = .()
	};
}
