namespace Sedulous.Engine.Physics;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.Physics;

/// Scene component that manages physics simulation for a scene.
/// Owns the IPhysicsWorld and manages entity-to-proxy synchronization.
class PhysicsSceneComponent : ISceneComponent
{
	private Scene mScene;
	private IPhysicsWorld mPhysicsWorld;

	// Entity → Proxy mapping
	private Dictionary<EntityId, PhysicsProxyHandle> mBodyProxies = new .() ~ delete _;

	// Proxy storage (dense array for cache efficiency)
	private List<PhysicsBodyProxy> mProxies = new .() ~ delete _;
	private List<uint32> mFreeProxySlots = new .() ~ delete _;
	private uint32 mNextProxyGeneration = 1;

	// Fixed timestep accumulator
	private float mAccumulator = 0.0f;
	private float mFixedTimeStep = 1.0f / 60.0f;
	private int32 mMaxSubSteps = 8;

	// Contact and activation listeners
	private ContactListenerAdapter mContactAdapter ~ delete _;
	private ActivationListenerAdapter mActivationAdapter ~ delete _;
	private IContactListener mUserContactListener;
	private IBodyActivationListener mUserActivationListener;

	// ==================== Properties ====================

	/// Gets the physics world (may be null if scene is being destroyed).
	public IPhysicsWorld PhysicsWorld => mPhysicsWorld;

	/// Gets whether the physics world is still valid.
	public bool HasPhysicsWorld => mPhysicsWorld != null;

	/// Gets the scene this component is attached to.
	public Scene Scene => mScene;

	/// Gets or sets the fixed timestep for physics simulation (default: 1/60).
	public float FixedTimeStep
	{
		get => mFixedTimeStep;
		set => mFixedTimeStep = Math.Max(value, 0.001f);
	}

	/// Gets or sets the maximum number of sub-steps per frame.
	public int32 MaxSubSteps
	{
		get => mMaxSubSteps;
		set => mMaxSubSteps = Math.Max(value, 1);
	}

	/// Gets the number of active physics proxies.
	public int32 ProxyCount => (int32)(mProxies.Count - mFreeProxySlots.Count);

	// ==================== Constructor ====================

	/// Creates a new PhysicsSceneComponent with the given physics world.
	public this(IPhysicsWorld physicsWorld)
	{
		mPhysicsWorld = physicsWorld;
	}

	// ==================== ISceneComponent Implementation ====================

	/// Called when the component is attached to a scene.
	public void OnAttach(Scene scene)
	{
		mScene = scene;
	}

	/// Called when the component is detached from a scene.
	public void OnDetach()
	{
		// Clear all proxies
		for (var entityId in mBodyProxies.Keys)
		{
			if (mBodyProxies.TryGetValue(entityId, let proxyHandle))
			{
				if (GetProxy(proxyHandle, let proxy))
				{
					if (proxy.BodyHandle.IsValid)
						mPhysicsWorld.DestroyBody(proxy.BodyHandle);
				}
			}
		}
		mBodyProxies.Clear();
		mProxies.Clear();
		mFreeProxySlots.Clear();
		mScene = null;
	}

	/// Called each frame to update the component.
	public void OnUpdate(float deltaTime)
	{
		if (mScene == null || mPhysicsWorld == null)
			return;

		// Sync gameplay → physics for kinematic bodies
		SyncGameplayToPhysics();

		// Fixed timestep physics simulation
		mAccumulator += deltaTime;
		int32 steps = 0;

		while (mAccumulator >= mFixedTimeStep && steps < mMaxSubSteps)
		{
			mPhysicsWorld.Step(mFixedTimeStep, 1);
			mAccumulator -= mFixedTimeStep;
			steps++;
		}

		// Clamp accumulator to prevent spiral of death
		if (mAccumulator > mFixedTimeStep * 2)
			mAccumulator = mFixedTimeStep * 2;

		// Sync physics → gameplay for dynamic bodies
		SyncPhysicsToGameplay();
	}

	/// Called when the scene state changes.
	public void OnSceneStateChanged(SceneState oldState, SceneState newState)
	{
		if (newState == .Unloaded)
		{
			// Clear proxies when scene unloads
			mBodyProxies.Clear();
			mProxies.Clear();
			mFreeProxySlots.Clear();
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

		// Serialize fixed timestep settings
		result = serializer.Float("fixedTimeStep", ref mFixedTimeStep);
		if (result != .Ok)
			return result;

		int32 maxSteps = mMaxSubSteps;
		result = serializer.Int32("maxSubSteps", ref maxSteps);
		if (result != .Ok)
			return result;
		mMaxSubSteps = maxSteps;

		// Proxies are recreated from entity components when scene loads
		return .Ok;
	}

	// ==================== Proxy Management ====================

	/// Creates a physics body proxy for an entity.
	public PhysicsProxyHandle CreateBodyProxy(EntityId entityId, PhysicsBodyDescriptor descriptor)
	{
		if (mPhysicsWorld == null)
			return .Invalid;

		// Destroy existing proxy if any
		DestroyBodyProxy(entityId);

		// Create the physics body
		let bodyResult = mPhysicsWorld.CreateBody(descriptor);
		if (bodyResult case .Err)
			return .Invalid;

		let bodyHandle = bodyResult.Value;

		// Allocate proxy slot
		PhysicsProxyHandle proxyHandle;
		uint32 index;

		if (mFreeProxySlots.Count > 0)
		{
			index = mFreeProxySlots.PopBack();
			mNextProxyGeneration++;
			proxyHandle = .((.)index, mNextProxyGeneration);
		}
		else
		{
			index = (uint32)mProxies.Count;
			mNextProxyGeneration++;
			proxyHandle = .((.)index, mNextProxyGeneration);
			mProxies.Add(default);
		}

		// Initialize proxy
		ref PhysicsBodyProxy proxy = ref mProxies[(int)index];
		proxy.Id = index;
		proxy.BodyHandle = bodyHandle;
		proxy.EntityId = PackEntityId(entityId);
		proxy.BodyType = descriptor.BodyType;
		proxy.LastPosition = descriptor.Position;
		proxy.LastRotation = descriptor.Rotation;
		proxy.LastLinearVelocity = descriptor.LinearVelocity;
		proxy.LastAngularVelocity = descriptor.AngularVelocity;
		proxy.Flags = .Active;

		if (descriptor.IsSensor)
			proxy.Flags |= .Sensor;

		// Store mapping
		mBodyProxies[entityId] = proxyHandle;

		return proxyHandle;
	}

	/// Destroys a physics body proxy for an entity.
	public void DestroyBodyProxy(EntityId entityId)
	{
		if (!mBodyProxies.TryGetValue(entityId, let proxyHandle))
			return;

		if (GetProxy(proxyHandle, let proxy))
		{
			// Destroy the physics body
			if (proxy.BodyHandle.IsValid && mPhysicsWorld != null)
				mPhysicsWorld.DestroyBody(proxy.BodyHandle);

			// Mark proxy slot as free
			mProxies[(int)proxyHandle.Index] = .Invalid;
			mFreeProxySlots.Add((uint32)proxyHandle.Index);
		}

		mBodyProxies.Remove(entityId);
	}

	/// Gets the proxy handle for an entity.
	public PhysicsProxyHandle GetBodyProxyHandle(EntityId entityId)
	{
		if (mBodyProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	/// Gets a proxy by handle.
	public bool GetProxy(PhysicsProxyHandle handle, out PhysicsBodyProxy* proxy)
	{
		proxy = null;
		if (!handle.IsValid)
			return false;
		if (handle.Index >= mProxies.Count)
			return false;

		proxy = &mProxies[handle.Index];
		return proxy.IsValid;
	}

	// ==================== Listeners ====================

	/// Sets the contact listener for collision events.
	public void SetContactListener(IContactListener listener)
	{
		mUserContactListener = listener;

		if (mPhysicsWorld == null)
			return;

		if (listener != null)
		{
			if (mContactAdapter == null)
				mContactAdapter = new ContactListenerAdapter(this);
			mPhysicsWorld.SetContactListener(mContactAdapter);
		}
		else
		{
			mPhysicsWorld.SetContactListener(null);
		}
	}

	/// Sets the body activation listener for sleep/wake events.
	public void SetBodyActivationListener(IBodyActivationListener listener)
	{
		mUserActivationListener = listener;

		if (mPhysicsWorld == null)
			return;

		if (listener != null)
		{
			if (mActivationAdapter == null)
				mActivationAdapter = new ActivationListenerAdapter(this);
			mPhysicsWorld.SetBodyActivationListener(mActivationAdapter);
		}
		else
		{
			mPhysicsWorld.SetBodyActivationListener(null);
		}
	}

	// ==================== Sync ====================

	/// Syncs gameplay transforms to physics for kinematic bodies.
	private void SyncGameplayToPhysics()
	{
		if (mScene == null || mPhysicsWorld == null)
			return;

		for (let (entityId, proxyHandle) in mBodyProxies)
		{
			if (!GetProxy(proxyHandle, let proxy))
				continue;

			// Only sync kinematic bodies from gameplay to physics
			if (proxy.BodyType != .Kinematic)
				continue;

			if ((proxy.Flags & .SyncDisabled) != 0)
				continue;

			// Get entity transform (using local for simplicity - assumes root entities)
			if (let entity = mScene.EntityManager.GetEntity(entityId))
			{
				let pos = entity.Transform.Position;
				let rot = entity.Transform.Rotation;

				// Update physics body
				mPhysicsWorld.SetBodyTransform(proxy.BodyHandle, pos, rot, true);

				// Update proxy cache
				proxy.LastPosition = pos;
				proxy.LastRotation = rot;
			}
		}
	}

	/// Syncs physics transforms to gameplay for dynamic bodies.
	private void SyncPhysicsToGameplay()
	{
		if (mScene == null || mPhysicsWorld == null)
			return;

		for (let (entityId, proxyHandle) in mBodyProxies)
		{
			if (!GetProxy(proxyHandle, let proxy))
				continue;

			// Only sync dynamic bodies from physics to gameplay
			if (proxy.BodyType != .Dynamic)
				continue;

			if ((proxy.Flags & .SyncDisabled) != 0)
				continue;

			// Get physics transform
			let pos = mPhysicsWorld.GetBodyPosition(proxy.BodyHandle);
			let rot = mPhysicsWorld.GetBodyRotation(proxy.BodyHandle);

			// Update proxy cache
			proxy.LastPosition = pos;
			proxy.LastRotation = rot;
			proxy.LastLinearVelocity = mPhysicsWorld.GetLinearVelocity(proxy.BodyHandle);
			proxy.LastAngularVelocity = mPhysicsWorld.GetAngularVelocity(proxy.BodyHandle);

			// Update entity transform (using local for simplicity - assumes root entities)
			if (let entity = mScene.EntityManager.GetEntity(entityId))
			{
				entity.Transform.SetPosition(pos);
				entity.Transform.SetRotation(rot);
			}
		}
	}

	// ==================== Internal ====================

	/// Called by PhysicsService before the physics world is destroyed.
	/// This allows the component to release its reference before deletion.
	public void InvalidatePhysicsWorld()
	{
		mPhysicsWorld = null;
	}

	// ==================== Helpers ====================

	/// Packs an EntityId into a uint64 for storage.
	private static uint64 PackEntityId(EntityId id)
	{
		return ((uint64)id.Generation << 32) | id.Index;
	}

	/// Unpacks a uint64 back into an EntityId.
	private static EntityId UnpackEntityId(uint64 packed)
	{
		return .((uint32)(packed & 0xFFFFFFFF), (uint32)(packed >> 32));
	}

	// ==================== Listener Adapters ====================

	/// Internal adapter that forwards contact events with BodyHandle -> EntityId translation.
	private class ContactListenerAdapter : IContactListener
	{
		private PhysicsSceneComponent mScene;

		public this(PhysicsSceneComponent scene) { mScene = scene; }

		public bool OnContactAdded(BodyHandle body1, BodyHandle body2, ContactEvent event)
		{
			if (mScene.mUserContactListener == null)
				return true;
			return mScene.mUserContactListener.OnContactAdded(body1, body2, event);
		}

		public void OnContactPersisted(BodyHandle body1, BodyHandle body2, ContactEvent event)
		{
			mScene.mUserContactListener?.OnContactPersisted(body1, body2, event);
		}

		public void OnContactRemoved(BodyHandle body1, BodyHandle body2)
		{
			mScene.mUserContactListener?.OnContactRemoved(body1, body2);
		}
	}

	/// Internal adapter for body activation events.
	private class ActivationListenerAdapter : IBodyActivationListener
	{
		private PhysicsSceneComponent mScene;

		public this(PhysicsSceneComponent scene) { mScene = scene; }

		public void OnBodyActivated(BodyHandle body)
		{
			mScene.mUserActivationListener?.OnBodyActivated(body);
		}

		public void OnBodyDeactivated(BodyHandle body)
		{
			mScene.mUserActivationListener?.OnBodyDeactivated(body);
		}
	}
}
