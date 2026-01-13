namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.Renderer;

/// Entity component that creates a trail/ribbon effect following the entity.
/// Useful for sword swings, projectiles, laser beams, motion blur effects.
class TrailComponent : IEntityComponent
{
	// Entity and scene references
	private Entity mEntity;
	private RenderSceneComponent mRenderScene;

	// Trail data
	private ParticleTrail mTrail ~ delete _;
	private float mLastUpdateTime = 0;

	/// Whether the trail is currently emitting (adding new points).
	public bool IsEmitting = true;

	/// Maximum number of points in the trail.
	public int32 MaxPoints
	{
		get => mMaxPoints;
		set
		{
			if (value != mMaxPoints)
			{
				mMaxPoints = value;
				RecreateTrail();
			}
		}
	}
	private int32 mMaxPoints = 30;

	/// Minimum distance between trail points.
	public float MinVertexDistance = 0.1f;

	/// Width at the head (entity position) of the trail.
	public float WidthStart = 0.5f;

	/// Width at the tail of the trail.
	public float WidthEnd = 0.0f;

	/// Maximum age of trail points in seconds.
	public float MaxAge = 1.0f;

	/// Trail color at the head.
	public Color ColorStart = .White;

	/// Trail color at the tail.
	public Color ColorEnd = .(255, 255, 255, 0);

	/// Blend mode for rendering.
	public ParticleBlendMode BlendMode = .AlphaBlend;

	/// Soft edge amount (0 = hard edges, 1 = very soft).
	public float SoftEdge = 0.3f;

	/// Whether to inherit color from a gradient over the trail length.
	public bool UseColorGradient = true;

	/// Local offset from entity position for trail origin.
	public Vector3 LocalOffset = .Zero;

	/// Creates a new TrailComponent with default settings.
	public this()
	{
		mTrail = new ParticleTrail(mMaxPoints);
	}

	/// Creates a TrailComponent with custom settings.
	public this(int32 maxPoints, float minDistance = 0.1f, float maxAge = 1.0f)
	{
		mMaxPoints = maxPoints;
		MinVertexDistance = minDistance;
		MaxAge = maxAge;
		mTrail = new ParticleTrail(maxPoints);
		mTrail.MinVertexDistance = minDistance;
	}

	/// Creates a laser beam trail preset.
	public static TrailComponent CreateLaser(Color color, float width = 0.1f)
	{
		let trail = new TrailComponent(40, 0.05f, 0.5f);
		trail.WidthStart = width;
		trail.WidthEnd = width * 0.5f;
		trail.ColorStart = color;
		trail.ColorEnd = .(color.R, color.G, color.B, 0);
		trail.BlendMode = .Additive;
		trail.SoftEdge = 0.2f;
		return trail;
	}

	/// Creates a magic trail preset.
	public static TrailComponent CreateMagic(Color color)
	{
		let trail = new TrailComponent(50, 0.08f, 0.8f);
		trail.WidthStart = 0.3f;
		trail.WidthEnd = 0.0f;
		trail.ColorStart = color;
		trail.ColorEnd = .(color.R, color.G, color.B, 0);
		trail.BlendMode = .Additive;
		trail.SoftEdge = 0.4f;
		return trail;
	}

	/// Creates a sword swing trail preset.
	public static TrailComponent CreateSwordSwing(Color color = .(200, 220, 255, 200))
	{
		let trail = new TrailComponent(20, 0.02f, 0.15f);
		trail.WidthStart = 1.0f;
		trail.WidthEnd = 0.3f;
		trail.ColorStart = color;
		trail.ColorEnd = .(color.R, color.G, color.B, 0);
		trail.BlendMode = .AlphaBlend;
		trail.SoftEdge = 0.5f;
		return trail;
	}

	/// Creates a motion blur trail preset.
	public static TrailComponent CreateMotionBlur()
	{
		let trail = new TrailComponent(15, 0.02f, 0.1f);
		trail.WidthStart = 1.0f;
		trail.WidthEnd = 0.8f;
		trail.ColorStart = .(255, 255, 255, 150);
		trail.ColorEnd = .(255, 255, 255, 0);
		trail.BlendMode = .AlphaBlend;
		trail.SoftEdge = 0.3f;
		trail.UseColorGradient = false;
		return trail;
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
				// Register this trail component with the scene
				mRenderScene.RegisterTrailComponent(this);
			}
		}
	}

	/// Called when the component is detached from an entity.
	public void OnDetach()
	{
		if (mRenderScene != null)
		{
			mRenderScene.UnregisterTrailComponent(this);
		}

		mEntity = null;
		mRenderScene = null;
	}

	/// Called each frame to update the component.
	public void OnUpdate(float deltaTime)
	{
		if (mTrail == null || mEntity == null)
			return;

		mLastUpdateTime += deltaTime;

		// Update trail settings
		mTrail.MinVertexDistance = MinVertexDistance;

		if (IsEmitting)
		{
			// Calculate world position with local offset
			let worldPos = mEntity.Transform.WorldPosition +
				mEntity.Transform.Right * LocalOffset.X +
				mEntity.Transform.Up * LocalOffset.Y +
				mEntity.Transform.Forward * LocalOffset.Z;

			// Calculate color based on gradient or use start color
			Color pointColor = ColorStart;

			// Add point to trail
			mTrail.TryAddPoint(worldPos, 1.0f, pointColor, mLastUpdateTime);
		}

		// Remove old points
		mTrail.RemoveOldPoints(mLastUpdateTime, MaxAge);
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// Max points
		result = serializer.Int32("maxPoints", ref mMaxPoints);
		if (result != .Ok) return result;

		// Distances and sizes
		result = serializer.Float("minVertexDistance", ref MinVertexDistance);
		if (result != .Ok) return result;

		result = serializer.Float("widthStart", ref WidthStart);
		if (result != .Ok) return result;

		result = serializer.Float("widthEnd", ref WidthEnd);
		if (result != .Ok) return result;

		result = serializer.Float("maxAge", ref MaxAge);
		if (result != .Ok) return result;

		// Colors
		int32 colorStartVal = (int32)ColorStart.PackedValue;
		result = serializer.Int32("colorStart", ref colorStartVal);
		if (result != .Ok) return result;
		if (serializer.IsReading)
			ColorStart = .((uint32)colorStartVal);

		int32 colorEndVal = (int32)ColorEnd.PackedValue;
		result = serializer.Int32("colorEnd", ref colorEndVal);
		if (result != .Ok) return result;
		if (serializer.IsReading)
			ColorEnd = .((uint32)colorEndVal);

		// Blend mode
		int32 blendModeVal = (int32)BlendMode;
		result = serializer.Int32("blendMode", ref blendModeVal);
		if (result != .Ok) return result;
		if (serializer.IsReading)
			BlendMode = (ParticleBlendMode)blendModeVal;

		// Soft edge
		result = serializer.Float("softEdge", ref SoftEdge);
		if (result != .Ok) return result;

		// Flags
		int32 flags = (IsEmitting ? 1 : 0) | (UseColorGradient ? 2 : 0);
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok) return result;
		if (serializer.IsReading)
		{
			IsEmitting = (flags & 1) != 0;
			UseColorGradient = (flags & 2) != 0;
		}

		// Local offset
		float[3] offsetArr = .(LocalOffset.X, LocalOffset.Y, LocalOffset.Z);
		result = serializer.FixedFloatArray("localOffset", &offsetArr, 3);
		if (result != .Ok) return result;
		if (serializer.IsReading)
			LocalOffset = .(offsetArr[0], offsetArr[1], offsetArr[2]);

		// Recreate trail with loaded settings
		if (serializer.IsReading)
			RecreateTrail();

		return .Ok;
	}

	// ==================== Public Methods ====================

	/// Gets the underlying ParticleTrail (for rendering).
	public ParticleTrail Trail => mTrail;

	/// Gets trail settings for rendering.
	public TrailSettings GetTrailSettings()
	{
		return .()
		{
			Enabled = true,
			MaxPoints = mMaxPoints,
			MinVertexDistance = MinVertexDistance,
			WidthStart = WidthStart,
			WidthEnd = WidthEnd,
			MaxAge = MaxAge,
			InheritParticleColor = false,
			TrailColor = ColorStart
		};
	}

	/// Gets the current time for trail rendering.
	public float CurrentTime => mLastUpdateTime;

	/// Clears all trail points.
	public void Clear()
	{
		mTrail?.Clear();
	}

	/// Forces adding a point regardless of distance threshold.
	public void ForceAddPoint()
	{
		if (mTrail == null || mEntity == null)
			return;

		let worldPos = mEntity.Transform.WorldPosition +
			mEntity.Transform.Right * LocalOffset.X +
			mEntity.Transform.Up * LocalOffset.Y +
			mEntity.Transform.Forward * LocalOffset.Z;

		mTrail.ForceAddPoint(worldPos, 1.0f, ColorStart, mLastUpdateTime);
	}

	/// Number of points currently in the trail.
	public int32 PointCount => mTrail?.PointCount ?? 0;

	/// Whether the trail has any points.
	public bool HasPoints => mTrail != null && mTrail.HasPoints;

	// ==================== Internal ====================

	private void RecreateTrail()
	{
		if (mTrail != null)
			delete mTrail;
		mTrail = new ParticleTrail(mMaxPoints);
		mTrail.MinVertexDistance = MinVertexDistance;
	}
}
