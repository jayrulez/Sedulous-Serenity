namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Configuration for particle emission and behavior.
class ParticleEmitterConfig
{
	// Emission
	public float EmissionRate = 100;
	public int32 BurstCount = 0;
	public float BurstInterval = 1.0f;
	public EmissionShape EmissionShape = .Point;

	// Initial values
	public RangeFloat InitialSpeed = .(1, 3);
	public RangeFloat InitialSize = .(0.1f, 0.3f);
	public RangeFloat InitialRotation = .(0, Math.PI_f * 2);
	public RangeFloat InitialRotationSpeed = .(0, 0);
	public RangeFloat Lifetime = .(1, 3);
	public RangeColor StartColor = .(Color.White);
	public RangeColor EndColor = .(Color(255, 255, 255, 0));

	// Physics
	public Vector3 Gravity = .(0, -9.81f, 0);
	public float Drag = 0.1f;
	public bool InheritVelocity = false;
	public float InheritVelocityFactor = 0.5f;

	// Rendering
	public ParticleBlendMode BlendMode = .Additive;
	public ParticleRenderMode RenderMode = .Billboard;
	public float StretchFactor = 1.0f;
	public float MinStretchLength = 0.1f;
	public bool SortParticles = false;

	// Texture animation
	public int32 TextureSheetRows = 1;
	public int32 TextureSheetColumns = 1;
	public int32 StartFrame = 0;
	public bool AnimateTextureSheet = false;
	public float AnimationFrameRate = 30;

	// Soft particles
	public bool SoftParticles = false;
	public float SoftParticleDistance = 0.5f;
}

/// CPU-driven particle emitter with simulation.
class ParticleEmitter : IDisposable
{
	// Particle pool
	private Particle[] mParticlePool ~ delete _;
	private int32 mActiveCount = 0;
	private int32 mMaxParticles;

	// Configuration
	private ParticleEmitterConfig mConfig ~ if (mOwnsConfig) delete _;
	private bool mOwnsConfig = false;

	// Emitter state
	private Vector3 mPosition;
	private Vector3 mVelocity;
	private float mEmissionAccumulator = 0;
	private float mBurstAccumulator = 0;
	private float mTotalTime = 0;
	private bool mEmitting = true;
	private Random mRandom = new .() ~ delete _;

	// Camera for sorting
	public Vector3 CameraPosition { get; set; } = .Zero;

	// Layer mask for force field filtering
	private uint32 mLayerMask = 0xFFFFFFFF;

	// Properties
	public int32 ParticleCount => mActiveCount;
	public int32 MaxParticles => mMaxParticles;
	public bool IsEmitting { get => mEmitting; set => mEmitting = value; }
	public Vector3 Position { get => mPosition; set => mPosition = value; }
	public Vector3 Velocity { get => mVelocity; set => mVelocity = value; }
	public ParticleEmitterConfig Config => mConfig;
	public uint32 LayerMask { get => mLayerMask; set => mLayerMask = value; }
	public float TotalTime => mTotalTime;

	public const int32 DefaultMaxParticles = 5000;

	public this(int32 maxParticles = DefaultMaxParticles)
	{
		mMaxParticles = maxParticles;
		mParticlePool = new Particle[maxParticles];
		mConfig = new ParticleEmitterConfig();
		mOwnsConfig = true;
	}

	public this(ParticleEmitterConfig config, int32 maxParticles = DefaultMaxParticles)
	{
		mMaxParticles = maxParticles;
		mParticlePool = new Particle[maxParticles];
		mConfig = config;
		mOwnsConfig = false;
	}

	/// Sets the emitter configuration.
	public void SetConfig(ParticleEmitterConfig config, bool ownConfig = false)
	{
		if (mOwnsConfig && mConfig != null)
			delete mConfig;
		mConfig = config;
		mOwnsConfig = ownConfig;
	}

	/// Updates particles and emits new ones.
	public void Update(float deltaTime)
	{
		if (mConfig == null)
			return;

		mTotalTime += deltaTime;

		// Update existing particles
		UpdateParticles(deltaTime);

		// Emit new particles
		if (mEmitting && mActiveCount < mMaxParticles)
			EmitParticles(deltaTime);
	}

	private void UpdateParticles(float deltaTime)
	{
		for (int i = mActiveCount - 1; i >= 0; i--)
		{
			ref Particle p = ref mParticlePool[i];

			p.Life -= deltaTime;
			if (p.Life <= 0)
			{
				RemoveParticleAt(i);
				continue;
			}

			float age = p.NormalizedAge;

			// Apply gravity and drag
			p.Velocity += mConfig.Gravity * deltaTime;
			if (mConfig.Drag > 0)
				p.Velocity *= (1.0f - mConfig.Drag * deltaTime);

			// Update position and rotation
			p.Position += p.Velocity * deltaTime;
			p.Rotation += p.RotationSpeed * deltaTime;

			// Interpolate color
			p.Color = mConfig.StartColor.Lerp(age).Interpolate(mConfig.EndColor.Lerp(age), age);

			// Update texture frame
			if (mConfig.AnimateTextureSheet && p.TotalFrames > 1)
			{
				if (mConfig.AnimationFrameRate > 0)
				{
					float elapsedTime = p.MaxLife - p.Life;
					int32 frame = (int32)(elapsedTime * mConfig.AnimationFrameRate) % p.TotalFrames;
					p.TextureFrame = (uint16)frame;
				}
				else
				{
					int32 frame = (int32)(age * (p.TotalFrames - 1));
					p.TextureFrame = (uint16)Math.Clamp(frame, 0, p.TotalFrames - 1);
				}
			}
		}
	}

	[Inline]
	private void RemoveParticleAt(int index)
	{
		if (index < 0 || index >= mActiveCount)
			return;

		mActiveCount--;
		if (index < mActiveCount)
			mParticlePool[index] = mParticlePool[mActiveCount];
	}

	private void EmitParticles(float deltaTime)
	{
		// Continuous emission
		if (mConfig.EmissionRate > 0)
		{
			mEmissionAccumulator += mConfig.EmissionRate * deltaTime;

			while (mEmissionAccumulator >= 1.0f && mActiveCount < mMaxParticles)
			{
				EmitParticle();
				mEmissionAccumulator -= 1.0f;
			}
		}

		// Burst emission
		if (mConfig.BurstCount > 0 && mConfig.BurstInterval > 0)
		{
			mBurstAccumulator += deltaTime;
			if (mBurstAccumulator >= mConfig.BurstInterval)
			{
				Burst(mConfig.BurstCount);
				mBurstAccumulator = 0;
			}
		}
	}

	private void EmitParticle()
	{
		Particle p = .();
		p.RandomSeed = (uint32)mRandom.Next(0, int32.MaxValue);

		// Calculate spawn position and direction
		Vector3 spawnOffset, spawnDirection;
		CalculateEmissionPoint(out spawnOffset, out spawnDirection);

		p.Position = mPosition + spawnOffset;

		// Initial velocity
		float speed = mConfig.InitialSpeed.Evaluate(mRandom);
		p.Velocity = spawnDirection * speed;
		p.StartVelocity = p.Velocity;

		if (mConfig.InheritVelocity)
			p.Velocity += mVelocity * mConfig.InheritVelocityFactor;

		// Initial size
		float size = mConfig.InitialSize.Evaluate(mRandom);
		p.Size = .(size, size);
		p.StartSize = p.Size;

		// Initial color
		p.Color = mConfig.StartColor.Evaluate(mRandom);
		p.StartColor = p.Color;

		// Rotation
		p.Rotation = mConfig.InitialRotation.Evaluate(mRandom);
		p.RotationSpeed = mConfig.InitialRotationSpeed.Evaluate(mRandom);

		// Lifetime
		p.MaxLife = mConfig.Lifetime.Evaluate(mRandom);
		p.Life = p.MaxLife;

		// Texture animation
		int32 totalFrames = mConfig.TextureSheetRows * mConfig.TextureSheetColumns;
		p.TotalFrames = (uint16)totalFrames;
		p.TextureFrame = (uint16)mConfig.StartFrame;

		// Add to pool
		if (mActiveCount < mMaxParticles)
		{
			mParticlePool[mActiveCount] = p;
			mActiveCount++;
		}
	}

	private void CalculateEmissionPoint(out Vector3 offset, out Vector3 direction)
	{
		offset = .Zero;
		direction = .(0, 1, 0);

		let shape = mConfig.EmissionShape;

		switch (shape.Type)
		{
		case .Point:
			offset = .Zero;
			if (shape.RandomizeDirection)
				direction = RandomDirection();

		case .Sphere:
			let radius = shape.Size.X;
			direction = RandomDirection();
			if (shape.EmitFromSurface)
				offset = direction * radius;
			else
				offset = direction * (float)mRandom.NextDouble() * radius;

		case .Hemisphere:
			let hRadius = shape.Size.X;
			direction = RandomHemisphereDirection();
			if (shape.EmitFromSurface)
				offset = direction * hRadius;
			else
				offset = direction * (float)mRandom.NextDouble() * hRadius;

		case .Cone:
			let coneAngle = shape.ConeAngle * Math.PI_f / 180.0f;
			let coneRadius = shape.Size.X;

			float theta = (float)mRandom.NextDouble() * 2 * Math.PI_f;
			float phi = (float)mRandom.NextDouble() * coneAngle;

			direction = .(
				Math.Sin(phi) * Math.Cos(theta),
				Math.Cos(phi),
				Math.Sin(phi) * Math.Sin(theta)
			);

			if (coneRadius > 0)
			{
				float r = (float)mRandom.NextDouble() * coneRadius;
				offset = .(r * Math.Cos(theta), 0, r * Math.Sin(theta));
			}

		case .Box:
			let halfExtents = shape.Size;
			offset = .(
				RandomRange(-halfExtents.X, halfExtents.X),
				RandomRange(-halfExtents.Y, halfExtents.Y),
				RandomRange(-halfExtents.Z, halfExtents.Z)
			);
			if (shape.RandomizeDirection)
				direction = RandomDirection();

		case .Circle:
			let circleRadius = shape.Size.X;
			float angle = (float)mRandom.NextDouble() * shape.Arc * Math.PI_f / 180.0f;
			float r = shape.EmitFromSurface ? circleRadius : (float)mRandom.NextDouble() * circleRadius;
			offset = .(Math.Cos(angle) * r, 0, Math.Sin(angle) * r);
		}
	}

	private float RandomRange(float min, float max) =>
		min + (float)mRandom.NextDouble() * (max - min);

	private Vector3 RandomDirection()
	{
		float theta = (float)mRandom.NextDouble() * 2 * Math.PI_f;
		float phi = Math.Acos(2 * (float)mRandom.NextDouble() - 1);
		return .(
			Math.Sin(phi) * Math.Cos(theta),
			Math.Cos(phi),
			Math.Sin(phi) * Math.Sin(theta)
		);
	}

	private Vector3 RandomHemisphereDirection()
	{
		float theta = (float)mRandom.NextDouble() * 2 * Math.PI_f;
		float phi = Math.Acos((float)mRandom.NextDouble());
		return .(
			Math.Sin(phi) * Math.Cos(theta),
			Math.Cos(phi),
			Math.Sin(phi) * Math.Sin(theta)
		);
	}

	/// Emits a burst of particles.
	public void Burst(int32 count)
	{
		int32 maxToEmit = Math.Min(count, mMaxParticles - mActiveCount);
		for (int32 i = 0; i < maxToEmit; i++)
			EmitParticle();
	}

	/// Clears all particles.
	public void Clear()
	{
		mActiveCount = 0;
		mEmissionAccumulator = 0;
		mBurstAccumulator = 0;
	}

	/// Sorts particles back-to-front by distance from camera.
	public void SortByDistance()
	{
		if (mActiveCount < 2)
			return;

		let camPos = CameraPosition;
		Span<Particle> activeParticles = .(mParticlePool.Ptr, mActiveCount);
		activeParticles.Sort(scope (a, b) =>
		{
			float distA = (a.Position - camPos).LengthSquared();
			float distB = (b.Position - camPos).LengthSquared();
			return distB <=> distA; // Back-to-front
		});
	}

	/// Applies force fields to all active particles.
	public void ApplyForceFields(Span<ForceFieldProxy> forceFields, float deltaTime)
	{
		if (forceFields.Length == 0 || mActiveCount == 0)
			return;

		for (int i = 0; i < mActiveCount; i++)
		{
			ref Particle p = ref mParticlePool[i];

			for (let field in forceFields)
			{
				// Check if force field is active and affects this emitter's layer
				if (!field.IsActive || (field.LayerMask & mLayerMask) == 0)
					continue;

				// Calculate force for this particle
				Vector3 force = CalculateForce(ref p, field);
				p.Velocity += force * deltaTime;
			}
		}
	}

	/// Calculates force from a single force field on a particle.
	private Vector3 CalculateForce(ref Particle p, ForceFieldProxy field)
	{
		Vector3 toField = field.Position - p.Position;
		float distance = toField.Length();

		// Check radius
		if (distance >= field.Radius)
			return .Zero;

		float falloff = field.GetFalloff(distance);
		float strength = field.Strength;

		// Invert flag
		if ((field.Flags & .Invert) != 0)
			strength = -strength;

		switch (field.Type)
		{
		case .Wind:
			return CalculateWindForce(field, falloff, strength);

		case .Point:
			return CalculatePointForce(toField, distance, falloff, strength);

		case .Vortex:
			return CalculateVortexForce(toField, field.VortexAxis, distance, falloff, strength);

		case .Turbulence:
			return CalculateTurbulenceForce(p.Position, field, falloff);

		case .Drag:
			return CalculateDragForce(ref p, falloff, strength);
		}
	}

	/// Calculates directional wind force.
	private Vector3 CalculateWindForce(ForceFieldProxy field, float falloff, float strength)
	{
		return Vector3.Normalize(field.Direction) * strength * falloff;
	}

	/// Calculates radial point force (attraction/repulsion).
	private Vector3 CalculatePointForce(Vector3 toField, float distance, float falloff, float strength)
	{
		if (distance < 0.001f)
			return .Zero;

		Vector3 direction = toField / distance;
		return direction * strength * falloff;
	}

	/// Calculates vortex force (rotation around axis).
	private Vector3 CalculateVortexForce(Vector3 toField, Vector3 axis, float distance, float falloff, float strength)
	{
		if (distance < 0.001f)
			return .Zero;

		// Project position onto the plane perpendicular to vortex axis
		Vector3 normalizedAxis = Vector3.Normalize(axis);
		float axisComponent = Vector3.Dot(toField, normalizedAxis);
		Vector3 radialComponent = toField - normalizedAxis * axisComponent;

		float radialDistance = radialComponent.Length();
		if (radialDistance < 0.001f)
			return .Zero;

		// Tangent direction (perpendicular to both axis and radial)
		Vector3 tangent = Vector3.Cross(normalizedAxis, radialComponent / radialDistance);
		return tangent * strength * falloff;
	}

	/// Calculates turbulence force using simple noise.
	private Vector3 CalculateTurbulenceForce(Vector3 position, ForceFieldProxy field, float falloff)
	{
		// Simple pseudo-noise based on position and time
		float freq = field.NoiseFrequency;
		float amp = field.NoiseAmplitude * field.Strength;
		float time = mTotalTime;

		// Generate 3D noise-like values using trig functions
		float px = position.X * freq + time;
		float py = position.Y * freq + time * 0.8f;
		float pz = position.Z * freq + time * 1.2f;

		Vector3 noise = .(
			Math.Sin(px * 1.7f) * Math.Cos(py * 2.3f) + Math.Sin(pz * 1.1f),
			Math.Cos(px * 1.3f) * Math.Sin(pz * 1.9f) + Math.Cos(py * 2.1f),
			Math.Sin(py * 1.5f) * Math.Cos(px * 2.7f) + Math.Sin(pz * 1.3f)
		);

		return noise * amp * falloff;
	}

	/// Calculates drag force (velocity-relative).
	private Vector3 CalculateDragForce(ref Particle p, float falloff, float strength)
	{
		float speed = p.Velocity.Length();
		if (speed < 0.001f)
			return .Zero;

		// Drag opposes velocity, proportional to speed
		Vector3 dragDirection = -p.Velocity / speed;
		return dragDirection * speed * strength * falloff;
	}

	/// Gets read-only access to active particles.
	public Span<Particle> Particles => .(mParticlePool.Ptr, mActiveCount);

	/// Writes particle vertices to a span. Returns number of particles written.
	public int WriteVertices(Span<ParticleVertex> output)
	{
		int count = Math.Min(mActiveCount, output.Length);

		int32 columns = mConfig.TextureSheetColumns;
		int32 rows = mConfig.TextureSheetRows;

		for (int i = 0; i < count; i++)
		{
			ref Particle p = ref mParticlePool[i];

			int32 frame = p.TextureFrame;
			int32 col = columns > 0 ? frame % columns : 0;
			int32 row = columns > 0 ? frame / columns : 0;
			float frameWidth = columns > 0 ? 1.0f / columns : 1.0f;
			float frameHeight = rows > 0 ? 1.0f / rows : 1.0f;

			Vector2 texOffset = .(col * frameWidth, row * frameHeight);
			Vector2 texScale = .(frameWidth, frameHeight);
			Vector2 velocity2D = .(p.Velocity.X, p.Velocity.Y);

			output[i] = .(p.Position, p.Size, p.Color, p.Rotation, texOffset, texScale, velocity2D);
		}

		return count;
	}

	public void Dispose()
	{
		// Resources cleaned up by destructor
	}
}
