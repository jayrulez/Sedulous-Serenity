namespace Sedulous.Engine.Render;

using Sedulous.Foundation.Mathematics;
using Sedulous.Serialization;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using System;

using static Sedulous.Foundation.Mathematics.MathSerializerExtensions;

/// Persistent settings for the render scene module.
/// Auto-discovered by Scene and serialized in .scene files.
[ModuleSettings("RenderSceneModule", "Environment")]
class RenderModuleSettings : ISerializable
{
	// Ambient lighting
	[Property(.Color)] public Vector3 AmbientColor = .(0.15f, 0.15f, 0.2f);
	[Property] public float AmbientIntensity = 0.5f;
	[Property] public float Exposure = 1.0f;

	// Sky
	[Property] public SkyMode SkyMode = .Procedural;
	[Property] public Vector3 SunDirection = Vector3.Normalize(.(-0.5f, 0.8f, 0.3f));
	[Property] public float SunIntensity = 20.0f;
	[Property(.Color)] public Vector3 SunColor = .(1.0f, 0.95f, 0.9f);
	[Property] public float AtmosphereDensity = 1.0f;
	[Property(.Color)] public Vector3 ZenithColor = .(0.3f, 0.5f, 0.85f);
	[Property(.Color)] public Vector3 HorizonColor = .(0.8f, 0.85f, 0.9f);
	[Property(.Color)] public Vector3 GroundColor = .(0.3f, 0.25f, 0.2f);
	[Property(.Color)] public Vector3 SolidSkyColor = .(0.529f, 0.808f, 0.922f);

	public int32 SerializationVersion => 1;

	public this()
	{

	}

	public SerializationResult Serialize(Serializer s)
	{
		s.Vector3("ambientColor", ref AmbientColor);
		s.Float("ambientIntensity", ref AmbientIntensity);
		s.Float("exposure", ref Exposure);

		s.Enum("skyMode", ref SkyMode);
		s.Vector3("sunDirection", ref SunDirection);
		s.Float("sunIntensity", ref SunIntensity);
		s.Vector3("sunColor", ref SunColor);
		s.Float("atmosphereDensity", ref AtmosphereDensity);
		s.Vector3("zenithColor", ref ZenithColor);
		s.Vector3("horizonColor", ref HorizonColor);
		s.Vector3("groundColor", ref GroundColor);
		s.Vector3("solidSkyColor", ref SolidSkyColor);
		return .Ok;
	}
}
