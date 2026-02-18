namespace Sedulous.Framework.Render;

using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.Framework.Scenes;

using static Sedulous.Mathematics.MathSerializerExtensions;

/// Persistent settings for the render scene module.
/// Auto-discovered by Scene and serialized in .scene files.
[ModuleSettings("RenderSceneModule", "Environment")]
class RenderModuleSettings : ISerializable
{
	[Property] public Vector3 AmbientColor = .(0.15f, 0.15f, 0.2f);
	[Property] public float AmbientIntensity = 0.5f;
	[Property] public float Exposure = 1.0f;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Vector3("ambientColor", ref AmbientColor);
		s.Float("ambientIntensity", ref AmbientIntensity);
		s.Float("exposure", ref Exposure);
		return .Ok;
	}
}
