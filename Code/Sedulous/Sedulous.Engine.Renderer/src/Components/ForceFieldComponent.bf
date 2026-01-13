namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.Renderer;

/// Entity component that creates a force field affecting particles.
/// Force fields are scene-level forces that affect all particles with ForceFieldModule.
class ForceFieldComponent : IEntityComponent
{
	// Entity and scene references
	private Entity mEntity;
	private RenderSceneComponent mRenderScene;
	private ForceFieldHandle mHandle = .Invalid;

	/// The type of force field.
	public ForceFieldType Type = .Directional;

	/// Force strength (can be negative for repulsion on Point type).
	public float Strength = 5.0f;

	/// Radius of effect (0 = infinite for Directional).
	public float Radius = 10.0f;

	/// Falloff exponent (0=constant, 1=linear, 2=quadratic).
	public float Falloff = 1.0f;

	/// Whether this force field is enabled.
	public bool Enabled = true;

	/// Layer mask for selective particle interaction.
	public uint32 LayerMask = 0xFFFFFFFF;

	// Vortex-specific
	/// Inward pull strength for vortex fields.
	public float InwardForce = 0.0f;

	// Turbulence-specific
	/// Noise frequency for turbulence fields.
	public float Frequency = 1.0f;

	/// Number of noise octaves for turbulence.
	public int32 Octaves = 2;

	/// Creates a new ForceFieldComponent.
	public this()
	{
	}

	/// Creates a directional (wind) force field component.
	public static ForceFieldComponent CreateDirectional(float strength = 5.0f)
	{
		let field = new ForceFieldComponent();
		field.Type = .Directional;
		field.Strength = strength;
		field.Radius = 0;  // Infinite
		return field;
	}

	/// Creates a point attractor/repulsor force field component.
	public static ForceFieldComponent CreatePoint(float strength, float radius, float falloff = 2.0f)
	{
		let field = new ForceFieldComponent();
		field.Type = .Point;
		field.Strength = strength;
		field.Radius = radius;
		field.Falloff = falloff;
		return field;
	}

	/// Creates a vortex force field component.
	public static ForceFieldComponent CreateVortex(float strength, float radius, float inwardForce = 0)
	{
		let field = new ForceFieldComponent();
		field.Type = .Vortex;
		field.Strength = strength;
		field.Radius = radius;
		field.InwardForce = inwardForce;
		return field;
	}

	/// Creates a turbulence force field component.
	public static ForceFieldComponent CreateTurbulence(float strength, float radius, float frequency = 1.0f, int32 octaves = 2)
	{
		let field = new ForceFieldComponent();
		field.Type = .Turbulence;
		field.Strength = strength;
		field.Radius = radius;
		field.Frequency = frequency;
		field.Octaves = octaves;
		return field;
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
				CreateForceField();
			}
		}
	}

	/// Called when the component is detached from an entity.
	public void OnDetach()
	{
		RemoveForceField();
		mEntity = null;
		mRenderScene = null;
	}

	/// Called each frame to update the component.
	public void OnUpdate(float deltaTime)
	{
		// Update force field properties from entity transform
		if (mRenderScene != null && mHandle.IsValid)
		{
			let renderWorld = mRenderScene.RenderWorld;
			if (let field = renderWorld.GetForceField(mHandle))
			{
				// Update position from entity
				field.Position = mEntity.Transform.WorldPosition;

				// Update direction from entity forward (for Directional and Vortex)
				field.Direction = mEntity.Transform.Forward;

				// Update other properties
				field.Strength = Strength;
				field.Radius = Radius;
				field.Falloff = Falloff;
				field.Enabled = Enabled;
				field.LayerMask = LayerMask;
				field.InwardForce = InwardForce;
				field.Frequency = Frequency;
				field.Octaves = Octaves;
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

		// Type
		int32 typeVal = (int32)Type;
		result = serializer.Int32("type", ref typeVal);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			Type = (ForceFieldType)typeVal;

		// Core properties
		result = serializer.Float("strength", ref Strength);
		if (result != .Ok) return result;

		result = serializer.Float("radius", ref Radius);
		if (result != .Ok) return result;

		result = serializer.Float("falloff", ref Falloff);
		if (result != .Ok) return result;

		// Enabled flag
		int32 enabledVal = Enabled ? 1 : 0;
		result = serializer.Int32("enabled", ref enabledVal);
		if (result != .Ok) return result;
		if (serializer.IsReading)
			Enabled = enabledVal != 0;

		// Layer mask
		int32 layerMaskVal = (int32)LayerMask;
		result = serializer.Int32("layerMask", ref layerMaskVal);
		if (result != .Ok) return result;
		if (serializer.IsReading)
			LayerMask = (uint32)layerMaskVal;

		// Type-specific properties
		result = serializer.Float("inwardForce", ref InwardForce);
		if (result != .Ok) return result;

		result = serializer.Float("frequency", ref Frequency);
		if (result != .Ok) return result;

		result = serializer.Int32("octaves", ref Octaves);
		if (result != .Ok) return result;

		return .Ok;
	}

	// ==================== Internal ====================

	private void CreateForceField()
	{
		if (mRenderScene == null || mEntity == null)
			return;

		let renderWorld = mRenderScene.RenderWorld;
		let transform = mEntity.Transform;

		ForceField field;
		switch (Type)
		{
		case .Directional:
			field = .Directional(transform.Forward, Strength);
		case .Point:
			field = .Point(transform.WorldPosition, Strength, Radius, Falloff);
		case .Vortex:
			field = .Vortex(transform.WorldPosition, transform.Forward, Strength, Radius, InwardForce);
		case .Turbulence:
			field = .Turbulence(transform.WorldPosition, Strength, Radius, Frequency, Octaves);
		}

		field.Enabled = Enabled;
		field.LayerMask = LayerMask;

		mHandle = renderWorld.CreateForceField(field);
	}

	private void RemoveForceField()
	{
		if (mRenderScene != null && mHandle.IsValid)
		{
			mRenderScene.RenderWorld.DestroyForceField(mHandle);
		}
		mHandle = .Invalid;
	}

	/// Recreates the force field (e.g., if type changes at runtime).
	public void RecreateForceField()
	{
		RemoveForceField();
		CreateForceField();
	}

	/// Gets the force field handle (for advanced usage).
	public ForceFieldHandle Handle => mHandle;
}
