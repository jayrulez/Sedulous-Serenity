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

	// RNG for particle spawning
	private Random mRandom = new .() ~ delete _;

	// Emission shape
	private EmissionShape mShape = .Point();

	// Double-buffered vertex buffers
	private IBuffer[FrameBufferCount] mVertexBuffers;
	private CPUParticleVertex[] mVertexData ~ delete _;

	// Sort scratch buffer
	private int32[] mSortIndices ~ delete _;
	private float[] mSortDistances ~ delete _;

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

	/// Creates a new CPU particle emitter.
	public this(IDevice device, int32 maxParticles)
	{
		mDevice = device;
		mMaxParticles = maxParticles;
		mParticles = new CPUParticle[maxParticles];
		mVertexData = new CPUParticleVertex[maxParticles];
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
		}
	}

	/// Updates particle simulation.
	public void Update(float deltaTime, ParticleEmitterProxy* config)
	{
		// Spawn new particles
		SpawnParticles(deltaTime, config);

		// Simulate existing particles
		SimulateParticles(deltaTime, config);
	}

	/// Uploads vertex data to GPU buffer for rendering.
	public void Upload(uint32 frameIndex, Vector3 cameraPos, ParticleEmitterProxy* config)
	{
		if (mAliveCount == 0)
			return;

		let bufferIdx = frameIndex % FrameBufferCount;
		let buffer = mVertexBuffers[bufferIdx];
		if (buffer == null)
			return;

		// Sort if needed (back-to-front for alpha blending)
		if (config.SortParticles && config.BlendMode == .Alpha)
			SortParticles(cameraPos);

		// Build vertex data
		for (int32 i = 0; i < mAliveCount; i++)
		{
			int32 particleIdx = config.SortParticles && config.BlendMode == .Alpha
				? mSortIndices[i]
				: i;

			ref CPUParticle p = ref mParticles[particleIdx];
			ref CPUParticleVertex v = ref mVertexData[i];

			v.Position = p.Position;
			v.Size = p.Size;
			v.Color = p.Color;
			v.Rotation = p.Rotation;
			v.TexCoordOffset = .(0, 0); // Full texture (no atlas)
			v.TexCoordScale = .(1, 1);
			v.Velocity2D = .(p.Velocity.X, p.Velocity.Y); // For stretched billboard
		}

		// Upload to GPU
		mDevice.Queue.WriteBuffer(
			buffer, 0,
			Span<uint8>((uint8*)&mVertexData[0], mAliveCount * CPUParticleVertex.SizeInBytes)
		);
	}

	private void SpawnParticles(float deltaTime, ParticleEmitterProxy* config)
	{
		mSpawnAccumulator += config.SpawnRate * deltaTime;
		int32 spawnCount = (int32)mSpawnAccumulator;
		mSpawnAccumulator -= (float)spawnCount;

		for (int32 i = 0; i < spawnCount; i++)
		{
			if (mAliveCount >= mMaxParticles)
				break;

			ref CPUParticle p = ref mParticles[mAliveCount];

			// Sample emission shape
			Vector3 localPos;
			Vector3 localDir;
			mShape.Sample(mRandom, out localPos, out localDir);

			// Transform by emitter position/rotation
			p.Position = config.Position + localPos;

			// Calculate initial velocity
			let speed = config.InitialVelocity.Length();
			if (speed > 0.001f)
			{
				// Apply velocity in the shape direction with randomness
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

			p.StartVelocity = p.Velocity;
			p.Age = 0;

			// Randomize lifetime slightly
			let lifetimeVariance = config.ParticleLifetime * 0.5f;
			p.Lifetime = config.ParticleLifetime + (float)(mRandom.NextDouble() * 2.0 - 1.0) * lifetimeVariance;
			p.Lifetime = Math.Max(p.Lifetime, 0.1f);

			p.Size = config.StartSize;

			// Start color from Vector4 to Color
			let sc = config.StartColor;
			p.Color = Color(sc.X, sc.Y, sc.Z, sc.W);

			p.Rotation = (float)(mRandom.NextDouble() * Math.PI_d * 2.0);
			p.RotationSpeed = (float)(mRandom.NextDouble() * 2.0 - 1.0) * 2.0f;

			mAliveCount++;
		}
	}

	private void SimulateParticles(float deltaTime, ParticleEmitterProxy* config)
	{
		int32 writeIdx = 0;

		for (int32 i = 0; i < mAliveCount; i++)
		{
			ref CPUParticle p = ref mParticles[i];

			// Update age
			p.Age += deltaTime;

			// Kill dead particles
			if (p.Age >= p.Lifetime)
				continue;

			// Calculate life ratio
			let lifeRatio = p.Age / p.Lifetime;

			// Apply gravity
			p.Velocity.Y -= 9.81f * config.GravityMultiplier * deltaTime;

			// Apply drag
			let dragFactor = 1.0f - config.Drag * deltaTime;
			p.Velocity = p.Velocity * Math.Max(dragFactor, 0.0f);

			// Update position
			p.Position = p.Position + p.Velocity * deltaTime;

			// Update rotation
			p.Rotation += p.RotationSpeed * deltaTime;

			// Interpolate size
			p.Size = Vector2(
				config.StartSize.X + (config.EndSize.X - config.StartSize.X) * lifeRatio,
				config.StartSize.Y + (config.EndSize.Y - config.StartSize.Y) * lifeRatio
			);

			// Interpolate color
			let sc = config.StartColor;
			let ec = config.EndColor;
			var r = sc.X + (ec.X - sc.X) * lifeRatio;
			var g = sc.Y + (ec.Y - sc.Y) * lifeRatio;
			var b = sc.Z + (ec.Z - sc.Z) * lifeRatio;
			var a = sc.W + (ec.W - sc.W) * lifeRatio;

			// Fade out at end of life
			if (lifeRatio > 0.8f)
			{
				let fadeRatio = (lifeRatio - 0.8f) / 0.2f;
				a *= (1.0f - fadeRatio);
			}

			p.Color = Color(r, g, b, a);

			// Compact alive particles (swap-remove dead ones)
			if (writeIdx != i)
				mParticles[writeIdx] = p;

			writeIdx++;
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
}
