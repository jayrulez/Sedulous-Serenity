namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;

/// Entity component that adds a light source.
class LightComponent : IEntityComponent
{
	// Entity and scene references
	private Entity mEntity;
	private RenderSceneComponent mRenderScene;
	private ProxyHandle mProxyHandle = .Invalid;

	/// The type of light.
	public LightType Type = .Point;

	/// Light color (linear RGB).
	public Vector3 Color = .(1, 1, 1);

	/// Light intensity.
	public float Intensity = 1.0f;

	/// Range of the light (for point and spot lights).
	public float Range = 10.0f;

	/// Inner cone angle in radians (spot lights only).
	public float InnerConeAngle = Math.PI_f / 8.0f;

	/// Outer cone angle in radians (spot lights only).
	public float OuterConeAngle = Math.PI_f / 4.0f;

	/// Whether this light casts shadows.
	public bool CastsShadows = false;

	/// Whether this light is enabled.
	public bool Enabled = true;

	/// Creates a new LightComponent.
	public this()
	{
	}

	/// Creates a directional light component.
	public static LightComponent CreateDirectional(Vector3 color, float intensity, bool castShadows = false)
	{
		let light = new LightComponent();
		light.Type = .Directional;
		light.Color = color;
		light.Intensity = intensity;
		light.CastsShadows = castShadows;
		return light;
	}

	/// Creates a point light component.
	public static LightComponent CreatePoint(Vector3 color, float intensity, float range, bool castShadows = false)
	{
		let light = new LightComponent();
		light.Type = .Point;
		light.Color = color;
		light.Intensity = intensity;
		light.Range = range;
		light.CastsShadows = castShadows;
		return light;
	}

	/// Creates a spot light component.
	public static LightComponent CreateSpot(Vector3 color, float intensity, float range,
		float innerAngle, float outerAngle, bool castShadows = false)
	{
		let light = new LightComponent();
		light.Type = .Spot;
		light.Color = color;
		light.Intensity = intensity;
		light.Range = range;
		light.InnerConeAngle = innerAngle;
		light.OuterConeAngle = outerAngle;
		light.CastsShadows = castShadows;
		return light;
	}

	// ==================== IEntityComponent Implementation ====================

	/// Called when the component is attached to an entity.
	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		// Find the RenderSceneComponent
		if (entity.Scene != null)
		{
			mRenderScene = entity.Scene.GetSceneComponent<RenderSceneComponent>();
			if (mRenderScene != null)
			{
				CreateProxy();
			}
		}
	}

	/// Called when the component is detached from an entity.
	public void OnDetach()
	{
		RemoveProxy();
		mEntity = null;
		mRenderScene = null;
	}

	/// Called each frame to update the component.
	public void OnUpdate(float deltaTime)
	{
		// Update proxy properties if they've changed
		if (mRenderScene != null && mProxyHandle.IsValid)
		{
			if (let proxy = mRenderScene.RenderWorld.GetLightProxy(mProxyHandle))
			{
				proxy.Color = Color;
				proxy.Intensity = Intensity;
				proxy.Range = Range;
				proxy.InnerConeAngle = InnerConeAngle;
				proxy.OuterConeAngle = OuterConeAngle;
				proxy.CastsShadows = CastsShadows;
				proxy.Enabled = Enabled;
			}
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

		// Light type
		int32 typeVal = (int32)Type;
		result = serializer.Int32("type", ref typeVal);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			Type = (LightType)typeVal;

		// Color
		float[3] colorArr = .(Color.X, Color.Y, Color.Z);
		result = serializer.FixedFloatArray("color", &colorArr, 3);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			Color = .(colorArr[0], colorArr[1], colorArr[2]);

		// Intensity
		result = serializer.Float("intensity", ref Intensity);
		if (result != .Ok)
			return result;

		// Range
		result = serializer.Float("range", ref Range);
		if (result != .Ok)
			return result;

		// Cone angles (spot only, but serialize anyway for simplicity)
		result = serializer.Float("innerConeAngle", ref InnerConeAngle);
		if (result != .Ok)
			return result;
		result = serializer.Float("outerConeAngle", ref OuterConeAngle);
		if (result != .Ok)
			return result;

		// Flags
		int32 flags = (CastsShadows ? 1 : 0) | (Enabled ? 2 : 0);
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
		{
			CastsShadows = (flags & 1) != 0;
			Enabled = (flags & 2) != 0;
		}

		return .Ok;
	}

	// ==================== Internal ====================

	private void CreateProxy()
	{
		if (mRenderScene == null || mEntity == null)
			return;

		let transform = mEntity.Transform;

		switch (Type)
		{
		case .Directional:
			mProxyHandle = mRenderScene.CreateDirectionalLight(
				mEntity.Id,
				transform.Forward,
				Color,
				Intensity
			);
		case .Point:
			mProxyHandle = mRenderScene.CreatePointLight(
				mEntity.Id,
				transform.WorldPosition,
				Color,
				Intensity,
				Range
			);
		case .Spot:
			mProxyHandle = mRenderScene.CreateSpotLight(
				mEntity.Id,
				transform.WorldPosition,
				transform.Forward,
				Color,
				Intensity,
				Range,
				InnerConeAngle,
				OuterConeAngle
			);
		default:
			// Unknown light type - do nothing
		}

		// Set shadow flag
		if (mProxyHandle.IsValid)
		{
			if (let proxy = mRenderScene.RenderWorld.GetLightProxy(mProxyHandle))
			{
				proxy.CastsShadows = CastsShadows;
				proxy.Enabled = Enabled;
			}
		}
	}

	private void RemoveProxy()
	{
		if (mRenderScene != null && mEntity != null)
		{
			mRenderScene.RemoveLightProxy(mEntity.Id);
		}
		mProxyHandle = .Invalid;
	}

	/// Recreates the proxy (e.g., if light type changes at runtime).
	internal void RecreateProxy()
	{
		RemoveProxy();
		CreateProxy();
	}
}
