namespace Sedulous.Engine.Physics;

using System;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.Physics;

/// Entity component that adds rigid body physics to an entity.
class RigidBodyComponent : IEntityComponent
{
	// Entity and scene references
	private Entity mEntity;
	private PhysicsSceneComponent mPhysicsScene;
	private PhysicsProxyHandle mProxyHandle = .Invalid;

	// Shape handle (created from descriptor or set directly)
	private ShapeHandle mShape = .Invalid;
	private bool mOwnsShape = false;

	// Body configuration
	private BodyType mBodyType = .Dynamic;
	private float mMass = 1.0f;
	private float mFriction = 0.5f;
	private float mRestitution = 0.0f;
	private float mLinearDamping = 0.05f;
	private float mAngularDamping = 0.05f;
	private float mGravityFactor = 1.0f;
	private bool mIsSensor = false;
	private bool mAllowSleep = true;
	private uint16 mLayer = 1; // Default to dynamic layer

	// ==================== Properties ====================

	/// Gets or sets the body type.
	public BodyType BodyType
	{
		get => mBodyType;
		set
		{
			if (mBodyType != value)
			{
				mBodyType = value;
				if (mProxyHandle.IsValid && mPhysicsScene?.PhysicsWorld != null)
				{
					if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
					{
						mPhysicsScene.PhysicsWorld.SetBodyType(proxy.BodyHandle, value);
						proxy.BodyType = value;
					}
				}
			}
		}
	}

	/// Gets or sets the mass (for dynamic bodies).
	public float Mass
	{
		get => mMass;
		set => mMass = Math.Max(value, 0.001f);
	}

	/// Gets or sets the friction coefficient.
	public float Friction
	{
		get => mFriction;
		set => mFriction = Math.Clamp(value, 0.0f, 1.0f);
	}

	/// Gets or sets the restitution (bounciness).
	public float Restitution
	{
		get => mRestitution;
		set => mRestitution = Math.Clamp(value, 0.0f, 1.0f);
	}

	/// Gets or sets the linear damping.
	public float LinearDamping
	{
		get => mLinearDamping;
		set => mLinearDamping = Math.Max(value, 0.0f);
	}

	/// Gets or sets the angular damping.
	public float AngularDamping
	{
		get => mAngularDamping;
		set => mAngularDamping = Math.Max(value, 0.0f);
	}

	/// Gets or sets the gravity factor.
	public float GravityFactor
	{
		get => mGravityFactor;
		set => mGravityFactor = value;
	}

	/// Gets or sets whether this is a sensor (trigger) body.
	public bool IsSensor
	{
		get => mIsSensor;
		set => mIsSensor = value;
	}

	/// Gets or sets whether the body can sleep.
	public bool AllowSleep
	{
		get => mAllowSleep;
		set => mAllowSleep = value;
	}

	/// Gets or sets the collision layer.
	public uint16 Layer
	{
		get => mLayer;
		set => mLayer = value;
	}

	/// Gets the proxy handle for this body.
	public PhysicsProxyHandle ProxyHandle => mProxyHandle;

	/// Gets whether this body has a valid physics proxy.
	public bool HasProxy => mProxyHandle.IsValid;

	// ==================== Constructor ====================

	/// Creates a new RigidBodyComponent.
	public this()
	{
	}

	// ==================== Shape Configuration ====================

	/// Sets a box shape for this body.
	public void SetBoxShape(Vector3 halfExtents)
	{
		ClearShape();
		if (mPhysicsScene?.PhysicsWorld != null)
		{
			if (mPhysicsScene.PhysicsWorld.CreateBoxShape(halfExtents) case .Ok(let shape))
			{
				mShape = shape;
				mOwnsShape = true;
				RecreateBody();
			}
		}
	}

	/// Sets a sphere shape for this body.
	public void SetSphereShape(float radius)
	{
		ClearShape();
		if (mPhysicsScene?.PhysicsWorld != null)
		{
			if (mPhysicsScene.PhysicsWorld.CreateSphereShape(radius) case .Ok(let shape))
			{
				mShape = shape;
				mOwnsShape = true;
				RecreateBody();
			}
		}
	}

	/// Sets a capsule shape for this body.
	public void SetCapsuleShape(float halfHeight, float radius)
	{
		ClearShape();
		if (mPhysicsScene?.PhysicsWorld != null)
		{
			if (mPhysicsScene.PhysicsWorld.CreateCapsuleShape(halfHeight, radius) case .Ok(let shape))
			{
				mShape = shape;
				mOwnsShape = true;
				RecreateBody();
			}
		}
	}

	/// Sets a pre-created shape for this body.
	/// The component does NOT take ownership of the shape.
	public void SetShape(ShapeHandle shape)
	{
		ClearShape();
		mShape = shape;
		mOwnsShape = false;
		RecreateBody();
	}

	// ==================== Physics Actions ====================

	/// Gets the linear velocity.
	public Vector3 GetLinearVelocity()
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				return mPhysicsScene.PhysicsWorld.GetLinearVelocity(proxy.BodyHandle);
		}
		return .Zero;
	}

	/// Sets the linear velocity.
	public void SetLinearVelocity(Vector3 velocity)
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				mPhysicsScene.PhysicsWorld.SetLinearVelocity(proxy.BodyHandle, velocity);
		}
	}

	/// Gets the angular velocity.
	public Vector3 GetAngularVelocity()
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				return mPhysicsScene.PhysicsWorld.GetAngularVelocity(proxy.BodyHandle);
		}
		return .Zero;
	}

	/// Sets the angular velocity.
	public void SetAngularVelocity(Vector3 velocity)
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				mPhysicsScene.PhysicsWorld.SetAngularVelocity(proxy.BodyHandle, velocity);
		}
	}

	/// Adds a force to the body (applied at center of mass).
	public void AddForce(Vector3 force)
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				mPhysicsScene.PhysicsWorld.AddForce(proxy.BodyHandle, force);
		}
	}

	/// Adds an impulse to the body (applied at center of mass).
	public void AddImpulse(Vector3 impulse)
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				mPhysicsScene.PhysicsWorld.AddImpulse(proxy.BodyHandle, impulse);
		}
	}

	/// Adds torque to the body.
	public void AddTorque(Vector3 torque)
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				mPhysicsScene.PhysicsWorld.AddTorque(proxy.BodyHandle, torque);
		}
	}


	/// Wakes up the body if it's sleeping.
	public void Activate()
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				mPhysicsScene.PhysicsWorld.ActivateBody(proxy.BodyHandle);
		}
	}

	/// Puts the body to sleep.
	public void Deactivate()
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				mPhysicsScene.PhysicsWorld.DeactivateBody(proxy.BodyHandle);
		}
	}

	/// Checks if the body is currently active (awake).
	public bool IsActive()
	{
		if (mPhysicsScene?.PhysicsWorld != null && mProxyHandle.IsValid)
		{
			if (mPhysicsScene.GetProxy(mProxyHandle, let proxy))
				return mPhysicsScene.PhysicsWorld.IsBodyActive(proxy.BodyHandle);
		}
		return false;
	}

	// ==================== IEntityComponent Implementation ====================

	/// Called when the component is attached to an entity.
	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		// Find the PhysicsSceneComponent
		if (entity.Scene != null)
		{
			mPhysicsScene = entity.Scene.GetSceneComponent<PhysicsSceneComponent>();
			if (mPhysicsScene != null && mShape.IsValid)
			{
				CreateBody();
			}
		}
	}

	/// Called when the component is detached from an entity.
	public void OnDetach()
	{
		DestroyBody();
		ClearShape();
		mEntity = null;
		mPhysicsScene = null;
	}

	/// Called each frame to update the component.
	public void OnUpdate(float deltaTime)
	{
		// Transform sync is handled by PhysicsSceneComponent
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// Serialize body type
		int32 bodyType = (int32)mBodyType;
		result = serializer.Int32("bodyType", ref bodyType);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			mBodyType = (BodyType)bodyType;

		// Serialize physics properties
		result = serializer.Float("mass", ref mMass);
		if (result != .Ok) return result;

		result = serializer.Float("friction", ref mFriction);
		if (result != .Ok) return result;

		result = serializer.Float("restitution", ref mRestitution);
		if (result != .Ok) return result;

		result = serializer.Float("linearDamping", ref mLinearDamping);
		if (result != .Ok) return result;

		result = serializer.Float("angularDamping", ref mAngularDamping);
		if (result != .Ok) return result;

		result = serializer.Float("gravityFactor", ref mGravityFactor);
		if (result != .Ok) return result;

		// Serialize flags
		int32 flags = (mIsSensor ? 1 : 0) | (mAllowSleep ? 2 : 0);
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok) return result;
		if (serializer.IsReading)
		{
			mIsSensor = (flags & 1) != 0;
			mAllowSleep = (flags & 2) != 0;
		}

		// Serialize layer
		int32 layer = (int32)mLayer;
		result = serializer.Int32("layer", ref layer);
		if (result != .Ok) return result;
		if (serializer.IsReading)
			mLayer = (uint16)layer;

		// Note: Shape is not serialized - it needs to be set up by the loading code
		// using shape descriptors or resource references

		return .Ok;
	}

	// ==================== Internal ====================

	private void CreateBody()
	{
		if (mPhysicsScene == null || mEntity == null || !mShape.IsValid)
			return;

		// Build descriptor from current settings
		PhysicsBodyDescriptor descriptor = .();
		descriptor.Shape = mShape;
		descriptor.Position = mEntity.Transform.Position;
		descriptor.Rotation = mEntity.Transform.Rotation;
		descriptor.BodyType = mBodyType;
		descriptor.Layer = mLayer;
		descriptor.Friction = mFriction;
		descriptor.Restitution = mRestitution;
		descriptor.LinearDamping = mLinearDamping;
		descriptor.AngularDamping = mAngularDamping;
		descriptor.GravityFactor = mGravityFactor;
		descriptor.IsSensor = mIsSensor;
		descriptor.AllowSleep = mAllowSleep;

		mProxyHandle = mPhysicsScene.CreateBodyProxy(mEntity.Id, descriptor);
	}

	private void DestroyBody()
	{
		if (mPhysicsScene != null && mEntity != null)
		{
			mPhysicsScene.DestroyBodyProxy(mEntity.Id);
		}
		mProxyHandle = .Invalid;
	}

	private void RecreateBody()
	{
		if (mEntity != null && mPhysicsScene != null)
		{
			DestroyBody();
			CreateBody();
		}
	}

	private void ClearShape()
	{
		if (mOwnsShape && mShape.IsValid && mPhysicsScene?.PhysicsWorld != null)
		{
			mPhysicsScene.PhysicsWorld.ReleaseShape(mShape);
		}
		mShape = .Invalid;
		mOwnsShape = false;
	}
}
