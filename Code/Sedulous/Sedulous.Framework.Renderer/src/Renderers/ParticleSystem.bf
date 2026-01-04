namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// A single particle in the system.
struct Particle
{
	public Vector3 Position;
	public Vector3 Velocity;
	public Vector2 Size;
	public Color Color;
	public float Rotation;
	public float RotationSpeed;
	public float Life;      // Current life remaining
	public float MaxLife;   // Initial life

	public bool IsAlive => Life > 0;

	public float LifeRatio => MaxLife > 0 ? Life / MaxLife : 0;
}

/// GPU-uploadable particle vertex data.
[CRepr]
struct ParticleVertex
{
	public Vector3 Position;
	public Vector2 Size;
	public Color Color;
	public float Rotation;

	public this(Particle p)
	{
		Position = p.Position;
		Size = p.Size;
		Color = p.Color;
		Rotation = p.Rotation;
	}
}

/// Particle emitter configuration.
struct ParticleEmitterConfig
{
	/// Emission rate (particles per second).
	public float EmissionRate;
	/// Initial velocity range.
	public Vector3 MinVelocity;
	public Vector3 MaxVelocity;
	/// Initial size range.
	public float MinSize;
	public float MaxSize;
	/// Lifetime range.
	public float MinLife;
	public float MaxLife;
	/// Color over lifetime (start, end).
	public Color StartColor;
	public Color EndColor;
	/// Gravity or constant acceleration.
	public Vector3 Gravity;
	/// Size over lifetime multiplier (1.0 = no change).
	public float SizeOverLife;
	/// Rotation speed range (radians/sec).
	public float MinRotationSpeed;
	public float MaxRotationSpeed;

	public static Self Default => .()
	{
		EmissionRate = 100,
		MinVelocity = .(-1, 2, -1),
		MaxVelocity = .(1, 4, 1),
		MinSize = 0.1f,
		MaxSize = 0.2f,
		MinLife = 1.0f,
		MaxLife = 2.0f,
		StartColor = .White,
		EndColor = .(255, 255, 255, 0),
		Gravity = .(0, -9.8f, 0),
		SizeOverLife = 0.5f,
		MinRotationSpeed = -1.0f,
		MaxRotationSpeed = 1.0f
	};
}

/// CPU-driven particle system.
class ParticleSystem
{
	private IDevice mDevice;
	private List<Particle> mParticles = new .() ~ delete _;
	private IBuffer mVertexBuffer;
	private IBuffer mIndexBuffer;

	private ParticleEmitterConfig mConfig;
	private Vector3 mEmitterPosition;
	private float mEmissionAccumulator = 0;
	private int32 mMaxParticles;
	private Random mRandom = new .() ~ delete _;
	private bool mEmitting = true;

	public const int32 DEFAULT_MAX_PARTICLES = 10000;

	public int32 ParticleCount => (int32)mParticles.Count;
	public int32 MaxParticles => mMaxParticles;
	public bool IsEmitting { get => mEmitting; set => mEmitting = value; }
	public Vector3 Position { get => mEmitterPosition; set => mEmitterPosition = value; }
	public ref ParticleEmitterConfig Config => ref mConfig;

	public this(IDevice device, int32 maxParticles = DEFAULT_MAX_PARTICLES)
	{
		mDevice = device;
		mMaxParticles = maxParticles;
		mConfig = .Default;
		mEmitterPosition = .Zero;

		CreateBuffers();
	}

	public ~this()
	{
		if (mVertexBuffer != null) delete mVertexBuffer;
		if (mIndexBuffer != null) delete mIndexBuffer;
	}

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

	/// Updates particles and emits new ones.
	public void Update(float deltaTime)
	{
		// Update existing particles
		for (int i = mParticles.Count - 1; i >= 0; i--)
		{
			ref Particle p = ref mParticles[i];

			p.Life -= deltaTime;
			if (p.Life <= 0)
			{
				mParticles.RemoveAtFast(i);
				continue;
			}

			// Physics
			p.Velocity += mConfig.Gravity * deltaTime;
			p.Position += p.Velocity * deltaTime;
			p.Rotation += p.RotationSpeed * deltaTime;

			// Color over lifetime
			float lifeRatio = p.LifeRatio;
			p.Color = Color.Lerp(mConfig.EndColor, mConfig.StartColor, lifeRatio);
		}

		// Emit new particles
		if (mEmitting && mParticles.Count < mMaxParticles)
		{
			mEmissionAccumulator += mConfig.EmissionRate * deltaTime;

			while (mEmissionAccumulator >= 1.0f && mParticles.Count < mMaxParticles)
			{
				EmitParticle();
				mEmissionAccumulator -= 1.0f;
			}
		}
	}

	private void EmitParticle()
	{
		Particle p = .();
		p.Position = mEmitterPosition;
		p.Velocity = RandomRange(mConfig.MinVelocity, mConfig.MaxVelocity);
		float size = RandomRange(mConfig.MinSize, mConfig.MaxSize);
		p.Size = .(size, size);
		p.Color = mConfig.StartColor;
		p.Rotation = RandomRange(0, Math.PI_f * 2);
		p.RotationSpeed = RandomRange(mConfig.MinRotationSpeed, mConfig.MaxRotationSpeed);
		p.MaxLife = RandomRange(mConfig.MinLife, mConfig.MaxLife);
		p.Life = p.MaxLife;

		mParticles.Add(p);
	}

	private float RandomRange(float min, float max)
	{
		return min + (float)mRandom.NextDouble() * (max - min);
	}

	private Vector3 RandomRange(Vector3 min, Vector3 max)
	{
		return .(
			RandomRange(min.X, max.X),
			RandomRange(min.Y, max.Y),
			RandomRange(min.Z, max.Z)
		);
	}

	/// Uploads particle data to GPU.
	public void Upload()
	{
		if (mParticles.Count == 0)
			return;

		ParticleVertex[] vertices = new ParticleVertex[mParticles.Count];
		defer delete vertices;

		for (int i = 0; i < mParticles.Count; i++)
		{
			vertices[i] = .(mParticles[i]);
		}

		let dataSize = (uint64)(sizeof(ParticleVertex) * mParticles.Count);
		Span<uint8> data = .((uint8*)vertices.Ptr, (int)dataSize);
		mDevice.Queue.WriteBuffer(mVertexBuffer, 0, data);
	}

	/// Clears all particles.
	public void Clear()
	{
		mParticles.Clear();
		mEmissionAccumulator = 0;
	}

	/// Emits a burst of particles.
	public void Burst(int32 count)
	{
		for (int32 i = 0; i < count && mParticles.Count < mMaxParticles; i++)
		{
			EmitParticle();
		}
	}

	public IBuffer VertexBuffer => mVertexBuffer;
	public IBuffer IndexBuffer => mIndexBuffer;
	public uint32 IndexCount => (uint32)(mParticles.Count * 6);
}
