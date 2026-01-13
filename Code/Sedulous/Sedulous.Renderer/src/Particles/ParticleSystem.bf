namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// A single particle in the system.
struct Particle
{
	// Core state
	public Vector3 Position;
	public Vector3 Velocity;
	public Vector2 Size;
	public Color Color;
	public float Rotation;
	public float RotationSpeed;
	public float Life;      // Current life remaining
	public float MaxLife;   // Initial life

	// Initial values (for curve evaluation)
	public Vector3 StartVelocity;
	public Vector2 StartSize;
	public Color StartColor;

	// Texture animation
	public uint16 TextureFrame;
	public uint16 TotalFrames;

	// Per-particle random seed
	public uint32 RandomSeed;

	public bool IsAlive => Life > 0;

	/// Ratio of life remaining (1 = just spawned, 0 = dead)
	public float LifeRatio => MaxLife > 0 ? Life / MaxLife : 0;

	/// Normalized age (0 = just spawned, 1 = dead)
	public float NormalizedAge => MaxLife > 0 ? 1.0f - (Life / MaxLife) : 1;
}

/// CPU-driven particle system with advanced features.
class ParticleSystem
{
	private IDevice mDevice;
	private List<Particle> mParticles = new .() ~ delete _;
	private IBuffer mVertexBuffer;
	private IBuffer mIndexBuffer;

	private ParticleEmitterConfig mConfig ~ if (mOwnsConfig) delete _;
	private bool mOwnsConfig = false;
	private Vector3 mEmitterPosition;
	private Vector3 mEmitterVelocity; // For velocity inheritance
	private float mEmissionAccumulator = 0;
	private float mBurstAccumulator = 0;
	private int32 mMaxParticles;
	private Random mRandom = new .() ~ delete _;
	private bool mEmitting = true;

	public const int32 DEFAULT_MAX_PARTICLES = 10000;

	// ==================== Properties ====================

	public int32 ParticleCount => (int32)mParticles.Count;
	public int32 MaxParticles => mMaxParticles;
	public bool IsEmitting { get => mEmitting; set => mEmitting = value; }
	public Vector3 Position { get => mEmitterPosition; set => mEmitterPosition = value; }
	public Vector3 Velocity { get => mEmitterVelocity; set => mEmitterVelocity = value; }
	public ParticleEmitterConfig Config => mConfig;

	public IBuffer VertexBuffer => mVertexBuffer;
	public IBuffer IndexBuffer => mIndexBuffer;
	public uint32 IndexCount => (uint32)(mParticles.Count * 6);

	// ==================== Constructor ====================

	public this(IDevice device, int32 maxParticles = DEFAULT_MAX_PARTICLES)
	{
		mDevice = device;
		mMaxParticles = maxParticles;
		mConfig = new ParticleEmitterConfig();
		mOwnsConfig = true;
		mEmitterPosition = .Zero;
		mEmitterVelocity = .Zero;

		CreateBuffers();
	}

	public this(IDevice device, ParticleEmitterConfig config, int32 maxParticles = DEFAULT_MAX_PARTICLES)
	{
		mDevice = device;
		mMaxParticles = maxParticles;
		mConfig = config;
		mOwnsConfig = false;
		mEmitterPosition = .Zero;
		mEmitterVelocity = .Zero;

		CreateBuffers();
	}

	public ~this()
	{
		if (mVertexBuffer != null) delete mVertexBuffer;
		if (mIndexBuffer != null) delete mIndexBuffer;
	}

	// ==================== Configuration ====================

	/// Sets the emitter configuration (takes ownership if ownConfig is true).
	public void SetConfig(ParticleEmitterConfig config, bool ownConfig = false)
	{
		if (mOwnsConfig && mConfig != null)
			delete mConfig;
		mConfig = config;
		mOwnsConfig = ownConfig;
	}

	// ==================== Buffer Management ====================

	private void CreateBuffers()
	{
		// Vertex buffer
		let vertexSize = (uint64)(sizeof(ParticleVertex) * mMaxParticles);
		BufferDescriptor vertexDesc = .(vertexSize, .Vertex, .Upload);
		if (mDevice.CreateBuffer(&vertexDesc) case .Ok(let vertBuf))
			mVertexBuffer = vertBuf;

		// Index buffer for quads
		let indexCount = mMaxParticles * 6;
		let indexSize = (uint64)(sizeof(uint16) * indexCount);
		BufferDescriptor indexDesc = .(indexSize, .Index, .Upload);
		if (mDevice.CreateBuffer(&indexDesc) case .Ok(let idxBuf))
		{
			mIndexBuffer = idxBuf;

			uint16[] indices = new uint16[indexCount];
			defer delete indices;

			for (int32 i = 0; i < mMaxParticles; i++)
			{
				int32 baseVertex = i * 4;
				int32 baseIndex = i * 6;
				indices[baseIndex + 0] = (uint16)(baseVertex + 0);
				indices[baseIndex + 1] = (uint16)(baseVertex + 1);
				indices[baseIndex + 2] = (uint16)(baseVertex + 2);
				indices[baseIndex + 3] = (uint16)(baseVertex + 2);
				indices[baseIndex + 4] = (uint16)(baseVertex + 1);
				indices[baseIndex + 5] = (uint16)(baseVertex + 3);
			}

			Span<uint8> data = .((uint8*)indices.Ptr, (int)indexSize);
			mDevice.Queue.WriteBuffer(mIndexBuffer, 0, data);
		}
	}

	// ==================== Update ====================

	/// Updates particles and emits new ones.
	public void Update(float deltaTime)
	{
		if (mConfig == null)
			return;

		// Update existing particles
		UpdateParticles(deltaTime);

		// Emit new particles
		if (mEmitting && mParticles.Count < mMaxParticles)
		{
			EmitParticles(deltaTime);
		}
	}

	private void UpdateParticles(float deltaTime)
	{
		for (int i = mParticles.Count - 1; i >= 0; i--)
		{
			ref Particle p = ref mParticles[i];

			p.Life -= deltaTime;
			if (p.Life <= 0)
			{
				mParticles.RemoveAtFast(i);
				continue;
			}

			float age = p.NormalizedAge;

			// Apply gravity and drag
			p.Velocity += mConfig.Gravity * deltaTime;
			if (mConfig.Drag > 0)
			{
				p.Velocity *= (1.0f - mConfig.Drag * deltaTime);
			}

			// Apply speed over lifetime curve
			if (mConfig.SpeedOverLifetime != null && mConfig.SpeedOverLifetime.HasKeys)
			{
				float speedMult = mConfig.SpeedOverLifetime.Evaluate(age);
				float currentSpeed = p.Velocity.Length();
				if (currentSpeed > 0.0001f)
				{
					Vector3 dir = p.Velocity / currentSpeed;
					float startSpeed = p.StartVelocity.Length();
					p.Velocity = dir * (startSpeed * speedMult);
				}
			}

			// Update position
			p.Position += p.Velocity * deltaTime;
			p.Rotation += p.RotationSpeed * deltaTime;

			// Apply size over lifetime
			if (mConfig.SizeOverLifetime != null && mConfig.SizeOverLifetime.HasKeys)
			{
				float sizeMult = mConfig.SizeOverLifetime.Evaluate(age);
				p.Size = p.StartSize * sizeMult;
			}

			// Apply color over lifetime
			if (mConfig.ColorOverLifetime != null && mConfig.ColorOverLifetime.HasKeys)
			{
				p.Color = mConfig.ColorOverLifetime.Evaluate(age);
			}
			else
			{
				// Simple linear interpolation between start and end color
				p.Color = mConfig.StartColor.Lerp(age).Interpolate(mConfig.EndColor.Lerp(age), age);
			}

			// Apply alpha over lifetime
			if (mConfig.AlphaOverLifetime != null && mConfig.AlphaOverLifetime.HasKeys)
			{
				float alpha = mConfig.AlphaOverLifetime.Evaluate(age);
				p.Color = .(p.Color.R, p.Color.G, p.Color.B, (uint8)(alpha * 255));
			}

			// Update texture animation frame
			if (mConfig.AnimateTextureSheet && p.TotalFrames > 1)
			{
				if (mConfig.AnimationFrameRate > 0)
				{
					// Fixed frame rate animation
					float elapsedTime = p.MaxLife - p.Life;
					int32 frame = (int32)(elapsedTime * mConfig.AnimationFrameRate) % p.TotalFrames;
					p.TextureFrame = (uint16)frame;
				}
				else
				{
					// Spread animation over lifetime
					int32 frame = (int32)(age * (p.TotalFrames - 1));
					p.TextureFrame = (uint16)Math.Clamp(frame, 0, p.TotalFrames - 1);
				}
			}
		}
	}

	private void EmitParticles(float deltaTime)
	{
		// Continuous emission
		if (mConfig.EmissionRate > 0)
		{
			mEmissionAccumulator += mConfig.EmissionRate * deltaTime;

			while (mEmissionAccumulator >= 1.0f && mParticles.Count < mMaxParticles)
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

	// ==================== Emission ====================

	private void EmitParticle()
	{
		Particle p = .();

		// Generate random seed for this particle
		p.RandomSeed = (uint32)mRandom.Next(0, int32.MaxValue);

		// Calculate spawn position and direction from emission shape
		Vector3 spawnOffset;
		Vector3 spawnDirection;
		CalculateEmissionPoint(out spawnOffset, out spawnDirection);

		p.Position = mEmitterPosition + spawnOffset;

		// Initial velocity
		float speed = mConfig.InitialSpeed.Evaluate(mRandom);
		p.Velocity = spawnDirection * speed;
		p.StartVelocity = p.Velocity;

		// Inherit emitter velocity
		if (mConfig.InheritVelocity)
		{
			p.Velocity += mEmitterVelocity * mConfig.InheritVelocityFactor;
		}

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

		mParticles.Add(p);
	}

	private void CalculateEmissionPoint(out Vector3 offset, out Vector3 direction)
	{
		offset = .Zero;
		direction = .(0, 1, 0); // Default up

		let shape = mConfig.EmissionShape;

		switch (shape.Type)
		{
		case .Point:
			offset = .Zero;
			if (shape.RandomizeDirection)
				direction = RandomDirection();
			else
				direction = .(0, 1, 0);

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

			// Random angle within cone
			float theta = (float)mRandom.NextDouble() * 2 * Math.PI_f;
			float phi = (float)mRandom.NextDouble() * coneAngle;

			direction = .(
				Math.Sin(phi) * Math.Cos(theta),
				Math.Cos(phi),
				Math.Sin(phi) * Math.Sin(theta)
			);

			// Offset within base radius
			if (coneRadius > 0)
			{
				float r = (float)mRandom.NextDouble() * coneRadius;
				offset = .(
					r * Math.Cos(theta),
					0,
					r * Math.Sin(theta)
				);
			}

		case .Box:
			let halfExtents = shape.Size;
			if (shape.EmitFromSurface)
			{
				// Pick a random face
				int face = mRandom.Next(0, 6);
				offset = RandomBoxSurfacePoint(halfExtents, face);
			}
			else
			{
				offset = .(
					RandomRange(-halfExtents.X, halfExtents.X),
					RandomRange(-halfExtents.Y, halfExtents.Y),
					RandomRange(-halfExtents.Z, halfExtents.Z)
				);
			}
			if (shape.RandomizeDirection)
				direction = RandomDirection();

		case .Circle:
			let circleRadius = shape.Size.X;
			float angle = (float)mRandom.NextDouble() * shape.Arc * Math.PI_f / 180.0f;
			float r = shape.EmitFromSurface ? circleRadius : (float)mRandom.NextDouble() * circleRadius;
			offset = .(Math.Cos(angle) * r, 0, Math.Sin(angle) * r);
			direction = .(0, 1, 0);

		case .Edge:
			let edgeLength = shape.Size.X;
			float t = (float)mRandom.NextDouble() - 0.5f;
			offset = .(t * edgeLength, 0, 0);
			direction = .(0, 1, 0);

		case .Mesh:
			// Future: mesh surface emission
			offset = .Zero;
			direction = .(0, 1, 0);
		}
	}

	// ==================== Helper Methods ====================

	private float RandomRange(float min, float max)
	{
		return min + (float)mRandom.NextDouble() * (max - min);
	}

	private Vector3 RandomDirection()
	{
		// Uniform distribution on sphere
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
		float phi = Math.Acos((float)mRandom.NextDouble()); // Only upper hemisphere
		return .(
			Math.Sin(phi) * Math.Cos(theta),
			Math.Cos(phi),
			Math.Sin(phi) * Math.Sin(theta)
		);
	}

	private Vector3 RandomBoxSurfacePoint(Vector3 halfExtents, int face)
	{
		float u = RandomRange(-1, 1);
		float v = RandomRange(-1, 1);

		switch (face)
		{
		case 0: return .(halfExtents.X, u * halfExtents.Y, v * halfExtents.Z);   // +X
		case 1: return .(-halfExtents.X, u * halfExtents.Y, v * halfExtents.Z);  // -X
		case 2: return .(u * halfExtents.X, halfExtents.Y, v * halfExtents.Z);   // +Y
		case 3: return .(u * halfExtents.X, -halfExtents.Y, v * halfExtents.Z);  // -Y
		case 4: return .(u * halfExtents.X, v * halfExtents.Y, halfExtents.Z);   // +Z
		default: return .(u * halfExtents.X, v * halfExtents.Y, -halfExtents.Z); // -Z
		}
	}

	// ==================== GPU Upload ====================

	/// Uploads particle data to GPU.
	public void Upload()
	{
		if (mParticles.Count == 0)
			return;

		ParticleVertex[] vertices = new ParticleVertex[mParticles.Count];
		defer delete vertices;

		int32 columns = mConfig.TextureSheetColumns;
		int32 rows = mConfig.TextureSheetRows;

		for (int i = 0; i < mParticles.Count; i++)
		{
			ref Particle p = ref mParticles[i];

			// Calculate texture atlas frame
			int32 frame = p.TextureFrame;
			int32 col = columns > 0 ? frame % columns : 0;
			int32 row = columns > 0 ? frame / columns : 0;
			float frameWidth = columns > 0 ? 1.0f / columns : 1.0f;
			float frameHeight = rows > 0 ? 1.0f / rows : 1.0f;

			Vector2 texOffset = .(col * frameWidth, row * frameHeight);
			Vector2 texScale = .(frameWidth, frameHeight);

			// Calculate velocity in view space for stretched billboards
			// Note: This would ideally be done with the actual view matrix, but we'll
			// pass world-space velocity and let the shader handle it
			Vector2 velocity2D = .(p.Velocity.X, p.Velocity.Y);

			vertices[i] = .(
				p.Position,
				p.Size,
				p.Color,
				p.Rotation,
				texOffset,
				texScale,
				velocity2D
			);
		}

		let dataSize = (uint64)(sizeof(ParticleVertex) * mParticles.Count);
		Span<uint8> data = .((uint8*)vertices.Ptr, (int)dataSize);
		mDevice.Queue.WriteBuffer(mVertexBuffer, 0, data);
	}

	// ==================== Public Control ====================

	/// Clears all particles.
	public void Clear()
	{
		mParticles.Clear();
		mEmissionAccumulator = 0;
		mBurstAccumulator = 0;
	}

	/// Emits a burst of particles.
	public void Burst(int32 count)
	{
		int32 maxToEmit = Math.Min(count, mMaxParticles - (int32)mParticles.Count);
		for (int32 i = 0; i < maxToEmit; i++)
		{
			EmitParticle();
		}
	}

	/// Gets read-only access to the particle list.
	public Span<Particle> Particles => mParticles;
}
