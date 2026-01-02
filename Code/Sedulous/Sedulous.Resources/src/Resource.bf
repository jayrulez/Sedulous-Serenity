using System;
using System.Threading;
using System.Diagnostics;
using Sedulous.Serialization;

namespace Sedulous.Resources;

/// Abstract base class for all resources.
/// Provides reference counting and serialization support.
abstract class Resource : IResource, ISerializable
{
	private int32 mRefCount = 0;
	private Guid mId;
	private String mName = new .() ~ delete _;

	/// Gets or sets the unique identifier.
	public Guid Id
	{
		get => mId;
		set => mId = value;
	}

	/// Gets or sets the resource name.
	public String Name
	{
		get => mName;
		set { mName.Set(value); }
	}

	/// Gets the current reference count.
	public int RefCount => mRefCount;

	public this()
	{
		mId = Guid.Create();
	}

	public ~this()
	{
		Debug.Assert(mRefCount == 0, "Resource deleted with non-zero ref count");
	}

	/// Increments the reference count.
	public void AddRef()
	{
		Interlocked.Increment(ref mRefCount);
	}

	/// Decrements the reference count. Deletes when count reaches zero.
	public void ReleaseRef()
	{
		let refCount = Interlocked.Decrement(ref mRefCount);
		Debug.Assert(refCount >= 0);
		if (refCount == 0)
			delete this;
	}
	
	public void ReleaseLastRef()
	{
		int refCount = Interlocked.Decrement(ref mRefCount);
		Debug.Assert(refCount == 0);
		if (refCount == 0)
		{
			delete this;
		}
	}

	/// Decrements the reference count without deleting.
	public int ReleaseRefNoDelete()
	{
		let refCount = Interlocked.Decrement(ref mRefCount);
		Debug.Assert(refCount >= 0);
		return refCount;
	}

	// ---- ISerializable ----

	/// Gets the serialization version for this resource type.
	public virtual int32 SerializationVersion => 1;

	/// Serializes the resource.
	public virtual SerializationResult Serialize(Serializer s)
	{
		// Serialize base resource data
		var version = SerializationVersion;
		s.Version(ref version);

		// Serialize GUID as string
		let guidStr = scope String();
		if (s.IsWriting)
			mId.ToString(guidStr);
		s.String("id", guidStr);
		if (s.IsReading)
			mId = Guid.Parse(guidStr).GetValueOrDefault();

		s.String("name", mName);

		return OnSerialize(s);
	}

	/// Override to serialize resource-specific data.
	protected virtual SerializationResult OnSerialize(Serializer s)
	{
		return .Ok;
	}
}
