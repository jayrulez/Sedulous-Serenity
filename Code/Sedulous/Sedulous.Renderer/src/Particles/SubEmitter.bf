namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Trigger events for sub-emitter spawning.
enum SubEmitterTrigger
{
	/// Spawn sub-emitter when parent particle is born.
	OnBirth,
	/// Spawn sub-emitter when parent particle dies.
	OnDeath,
	/// Spawn sub-emitter when parent particle collides (future).
	OnCollision
}

/// Configuration for a sub-emitter that spawns child particles.
class SubEmitter
{
	/// Configuration for the child emitter.
	/// This config is used to create child particle systems.
	public ParticleEmitterConfig Config ~ delete _;

	/// When this sub-emitter should trigger.
	public SubEmitterTrigger Trigger = .OnDeath;

	/// Probability of spawning (0-1). 1.0 = always spawn.
	public float Probability = 1.0f;

	/// Number of particles to burst emit when triggered.
	public int32 EmitCount = 10;

	/// Whether the sub-emitter spawns at the parent particle's position.
	public bool InheritPosition = true;

	/// Whether the sub-emitter inherits the parent particle's velocity.
	public bool InheritVelocity = false;

	/// Velocity inheritance factor (0-1).
	public float VelocityInheritance = 0.5f;

	/// Whether the sub-emitter inherits the parent particle's color.
	public bool InheritColor = false;

	/// Maximum number of sub-emitter instances that can be active at once.
	/// Prevents explosion of particles in chain reactions.
	public int32 MaxInstances = 100;

	/// Creates a sub-emitter with default settings.
	public this()
	{
		Config = new ParticleEmitterConfig();
	}

	/// Creates a sub-emitter with the given config and trigger.
	public this(ParticleEmitterConfig config, SubEmitterTrigger trigger)
	{
		Config = config;
		Trigger = trigger;
	}

	/// Creates a sub-emitter that triggers on particle death.
	public static SubEmitter OnDeath(ParticleEmitterConfig config, int32 emitCount = 10)
	{
		let sub = new SubEmitter(config, .OnDeath);
		sub.EmitCount = emitCount;
		return sub;
	}

	/// Creates a sub-emitter that triggers on particle birth.
	public static SubEmitter OnBirth(ParticleEmitterConfig config, int32 emitCount = 5)
	{
		let sub = new SubEmitter(config, .OnBirth);
		sub.EmitCount = emitCount;
		return sub;
	}
}

/// Runtime instance of a sub-emitter.
/// Created when a sub-emitter triggers and lives until all its particles die.
class SubEmitterInstance
{
	/// The particle system for this sub-emitter instance.
	public ParticleSystem System ~ delete _;

	/// World position where this sub-emitter was spawned.
	public Vector3 Position;

	/// Initial velocity inherited from parent (if any).
	public Vector3 Velocity;

	/// Color inherited from parent (if any).
	public Color Color;

	/// Time when this instance was created.
	public float SpawnTime;

	/// Frame count when this instance became ready for deletion.
	/// Used for deferred deletion to ensure GPU has finished using buffers.
	public int32 DeletionFrameCount = -1;

	/// Whether this instance is still active (has particles or is emitting).
	public bool IsActive => System != null && (System.ParticleCount > 0 || System.IsEmitting);

	/// Whether this instance has finished (no more particles and not emitting).
	public bool IsFinished => System == null || (System.ParticleCount == 0 && !System.IsEmitting);

	/// Creates a sub-emitter instance.
	public this(IDevice device, ParticleEmitterConfig config, Vector3 position, Vector3 velocity, Color color, float spawnTime, bool inheritColor)
	{
		Position = position;
		Velocity = velocity;
		Color = color;
		SpawnTime = spawnTime;

		// Create the particle system with limited max particles to prevent explosion
		int32 maxParticles = Math.Min(config.MaxParticles, 500);
		System = new ParticleSystem(device, config, maxParticles);
		System.Position = position;
		System.Velocity = velocity;

		// Apply inherited color as tint
		if (inheritColor)
			System.ColorTint = color;

		// Sub-emitters don't continuously emit - they do a single burst
		System.IsEmitting = false;
	}

	/// Updates the sub-emitter instance.
	public void Update(float deltaTime)
	{
		if (System != null)
		{
			System.Update(deltaTime);
		}
	}

	/// Emits a burst of particles.
	public void Burst(int32 count)
	{
		System?.Burst(count);
	}

	/// Uploads particle data to GPU for the specified frame.
	public void Upload(int32 frameIndex)
	{
		System?.Upload(frameIndex);
	}
}

/// Manager for sub-emitter instances.
/// Tracks active sub-emitters and handles their lifecycle.
class SubEmitterManager
{
	private IDevice mDevice;
	private List<SubEmitterInstance> mActiveInstances = new .() ~ DeleteContainerAndItems!(_);
	private List<SubEmitterInstance> mPendingDeletion = new .() ~ DeleteContainerAndItems!(_);
	private int32 mMaxTotalInstances = 500;
	private float mCurrentTime = 0;
	private Random mRandom = new .() ~ delete _;
	private int32 mFrameCount = 0;

	// Defer deletion using centralized frame config to ensure GPU has finished using buffers

	public this(IDevice device, int32 maxInstances = 500)
	{
		mDevice = device;
		mMaxTotalInstances = maxInstances;
	}

	/// Gets the number of active sub-emitter instances.
	public int32 ActiveCount => (int32)mActiveInstances.Count;

	/// Gets the maximum number of instances.
	public int32 MaxInstances => mMaxTotalInstances;

	/// Gets all active instances for rendering.
	public List<SubEmitterInstance> ActiveInstances => mActiveInstances;

	/// Spawns a sub-emitter instance from a trigger event.
	/// Returns true if the instance was spawned, false if at capacity.
	public bool SpawnSubEmitter(SubEmitter subEmitter, Vector3 position, Vector3 velocity, Color color)
	{
		// Check probability
		if (subEmitter.Probability < 1.0f)
		{
			float roll = (float)mRandom.NextDouble();
			if (roll > subEmitter.Probability)
				return false;
		}

		// Check capacity (includes pending deletions since those still use GPU resources)
		int32 totalInstances = (int32)(mActiveInstances.Count + mPendingDeletion.Count);
		if (totalInstances >= mMaxTotalInstances)
			return false;

		// Apply inheritance
		Vector3 spawnPos = subEmitter.InheritPosition ? position : .Zero;
		Vector3 spawnVel = subEmitter.InheritVelocity ? velocity * subEmitter.VelocityInheritance : .Zero;
		Color spawnColor = subEmitter.InheritColor ? color : Color.White;

		// Create instance
		let instance = new SubEmitterInstance(mDevice, subEmitter.Config, spawnPos, spawnVel, spawnColor, mCurrentTime, subEmitter.InheritColor);

		// Emit burst
		instance.Burst(subEmitter.EmitCount);

		mActiveInstances.Add(instance);
		return true;
	}

	/// Updates all active sub-emitter instances.
	public void Update(float deltaTime)
	{
		mCurrentTime += deltaTime;
		mFrameCount++;

		// Process pending deletions - only delete after enough frames have passed
		for (int i = mPendingDeletion.Count - 1; i >= 0; i--)
		{
			let instance = mPendingDeletion[i];
			if (mFrameCount - instance.DeletionFrameCount >= FrameConfig.DELETION_DEFER_FRAMES)
			{
				delete instance;
				mPendingDeletion.RemoveAt(i);
			}
		}

		// Update all instances and move finished ones to pending deletion
		for (int i = mActiveInstances.Count - 1; i >= 0; i--)
		{
			let instance = mActiveInstances[i];
			instance.Update(deltaTime);

			if (instance.IsFinished)
			{
				// Mark when this instance became ready for deletion
				instance.DeletionFrameCount = mFrameCount;
				mPendingDeletion.Add(instance);
				mActiveInstances.RemoveAt(i);
			}
		}
	}

	/// Uploads all active sub-emitter particle data to GPU for the specified frame.
	public void Upload(int32 frameIndex)
	{
		for (let instance in mActiveInstances)
		{
			instance.Upload(frameIndex);
		}
	}

	/// Clears all active sub-emitter instances.
	public void Clear()
	{
		DeleteContainerAndItems!(mActiveInstances);
		mActiveInstances = new .();
		DeleteContainerAndItems!(mPendingDeletion);
		mPendingDeletion = new .();
	}

	/// Gets the total particle count across all sub-emitters.
	public int32 TotalParticleCount
	{
		get
		{
			int32 count = 0;
			for (let instance in mActiveInstances)
				count += instance.System?.ParticleCount ?? 0;
			return count;
		}
	}
}
