namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// CPU particle emitter - handles simulation, sorting, and vertex buffer upload.
/// One instance per CPU-mode particle emitter proxy.
public class CPUParticleEmitter
{
	/// Number of buffered vertex buffers for multi-frame rendering.
	public const int FrameBufferCount = RenderConfig.FrameBufferCount;

	// Particle pool
	private CPUParticle[] mParticles ~ delete _;
	private int32 mAliveCount = 0;
	private int32 mMaxParticles;

	// Emission accumulator for fractional spawning
	private float mSpawnAccumulator = 0;

	// Burst emission state
	private float mBurstTimer = 0;
	private int32 mBurstCyclesCompleted = 0;

	// Total elapsed time (for force modules)
	private float mTotalTime = 0;

	// LOD rate multiplier (1.0 = full rate, 0.0 = culled)
	private float mLODRateMultiplier = 1.0f;

	// RNG for particle spawning
	private Random mRandom = new .() ~ delete _;

	// Emission shape
	private EmissionShape mShape = .Point();

	// Double-buffered vertex buffers
	private IBuffer[FrameBufferCount] mVertexBuffers;
	private CPUParticleVertex[] mVertexData ~ delete _;

	// Death event buffer (positions where particles died this frame)
	private Vector3[] mDeathPositions ~ delete _;
	private int32 mDeathCount = 0;
	private int32 mMaxDeathEvents;

	// Sort scratch buffer
	private int32[] mSortIndices ~ delete _;
	private float[] mSortDistances ~ delete _;

	// Trail rendering state
	private ParticleTrailState[] mTrailStates ~ delete _;
	private TrailPoint[] mTrailPoints ~ delete _;
	private TrailVertex[] mTrailVertexData ~ delete _;
	private IBuffer[FrameBufferCount] mTrailVertexBuffers;
	private int32 mTrailVertexCount = 0;
	private int32 mMaxTrailPointsPerParticle = 0;
	private int32 mMaxTrailVertices = 0;
	private bool mTrailsInitialized = false;

	// Reference to device for buffer operations
	private IDevice mDevice;

	/// Gets the number of alive particles.
	public int32 GetAliveCount() => mAliveCount;

	/// Gets the vertex buffer for the given frame index.
	public IBuffer GetVertexBuffer(uint32 frameIndex)
	{
		return mVertexBuffers[frameIndex % FrameBufferCount];
	}

	/// Gets or sets the emission shape.
	public EmissionShape Shape
	{
		get => mShape;
		set { mShape = value; }
	}

	/// Gets the number of particles that died this frame.
	public int32 DeathCount => mDeathCount;

	/// Gets the positions where particles died this frame.
	/// Valid until the next Update() call.
	public Span<Vector3> DeathPositions => .(mDeathPositions.Ptr, mDeathCount);

	/// Gets the trail vertex buffer for the given frame index.
	public IBuffer GetTrailVertexBuffer(uint32 frameIndex)
	{
		return mTrailVertexBuffers[frameIndex % FrameBufferCount];
	}

	/// Gets the number of trail vertices generated this frame.
	public int32 GetTrailVertexCount() => mTrailVertexCount;

	/// Creates a new CPU particle emitter.
	public this(IDevice device, int32 maxParticles, int32 maxDeathEvents = 64)
	{
		mDevice = device;
		mMaxParticles = maxParticles;
		mMaxDeathEvents = maxDeathEvents;
		mParticles = new CPUParticle[maxParticles];
		mVertexData = new CPUParticleVertex[maxParticles];
		mDeathPositions = new Vector3[maxDeathEvents];
		mSortIndices = new int32[maxParticles];
		mSortDistances = new float[maxParticles];

		// Create vertex buffers
		for (int i = 0; i < FrameBufferCount; i++)
		{
			BufferDescriptor desc = .()
			{
				Label = "CPU Particle Vertex Buffer",
				Size = (uint64)(maxParticles * CPUParticleVertex.SizeInBytes),
				Usage = .Vertex | .CopyDst
			};

			switch (device.CreateBuffer(&desc))
			{
			case .Ok(let buf): mVertexBuffers[i] = buf;
			case .Err: // Will be null, checked at render time
			}
		}
	}

	public ~this()
	{
		for (int i = 0; i < FrameBufferCount; i++)
		{
			if (mVertexBuffers[i] != null)
				delete mVertexBuffers[i];
			if (mTrailVertexBuffers[i] != null)
				delete mTrailVertexBuffers[i];
		}
	}

	/// Updates particle simulation.
	/// cameraPos is used for LOD calculations.
	public void Update(float deltaTime, ParticleEmitterProxy* config, Vector3 cameraPos)
	{
		// Reset death events from last frame
		mDeathCount = 0;

		// Calculate LOD rate multiplier
		mLODRateMultiplier = CalculateLODMultiplier(config, cameraPos);

		// If fully culled by LOD, skip spawning but still simulate existing
		if (mLODRateMultiplier > 0 || mAliveCount > 0)
		{
			SpawnParticles(deltaTime, config);
			SimulateParticles(deltaTime, config);
		}

		// Record trail points for alive particles
		if (config.Trail.IsActive)
		{
			if (!mTrailsInitialized)
				InitializeTrails(config);
			RecordTrailPoints(config);
		}
	}

	/// Whether this emitter is culled by LOD (no alive particles and fully distant).
	public bool IsLODCulled => mLODRateMultiplier <= 0 && mAliveCount == 0;

	/// Uploads vertex data to GPU buffer for rendering.
	public void Upload(uint32 frameIndex, Vector3 cameraPos, ParticleEmitterProxy* config)
	{
		if (mAliveCount == 0)
			return;

		let bufferIdx = frameIndex % FrameBufferCount;
		let buffer = mVertexBuffers[bufferIdx];
		if (buffer == null)
			return;

		// For local-space particles, transform camera pos into local space for sorting
		var sortCameraPos = cameraPos;
		Matrix worldMatrix = default;
		if (config.SimulationSpace == .Local)
		{
			worldMatrix = config.GetWorldMatrix();
			// Transform camera into local space for distance sorting
			let invWorld = Matrix.Invert(worldMatrix);
			sortCameraPos = Vector3.Transform(cameraPos, invWorld);
		}

		// Sort if needed (back-to-front for alpha blending)
		if (config.SortParticles && config.BlendMode == .Alpha)
			SortParticles(sortCameraPos);

		// Pre-compute atlas parameters
		let useAtlas = config.AtlasColumns > 1 || config.AtlasRows > 1;
		let totalFrames = config.AtlasColumns * config.AtlasRows;
		let cellW = useAtlas ? 1.0f / (float)config.AtlasColumns : 1.0f;
		let cellH = useAtlas ? 1.0f / (float)config.AtlasRows : 1.0f;

		// Build vertex data
		for (int32 i = 0; i < mAliveCount; i++)
		{
			int32 particleIdx = config.SortParticles && config.BlendMode == .Alpha
				? mSortIndices[i]
				: i;

			ref CPUParticle p = ref mParticles[particleIdx];
			ref CPUParticleVertex v = ref mVertexData[i];

			// Transform local-space to world-space for rendering
			if (config.SimulationSpace == .Local)
				v.Position = Vector3.Transform(p.Position, worldMatrix);
			else
				v.Position = p.Position;
			v.Size = p.Size;
			v.Color = p.Color;
			v.Rotation = p.Rotation;
			// For stretched billboard: project 3D velocity into view plane
			if (config.RenderMode == .StretchedBillboard)
			{
				let toCamera = Vector3.Normalize(cameraPos - v.Position);
				var right = Vector3.Cross(.(0, 1, 0), toCamera);
				let rightLen = right.Length();
				if (rightLen > 0.001f)
					right = right / rightLen;
				else
					right = .(1, 0, 0);
				let up = Vector3.Cross(toCamera, right);
				v.Velocity2D = .(Vector3.Dot(p.Velocity, right), Vector3.Dot(p.Velocity, up));
			}
			else
			{
				v.Velocity2D = .(p.Velocity.X, p.Velocity.Y);
			}

			// Compute atlas UV
			if (useAtlas && config.AtlasFPS > 0)
			{
				// Animated atlas: pick frame based on age
				var frame = (int32)(p.Age * config.AtlasFPS);
				if (config.AtlasLoop)
					frame = frame % totalFrames;
				else
					frame = Math.Min(frame, totalFrames - 1);

				let col = frame % config.AtlasColumns;
				let row = frame / config.AtlasColumns;
				v.TexCoordOffset = .((float)col * cellW, (float)row * cellH);
				v.TexCoordScale = .(cellW, cellH);
			}
			else if (useAtlas)
			{
				// Static atlas: pick frame based on life ratio
				let lifeRatio = p.Age / p.Lifetime;
				var frame = (int32)(lifeRatio * (float)totalFrames);
				frame = Math.Min(frame, totalFrames - 1);

				let col = frame % config.AtlasColumns;
				let row = frame / config.AtlasColumns;
				v.TexCoordOffset = .((float)col * cellW, (float)row * cellH);
				v.TexCoordScale = .(cellW, cellH);
			}
			else
			{
				v.TexCoordOffset = .(0, 0);
				v.TexCoordScale = .(1, 1);
			}
		}

		// Upload to GPU
		mDevice.Queue.WriteBuffer(
			buffer, 0,
			Span<uint8>((uint8*)&mVertexData[0], mAliveCount * CPUParticleVertex.SizeInBytes)
		);
	}

	private void SpawnParticles(float deltaTime, ParticleEmitterProxy* config)
	{
		if (!config.IsEmitting)
			return;

		int32 spawnCount = 0;

		// Continuous emission (scaled by LOD)
		if (config.SpawnRate > 0 && mLODRateMultiplier > 0)
		{
			mSpawnAccumulator += config.SpawnRate * mLODRateMultiplier * deltaTime;
			spawnCount = (int32)mSpawnAccumulator;
			mSpawnAccumulator -= (float)spawnCount;
		}

		// Burst emission
		if (config.BurstCount > 0)
		{
			mBurstTimer += deltaTime;
			let canBurst = config.BurstCycles == 0 || mBurstCyclesCompleted < config.BurstCycles;

			if (canBurst)
			{
				if (config.BurstInterval <= 0)
				{
					// Single burst on first frame
					if (mBurstCyclesCompleted == 0)
					{
						spawnCount += config.BurstCount;
						mBurstCyclesCompleted++;
					}
				}
				else
				{
					while (mBurstTimer >= config.BurstInterval && (config.BurstCycles == 0 || mBurstCyclesCompleted < config.BurstCycles))
					{
						spawnCount += config.BurstCount;
						mBurstTimer -= config.BurstInterval;
						mBurstCyclesCompleted++;
					}
				}
			}
		}

		// Calculate emitter velocity for velocity inheritance
		Vector3 emitterVelocity = .Zero;
		if (config.VelocityInheritance > 0 && deltaTime > 0.0001f)
		{
			emitterVelocity = (config.Position - config.PrevPosition) / deltaTime;
		}

		for (int32 i = 0; i < spawnCount; i++)
		{
			if (mAliveCount >= mMaxParticles)
				break;

			ref CPUParticle p = ref mParticles[mAliveCount];

			// Sample emission shape
			Vector3 localPos;
			Vector3 localDir;
			mShape.Sample(mRandom, out localPos, out localDir);

			// Set initial position based on simulation space
			if (config.SimulationSpace == .Local)
				p.Position = localPos; // Store in local space
			else
				p.Position = config.Position + localPos; // Store in world space

			// Calculate initial velocity
			let speed = config.InitialVelocity.Length();
			if (speed > 0.001f)
			{
				let randomFactor = Vector3(
					(float)(mRandom.NextDouble() * 2.0 - 1.0) * config.VelocityRandomness.X,
					(float)(mRandom.NextDouble() * 2.0 - 1.0) * config.VelocityRandomness.Y,
					(float)(mRandom.NextDouble() * 2.0 - 1.0) * config.VelocityRandomness.Z
				);
				p.Velocity = config.InitialVelocity + randomFactor;
			}
			else
			{
				p.Velocity = localDir * 1.0f + Vector3(
					(float)(mRandom.NextDouble() * 2.0 - 1.0) * config.VelocityRandomness.X,
					(float)(mRandom.NextDouble() * 2.0 - 1.0) * config.VelocityRandomness.Y,
					(float)(mRandom.NextDouble() * 2.0 - 1.0) * config.VelocityRandomness.Z
				);
			}

			// Apply velocity inheritance from emitter movement
			if (config.VelocityInheritance > 0)
				p.Velocity = p.Velocity + emitterVelocity * config.VelocityInheritance;

			p.StartVelocity = p.Velocity;
			p.Age = 0;

			// Randomize lifetime using variance multipliers
			let varianceT = (float)mRandom.NextDouble();
			let lifetimeMul = config.LifetimeVarianceMin + (config.LifetimeVarianceMax - config.LifetimeVarianceMin) * varianceT;
			p.Lifetime = Math.Max(config.ParticleLifetime * lifetimeMul, 0.01f);

			p.Size = config.StartSize;

			// Start color
			let sc = config.StartColor;
			p.Color = Color(sc.X, sc.Y, sc.Z, sc.W);

			p.Rotation = (float)(mRandom.NextDouble() * Math.PI_d * 2.0);
			p.RotationSpeed = (float)(mRandom.NextDouble() * 2.0 - 1.0) * 2.0f;

			mAliveCount++;
		}
	}

	private void SimulateParticles(float deltaTime, ParticleEmitterProxy* config)
	{
		mTotalTime += deltaTime;
		int32 writeIdx = 0;

		let hasForces = config.ForceModules.HasActiveModules;

		for (int32 i = 0; i < mAliveCount; i++)
		{
			ref CPUParticle p = ref mParticles[i];

			// Update age
			p.Age += deltaTime;

			// Kill dead particles
			if (p.Age >= p.Lifetime)
			{
				// Record death position for sub-emitter support
				if (mDeathCount < mMaxDeathEvents)
				{
					mDeathPositions[mDeathCount] = p.Position;
					mDeathCount++;
				}
				continue;
			}

			// Calculate life ratio [0, 1]
			let lifeRatio = p.Age / p.Lifetime;

			// Apply gravity
			p.Velocity.Y -= 9.81f * config.GravityMultiplier * deltaTime;

			// Apply force modules
			if (hasForces)
				config.ForceModules.Apply(ref p, deltaTime, mTotalTime, config.Position, mRandom);

			// Apply drag
			let dragFactor = 1.0f - config.Drag * deltaTime;
			p.Velocity = p.Velocity * Math.Max(dragFactor, 0.0f);

			// Apply speed over lifetime curve (scales velocity magnitude)
			if (config.SpeedOverLifetime.IsActive)
			{
				let speedMul = config.SpeedOverLifetime.Evaluate(lifeRatio);
				let currentSpeed = p.Velocity.Length();
				if (currentSpeed > 0.0001f)
				{
					let desiredSpeed = p.StartVelocity.Length() * speedMul;
					p.Velocity = p.Velocity * (desiredSpeed / currentSpeed);
				}
			}

			// Update position
			p.Position = p.Position + p.Velocity * deltaTime;

			// Update rotation (with optional curve)
			var rotSpeed = p.RotationSpeed;
			if (config.RotationSpeedOverLifetime.IsActive)
				rotSpeed *= config.RotationSpeedOverLifetime.Evaluate(lifeRatio);
			p.Rotation += rotSpeed * deltaTime;

			// Evaluate size
			if (config.SizeOverLifetime.IsActive)
			{
				p.Size = config.SizeOverLifetime.Evaluate(lifeRatio);
			}
			else
			{
				// Default: linear lerp StartSize -> EndSize
				p.Size = Vector2(
					config.StartSize.X + (config.EndSize.X - config.StartSize.X) * lifeRatio,
					config.StartSize.Y + (config.EndSize.Y - config.StartSize.Y) * lifeRatio
				);
			}

			// Evaluate color
			float r, g, b, a;
			if (config.ColorOverLifetime.IsActive)
			{
				let c = config.ColorOverLifetime.Evaluate(lifeRatio);
				r = c.X;
				g = c.Y;
				b = c.Z;
				a = c.W;
			}
			else
			{
				// Default: linear lerp StartColor -> EndColor
				let sc = config.StartColor;
				let ec = config.EndColor;
				r = sc.X + (ec.X - sc.X) * lifeRatio;
				g = sc.Y + (ec.Y - sc.Y) * lifeRatio;
				b = sc.Z + (ec.Z - sc.Z) * lifeRatio;
				a = sc.W + (ec.W - sc.W) * lifeRatio;
			}

			// Apply alpha over lifetime curve (multiplier on top of color alpha)
			if (config.AlphaOverLifetime.IsActive)
			{
				a *= config.AlphaOverLifetime.Evaluate(lifeRatio);
			}

			p.Color = Color(r, g, b, a);

			// Compact alive particles (swap-remove dead ones)
			if (writeIdx != i)
			{
				mParticles[writeIdx] = p;
				// Also compact trail state and trail points
				if (mTrailsInitialized && mTrailStates != null)
				{
					mTrailStates[writeIdx] = mTrailStates[i];
					let srcOffset = i * mMaxTrailPointsPerParticle;
					let dstOffset = writeIdx * mMaxTrailPointsPerParticle;
					for (int32 t = 0; t < mMaxTrailPointsPerParticle; t++)
						mTrailPoints[dstOffset + t] = mTrailPoints[srcOffset + t];
				}
			}

			writeIdx++;
		}

		// Clear trail states for dead particles at the end
		if (mTrailsInitialized && mTrailStates != null)
		{
			for (int32 j = writeIdx; j < mAliveCount; j++)
				mTrailStates[j].Clear();
		}

		mAliveCount = writeIdx;
	}

	private void SortParticles(Vector3 cameraPos)
	{
		// Calculate distances
		for (int32 i = 0; i < mAliveCount; i++)
		{
			mSortIndices[i] = i;
			let diff = mParticles[i].Position - cameraPos;
			mSortDistances[i] = Vector3.Dot(diff, diff); // Squared distance is fine for sorting
		}

		// Simple insertion sort (particles are mostly sorted frame-to-frame)
		for (int32 i = 1; i < mAliveCount; i++)
		{
			let key = mSortIndices[i];
			let keyDist = mSortDistances[key];
			var j = i - 1;

			// Sort back-to-front (farthest first)
			while (j >= 0 && mSortDistances[mSortIndices[j]] < keyDist)
			{
				mSortIndices[j + 1] = mSortIndices[j];
				j--;
			}
			mSortIndices[j + 1] = key;
		}
	}

	private float CalculateLODMultiplier(ParticleEmitterProxy* config, Vector3 cameraPos)
	{
		// No LOD configured
		if (config.LODStartDistance <= 0 && config.LODCullDistance <= 0)
			return 1.0f;

		let diff = config.Position - cameraPos;
		let dist = diff.Length();

		// Before start distance: full rate
		if (config.LODStartDistance > 0 && dist <= config.LODStartDistance)
			return 1.0f;

		// Beyond cull distance: fully culled
		if (config.LODCullDistance > 0 && dist >= config.LODCullDistance)
			return 0.0f;

		// Between start and cull: interpolate
		if (config.LODStartDistance > 0 && config.LODCullDistance > config.LODStartDistance)
		{
			let range = config.LODCullDistance - config.LODStartDistance;
			let t = (dist - config.LODStartDistance) / range;
			return Math.Max(1.0f - t * (1.0f - config.LODMinRateMultiplier), config.LODMinRateMultiplier);
		}

		return 1.0f;
	}

	// --- Trail Methods ---

	private void InitializeTrails(ParticleEmitterProxy* config)
	{
		mMaxTrailPointsPerParticle = Math.Max(config.Trail.MaxPoints, 2);

		// Allocate trail states (one per particle slot)
		mTrailStates = new ParticleTrailState[mMaxParticles];

		// Allocate flat trail points array
		mTrailPoints = new TrailPoint[mMaxParticles * mMaxTrailPointsPerParticle];

		// Max trail vertices: each pair of adjacent points generates a quad (6 vertices)
		mMaxTrailVertices = mMaxParticles * (mMaxTrailPointsPerParticle - 1) * 6;
		mTrailVertexData = new TrailVertex[mMaxTrailVertices];

		// Create trail vertex buffers
		for (int i = 0; i < FrameBufferCount; i++)
		{
			BufferDescriptor desc = .()
			{
				Label = "CPU Particle Trail Vertex Buffer",
				Size = (uint64)(mMaxTrailVertices * TrailVertex.SizeInBytes),
				Usage = .Vertex | .CopyDst
			};

			switch (mDevice.CreateBuffer(&desc))
			{
			case .Ok(let buf): mTrailVertexBuffers[i] = buf;
			case .Err: // Will be null, checked at render time
			}
		}

		mTrailsInitialized = true;
	}

	private void RecordTrailPoints(ParticleEmitterProxy* config)
	{
		if (!mTrailsInitialized || mTrailStates == null)
			return;

		let trailSettings = config.Trail;

		for (int32 i = 0; i < mAliveCount; i++)
		{
			ref CPUParticle p = ref mParticles[i];
			ref ParticleTrailState state = ref mTrailStates[i];

			// Check if enough time has passed since last record
			let timeSinceRecord = mTotalTime - state.LastRecordTime;
			if (timeSinceRecord < trailSettings.RecordInterval && state.Count > 0)
				continue;

			// Check minimum distance
			if (state.Count > 0)
			{
				let diff = p.Position - state.LastPosition;
				let distSq = Vector3.Dot(diff, diff);
				if (distSq < trailSettings.MinVertexDistance * trailSettings.MinVertexDistance)
					continue;
			}

			// Compute width based on particle life ratio
			let lifeRatio = p.Age / p.Lifetime;
			let width = trailSettings.WidthStart * (1.0f - lifeRatio) + trailSettings.WidthEnd * lifeRatio;

			// Record trail point
			let pointOffset = i * mMaxTrailPointsPerParticle + state.Head;
			mTrailPoints[pointOffset] = .()
			{
				Position = p.Position,
				Width = width,
				Color = p.Color,
				RecordTime = mTotalTime
			};

			state.Head = (state.Head + 1) % mMaxTrailPointsPerParticle;
			if (state.Count < mMaxTrailPointsPerParticle)
				state.Count++;

			state.LastRecordTime = mTotalTime;
			state.LastPosition = p.Position;
		}
	}

	/// Uploads trail vertex data to GPU buffer for rendering.
	public void UploadTrails(uint32 frameIndex, Vector3 cameraPos, ParticleEmitterProxy* config)
	{
		if (!mTrailsInitialized || mAliveCount == 0)
		{
			mTrailVertexCount = 0;
			return;
		}

		let bufferIdx = frameIndex % FrameBufferCount;
		let buffer = mTrailVertexBuffers[bufferIdx];
		if (buffer == null)
		{
			mTrailVertexCount = 0;
			return;
		}

		int32 vertexIdx = 0;
		let trailSettings = config.Trail;

		for (int32 i = 0; i < mAliveCount; i++)
		{
			ref ParticleTrailState state = ref mTrailStates[i];
			if (state.Count < 2)
				continue;

			let baseOffset = i * mMaxTrailPointsPerParticle;

			// Generate ribbon vertices for this particle's trail
			// Walk from newest to oldest point
			for (int32 seg = 0; seg < state.Count - 1; seg++)
			{
				if (vertexIdx + 6 > mMaxTrailVertices)
					break;

				// Get current and next point (newer to older)
				let currRingIdx = ((state.Head - 1 - seg) % mMaxTrailPointsPerParticle + mMaxTrailPointsPerParticle) % mMaxTrailPointsPerParticle;
				let nextRingIdx = ((state.Head - 2 - seg) % mMaxTrailPointsPerParticle + mMaxTrailPointsPerParticle) % mMaxTrailPointsPerParticle;

				let currPoint = mTrailPoints[baseOffset + currRingIdx];
				let nextPoint = mTrailPoints[baseOffset + nextRingIdx];

				// Fade out old trail points
				let currAge = mTotalTime - currPoint.RecordTime;
				let nextAge = mTotalTime - nextPoint.RecordTime;

				if (currAge > trailSettings.Lifetime || nextAge > trailSettings.Lifetime)
					break;

				let currFade = 1.0f - (currAge / trailSettings.Lifetime);
				let nextFade = 1.0f - (nextAge / trailSettings.Lifetime);

				// Direction along the ribbon
				var dir = currPoint.Position - nextPoint.Position;
				let dirLen = dir.Length();
				if (dirLen < 0.0001f)
					continue;
				dir = dir / dirLen;

				// Width direction: perpendicular to ribbon direction and camera-to-point
				let toCamera = Vector3.Normalize(cameraPos - currPoint.Position);
				var widthDir = Vector3.Cross(dir, toCamera);
				let widthLen = widthDir.Length();
				if (widthLen < 0.0001f)
					continue;
				widthDir = widthDir / widthLen;

				// Width at each end, with fade
				let currWidth = currPoint.Width * currFade * 0.5f;
				let nextWidth = nextPoint.Width * nextFade * 0.5f;

				// V coordinates: normalized position along trail
				let vCurr = (float)seg / (float)(state.Count - 1);
				let vNext = (float)(seg + 1) / (float)(state.Count - 1);

				// Colors with fade
				let currColor = Color(
					(float)currPoint.Color.R / 255.0f,
					(float)currPoint.Color.G / 255.0f,
					(float)currPoint.Color.B / 255.0f,
					(float)currPoint.Color.A / 255.0f * currFade
				);
				let nextColor = Color(
					(float)nextPoint.Color.R / 255.0f,
					(float)nextPoint.Color.G / 255.0f,
					(float)nextPoint.Color.B / 255.0f,
					(float)nextPoint.Color.A / 255.0f * nextFade
				);

				// Four corners of the quad
				let p0 = currPoint.Position - widthDir * currWidth; // curr left
				let p1 = currPoint.Position + widthDir * currWidth; // curr right
				let p2 = nextPoint.Position - widthDir * nextWidth; // next left
				let p3 = nextPoint.Position + widthDir * nextWidth; // next right

				// Triangle 1: p0, p1, p2
				mTrailVertexData[vertexIdx] = .() { Position = p0, TexCoord = .(0, vCurr), Color = currColor };
				mTrailVertexData[vertexIdx + 1] = .() { Position = p1, TexCoord = .(1, vCurr), Color = currColor };
				mTrailVertexData[vertexIdx + 2] = .() { Position = p2, TexCoord = .(0, vNext), Color = nextColor };

				// Triangle 2: p2, p1, p3
				mTrailVertexData[vertexIdx + 3] = .() { Position = p2, TexCoord = .(0, vNext), Color = nextColor };
				mTrailVertexData[vertexIdx + 4] = .() { Position = p1, TexCoord = .(1, vCurr), Color = currColor };
				mTrailVertexData[vertexIdx + 5] = .() { Position = p3, TexCoord = .(1, vNext), Color = nextColor };

				vertexIdx += 6;
			}
		}

		mTrailVertexCount = vertexIdx;

		if (mTrailVertexCount > 0)
		{
			mDevice.Queue.WriteBuffer(
				buffer, 0,
				Span<uint8>((uint8*)&mTrailVertexData[0], mTrailVertexCount * TrailVertex.SizeInBytes)
			);
		}
	}
}
