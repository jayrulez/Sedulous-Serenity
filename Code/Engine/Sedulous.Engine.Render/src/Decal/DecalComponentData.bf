namespace Sedulous.Engine.Render;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.Serialization;
using static Sedulous.Resources.ResourceSerializerExtensions;

/// Transient data struct for DecalComponent serialization/deserialization.
/// Not stored on entities — only used by DecalComponentSerializer during save/load.
struct DecalComponentData : ISerializableComponentData
{
	[Property]
	public Vector3 Scale;
	[Property(.Color)]
	public Vector4 Color;
	[Property]
	public float AngleFadeStart;
	[Property]
	public float AngleFadeEnd;
	[Property]
	public int32 SortOrder;
	[Property]
	public DecalBlendMode BlendMode;
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

	public void Dispose() mut
	{
		TextureRef.Dispose();
	}
}
