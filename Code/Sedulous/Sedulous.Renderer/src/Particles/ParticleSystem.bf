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

	// Per-particle trail index (-1 = no trail)
	public int16 TrailIndex;

	// Per-particle random seed
	public uint32 RandomSeed;

	public bool IsAlive => Life > 0;

	/// Whether this particle has an associated trail.
	public bool HasTrail => TrailIndex >= 0;

	/// Ratio of life remaining (1 = just spawned, 0 = dead)
	public float LifeRatio => MaxLife > 0 ? Life / MaxLife : 0;

	/// Normalized age (0 = just spawned, 1 = dead)
	public float NormalizedAge => MaxLife > 0 ? 1.0f - (Life / MaxLife) : 1;
}

/// CPU-driven particle system with advanced features.
class ParticleSystem
{

	private IDevice mDevice;

	// Particle pool - pre-allocated array for zero runtime allocations
	private Particle[] mParticlePool ~ delete _;
	private int32 mActiveParticleCount = 0;

	// Double-buffered vertex buffers to avoid GPU/CPU race conditions
	private IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mVertexBuffers ~ { for (var buf in _) if (buf != null) delete buf; };
	private IBuffer mIndexBuffer ~ delete _;

	private ParticleEmitterConfig mConfig ~ if (mOwnsConfig) delete _;
	private bool mOwnsConfig = false;
	private Vector3 mEmitterPosition;
	private Vector3 mEmitterVelocity; // For velocity inheritance
	private float mEmissionAccumulator = 0;
	private float mBurstAccumulator = 0;
	private float mTotalTime = 0; // For time-based effects (turbulence, etc.)
	private int32 mMaxParticles;
	private Random mRandom = new .() ~ delete _;
	private bool mEmitting = true;

	// Per-particle trail storage
	private ParticleTrail[] mTrails ~ { if (_ != null) { for (let t in _) delete t; delete _; } };
	private List<int16> mFreeTrailSlots = new .() ~ delete _;
	private int32 mMaxTrails = 0;
	private bool mTrailsEnabled = false;

	// Sub-emitter management
	private SubEmitterManager mSubEmitterManager ~ delete _;
	private List<SubEmitter> mTempSubEmitters = new .() ~ delete _;

	public const int32 DEFAULT_MAX_PARTICLES = 10000;

	// ==================== Properties ====================

	public int32 ParticleCount => mActiveParticleCount;
	public int32 MaxParticles => mMaxParticles;
	public bool IsEmitting { get => mEmitting; set => mEmitting = value; }
	public Vector3 Position { get => mEmitterPosition; set => mEmitterPosition = value; }
	public Vector3 Velocity { get => mEmitterVelocity; set => mEmitterVelocity = value; }
	public ParticleEmitterConfig Config => mConfig;

	/// Color tint applied to all particles on spawn. Used for color inheritance from parent particles.
	public Color ColorTint { get; set; } = Color.White;

	/// Camera position for distance-based sorting. Set before Upload() for proper sorting.
	public Vector3 CameraPosition { get; set; } = .Zero;

	/// Current LOD factor (0 = culled, 1 = full quality). Calculated from camera distance.
	public float LODFactor { get; private set; } = 1.0f;

	/// Whether the emitter is culled due to LOD distance.
	public bool IsCulledByLOD => LODFactor <= 0;

	/// Gets the vertex buffer for the specified frame index.
	public IBuffer GetVertexBuffer(int32 frameIndex) => mVertexBuffers[frameIndex % FrameConfig.MAX_FRAMES_IN_FLIGHT];
	public IBuffer IndexBuffer => mIndexBuffer;
	public uint32 IndexCount => (uint32)(mActiveParticleCount * 6);

	/// Whether per-particle trails are enabled.
	public bool TrailsEnabled => mTrailsEnabled;

	/// Gets the trail settings from the config.
	public TrailSettings TrailSettings => mConfig?.ParticleTrails ?? .();

	/// Gets the array of particle trails (for rendering).
	public ParticleTrail[] Trails => mTrails;

	/// Gets the number of active trails.
	public int32 ActiveTrailCount => mMaxTrails - (int32)mFreeTrailSlots.Count;

	// ==================== Constructor ====================

	public this(IDevice device, int32 maxParticles = DEFAULT_MAX_PARTICLES)
	{
		mDevice = device;
		mMaxParticles = maxParticles;
		mConfig = new ParticleEmitterConfig();
		mOwnsConfig = true;
		mEmitterPosition = .Zero;
		mEmitterVelocity = .Zero;

		// Pre-allocate particle pool for zero runtime allocations
		mParticlePool = new Particle[maxParticles];
		mActiveParticleCount = 0;

		CreateBuffers();
		InitializeTrails();
		InitializeSubEmitters();
	}

	public this(IDevice device, ParticleEmitterConfig config, int32 maxParticles = DEFAULT_MAX_PARTICLES)
	{
		mDevice = device;
		mMaxParticles = maxParticles;
		mConfig = config;
		mOwnsConfig = false;
		mEmitterPosition = .Zero;
		mEmitterVelocity = .Zero;

		// Pre-allocate particle pool for zero runtime allocations
		mParticlePool = new Particle[maxParticles];
		mActiveParticleCount = 0;

		CreateBuffers();
		InitializeTrails();
		InitializeSubEmitters();
	}

	public ~this()
	{
		// Wait for GPU to finish using buffers before deleting them.
		// Even with double buffering, we need to ensure the GPU is done with all
		// in-flight frames before destroying the buffers during cleanup.
		// A proper deferred deletion queue would be more efficient.
		bool hasBuffers = mIndexBuffer != null;
		if (!hasBuffers)
		{
			for (let buf in mVertexBuffers)
				if (buf != null) { hasBuffers = true; break; }
		}
		if (hasBuffers)
			mDevice.WaitIdle();

		// Note: mVertexBuffers and mIndexBuffer are deleted by field destructors
	}

	// ==================== Configuration ====================

	/// Sets the emitter configuration (takes ownership if ownConfig is true).
	public void SetConfig(ParticleEmitterConfig config, bool ownConfig = false)
	{
		if (mOwnsConfig && mConfig != null)
			delete mConfig;
		mConfig = config;
		mOwnsConfig = ownConfig;

		// Reinitialize trails if config changed
		InitializeTrails();
		InitializeSubEmitters();
	}

	// ==================== Buffer Management ====================

	private void CreateBuffers()
	{
		// Create double-buffered vertex buffers (one per frame in flight)
		let vertexSize = (uint64)(sizeof(ParticleVertex) * mMaxParticles);
		BufferDescriptor vertexDesc = .(vertexSize, .Vertex, .Upload);
		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (mDevice.CreateBuffer(&vertexDesc) case .Ok(let vertBuf))
				mVertexBuffers[i] = vertBuf;
		}

		// Index buffer for quads (shared across frames - never changes)
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

		mTotalTime += deltaTime;

		// Calculate LOD factor based on camera distance
		CalculateLOD();

		// Update existing particles (even if culled, so they die naturally)
		UpdateParticles(deltaTime);

		// Emit new particles (respects LOD factor)
		if (mEmitting && mActiveParticleCount < mMaxParticles && LODFactor > 0)
		{
			EmitParticles(deltaTime);
		}

		// Update particle trails
		if (mTrailsEnabled)
		{
			UpdateParticleTrails();
		}

		// Update sub-emitters
		if (mSubEmitterManager != null)
		{
			mSubEmitterManager.Update(deltaTime);
		}
	}

	/// Calculates the LOD factor based on distance from camera.
	private void CalculateLOD()
	{
		if (mConfig == null || !mConfig.EnableLOD)
		{
			LODFactor = 1.0f;
			return;
		}

		float distance = (mEmitterPosition - CameraPosition).Length();

		if (distance <= mConfig.LODStartDistance)
		{
			// Full quality
			LODFactor = 1.0f;
		}
		else if (distance >= mConfig.LODEndDistance)
		{
			// Fully culled
			LODFactor = 0.0f;
		}
		else
		{
			// Linear interpolation between start and end distance
			float t = (distance - mConfig.LODStartDistance) / (mConfig.LODEndDistance - mConfig.LODStartDistance);
			// LODFactor goes from 1.0 at start to LODMinEmissionRate at end
			LODFactor = 1.0f - t * (1.0f - mConfig.LODMinEmissionRate);
		}
	}

	/// Removes a particle from the pool by swapping with the last active particle.
	/// This is O(1) and avoids shifting the array.
	[Inline]
	private void RemoveParticleAt(int index)
	{
		if (index < 0 || index >= mActiveParticleCount)
			return;

		// Swap with last active particle and decrement count
		mActiveParticleCount--;
		if (index < mActiveParticleCount)
		{
			mParticlePool[index] = mParticlePool[mActiveParticleCount];
		}
	}

	private void UpdateParticles(float deltaTime)
	{
		for (int i = mActiveParticleCount - 1; i >= 0; i--)
		{
			ref Particle p = ref mParticlePool[i];

			p.Life -= deltaTime;
			if (p.Life <= 0)
			{
				// Trigger OnDeath sub-emitters before removing particle
				TriggerSubEmitters(.OnDeath, p.Position, p.Velocity, p.Color);

				// Free associated trail before removing particle
				if (p.HasTrail)
					FreeTrail(p.TrailIndex);

				RemoveParticleAt(i);
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

			// Execute particle modules (turbulence, vortex, attractors, etc.)
			if (mConfig.Modules != null)
			{
				for (let module in mConfig.Modules)
				{
					module.OnParticleUpdate(ref p, deltaTime, mConfig, mTotalTime);
				}

				// Check if module killed the particle
				if (p.Life <= 0)
				{
					// Trigger OnDeath sub-emitters
					TriggerSubEmitters(.OnDeath, p.Position, p.Velocity, p.Color);

					// Free associated trail
					if (p.HasTrail)
						FreeTrail(p.TrailIndex);

					RemoveParticleAt(i);
					continue;
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
		// Apply LOD factor to emission rate
		float effectiveRate = mConfig.EmissionRate * LODFactor;

		// Continuous emission
		if (effectiveRate > 0)
		{
			mEmissionAccumulator += effectiveRate * deltaTime;

			while (mEmissionAccumulator >= 1.0f && mActiveParticleCount < mMaxParticles)
			{
				EmitParticle();
				mEmissionAccumulator -= 1.0f;
			}
		}

		// Burst emission (also scaled by LOD)
		if (mConfig.BurstCount > 0 && mConfig.BurstInterval > 0)
		{
			mBurstAccumulator += deltaTime;
			if (mBurstAccumulator >= mConfig.BurstInterval)
			{
				// Scale burst count by LOD factor
				int32 effectiveBurst = (int32)Math.Ceiling(mConfig.BurstCount * LODFactor);
				if (effectiveBurst > 0)
					Burst(effectiveBurst);
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

		// Initial color (apply tint for inherited colors)
		p.Color = mConfig.StartColor.Evaluate(mRandom);
		if (ColorTint != Color.White)
		{
			// Multiply RGB components, keep alpha from particle
			p.Color = Color(
				(uint8)((p.Color.R * ColorTint.R) / 255),
				(uint8)((p.Color.G * ColorTint.G) / 255),
				(uint8)((p.Color.B * ColorTint.B) / 255),
				p.Color.A
			);
		}
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

		// Allocate trail if trails are enabled
		p.TrailIndex = mTrailsEnabled ? AllocateTrail() : -1;

		// Call module spawn callbacks
		if (mConfig.Modules != null)
		{
			for (let module in mConfig.Modules)
			{
				module.OnParticleSpawn(ref p, mConfig, mRandom);
			}
		}

		// Add particle to pool
		if (mActiveParticleCount < mMaxParticles)
		{
			mParticlePool[mActiveParticleCount] = p;
			mActiveParticleCount++;

			// Trigger OnBirth sub-emitters after particle is fully initialized
			TriggerSubEmitters(.OnBirth, p.Position, p.Velocity, p.Color);
		}
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

	/// Uploads particle data to GPU for the specified frame.
	/// Each frame should use a different buffer to avoid GPU/CPU race conditions.
	public void Upload(int32 frameIndex)
	{
		// Sort particles if enabled (only for alpha blend, additive is order-independent)
		if (mConfig != null && mConfig.SortParticles && mConfig.BlendMode == .AlphaBlend)
		{
			SortParticlesByDistance();
		}

		// Upload main particle data to the frame's buffer
		UploadMainParticles(frameIndex);

		// Upload sub-emitter particles
		if (mSubEmitterManager != null)
		{
			mSubEmitterManager.Upload(frameIndex);
		}
	}

	/// Sorts particles back-to-front by distance from camera.
	/// This is necessary for correct alpha blending.
	private void SortParticlesByDistance()
	{
		if (mActiveParticleCount < 2)
			return;

		let camPos = CameraPosition;

		// Sort using squared distance (avoids sqrt)
		// Use Span to sort the active portion of the pool
		Span<Particle> activeParticles = .(mParticlePool.Ptr, mActiveParticleCount);
		activeParticles.Sort(scope (a, b) =>
		{
			float distA = (a.Position - camPos).LengthSquared();
			float distB = (b.Position - camPos).LengthSquared();
			// Back-to-front: larger distance first
			return distB <=> distA;
		});
	}

	/// Uploads main particle system data to GPU for the specified frame.
	private void UploadMainParticles(int32 frameIndex)
	{
		if (mActiveParticleCount == 0)
			return;

		let buffer = mVertexBuffers[frameIndex % FrameConfig.MAX_FRAMES_IN_FLIGHT];
		if (buffer == null)
			return;

		ParticleVertex[] vertices = new ParticleVertex[mActiveParticleCount];
		defer delete vertices;

		int32 columns = mConfig.TextureSheetColumns;
		int32 rows = mConfig.TextureSheetRows;

		for (int i = 0; i < mActiveParticleCount; i++)
		{
			ref Particle p = ref mParticlePool[i];

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

		let dataSize = (uint64)(sizeof(ParticleVertex) * mActiveParticleCount);
		Span<uint8> data = .((uint8*)vertices.Ptr, (int)dataSize);
		mDevice.Queue.WriteBuffer(buffer, 0, data);
	}

	// ==================== Public Control ====================

	/// Clears all particles.
	public void Clear()
	{
		// Free all trails associated with particles
		for (int i = 0; i < mActiveParticleCount; i++)
		{
			if (mParticlePool[i].HasTrail)
				FreeTrail(mParticlePool[i].TrailIndex);
		}

		mActiveParticleCount = 0;
		mEmissionAccumulator = 0;
		mBurstAccumulator = 0;

		// Clear sub-emitters
		if (mSubEmitterManager != null)
		{
			mSubEmitterManager.Clear();
		}
	}

	/// Emits a burst of particles.
	public void Burst(int32 count)
	{
		int32 maxToEmit = Math.Min(count, mMaxParticles - mActiveParticleCount);
		for (int32 i = 0; i < maxToEmit; i++)
		{
			EmitParticle();
		}
	}

	/// Gets read-only access to the active particles.
	public Span<Particle> Particles => .(mParticlePool.Ptr, mActiveParticleCount);

	// ==================== Sub-Emitter Management ====================

	/// Initializes the sub-emitter manager.
	/// Called automatically when config changes.
	private void InitializeSubEmitters()
	{
		// Create or clear sub-emitter manager
		if (mSubEmitterManager == null)
		{
			mSubEmitterManager = new SubEmitterManager(mDevice);
		}
		else
		{
			mSubEmitterManager.Clear();
		}
	}

	/// Triggers sub-emitters for the given trigger type.
	private void TriggerSubEmitters(SubEmitterTrigger trigger, Vector3 position, Vector3 velocity, Color color)
	{
		if (mConfig == null || !mConfig.HasSubEmitters || mSubEmitterManager == null)
			return;

		// Get sub-emitters for this trigger
		mConfig.GetSubEmittersForTrigger(trigger, mTempSubEmitters);

		for (let subEmitter in mTempSubEmitters)
		{
			mSubEmitterManager.SpawnSubEmitter(subEmitter, position, velocity, color);
		}
	}

	// ==================== Trail Management ====================

	/// Initializes trail storage based on config.
	/// Called automatically when config changes.
	private void InitializeTrails()
	{
		// Clean up existing trails
		if (mTrails != null)
		{
			for (let t in mTrails)
				delete t;
			delete mTrails;
			mTrails = null;
		}
		mFreeTrailSlots.Clear();
		mMaxTrails = 0;
		mTrailsEnabled = false;

		// Check if trails are enabled in config
		if (mConfig == null || !mConfig.ParticleTrails.Enabled)
			return;

		// Allocate trail storage (one trail per potential particle)
		mMaxTrails = mMaxParticles;
		mTrails = new ParticleTrail[mMaxTrails];

		let settings = mConfig.ParticleTrails;
		for (int32 i = 0; i < mMaxTrails; i++)
		{
			mTrails[i] = new ParticleTrail(settings.MaxPoints);
			mTrails[i].MinVertexDistance = settings.MinVertexDistance;
			mFreeTrailSlots.Add((int16)i);
		}

		mTrailsEnabled = true;
	}

	/// Allocates a trail for a particle.
	/// Returns the trail index, or -1 if no trails available.
	private int16 AllocateTrail()
	{
		if (!mTrailsEnabled || mFreeTrailSlots.Count == 0)
			return -1;

		int16 index = mFreeTrailSlots.PopBack();
		mTrails[index].Clear();
		return index;
	}

	/// Frees a trail back to the pool.
	private void FreeTrail(int16 index)
	{
		if (index < 0 || index >= mMaxTrails)
			return;

		mTrails[index].Clear();
		mFreeTrailSlots.Add(index);
	}

	/// Updates trail points for all particles with trails.
	private void UpdateParticleTrails()
	{
		if (!mTrailsEnabled || mConfig == null)
			return;

		let settings = mConfig.ParticleTrails;

		for (int i = 0; i < mActiveParticleCount; i++)
		{
			ref Particle p = ref mParticlePool[i];
			if (!p.HasTrail)
				continue;

			let trail = mTrails[p.TrailIndex];

			// Determine trail width based on particle size
			float width = settings.InheritParticleColor ? p.Size.X : settings.WidthStart;

			// Determine trail color
			Color trailColor = settings.InheritParticleColor ? p.Color : settings.TrailColor;

			// Try to add a new point
			trail.TryAddPoint(p.Position, width, trailColor, mTotalTime);

			// Remove old points
			trail.RemoveOldPoints(mTotalTime, settings.MaxAge);
		}
	}

	/// Gets a list of active trails for rendering.
	/// Only returns trails that have points.
	public void GetActiveTrails(List<ParticleTrail> outTrails)
	{
		outTrails.Clear();

		if (!mTrailsEnabled || mTrails == null)
			return;

		for (int i = 0; i < mActiveParticleCount; i++)
		{
			let particle = mParticlePool[i];
			if (particle.HasTrail && particle.TrailIndex < mMaxTrails)
			{
				let trail = mTrails[particle.TrailIndex];
				if (trail.HasPoints)
					outTrails.Add(trail);
			}
		}
	}

	/// Gets the current time for trail rendering.
	public float CurrentTime => mTotalTime;

	// ==================== Sub-Emitter Properties ====================

	/// Gets the sub-emitter manager for this particle system.
	public SubEmitterManager SubEmitters => mSubEmitterManager;

	/// Returns true if this system has active sub-emitter instances.
	public bool HasActiveSubEmitters => mSubEmitterManager != null && mSubEmitterManager.ActiveCount > 0;

	/// Gets the total particle count including sub-emitters.
	public int32 TotalParticleCount => ParticleCount + (mSubEmitterManager?.TotalParticleCount ?? 0);
}
