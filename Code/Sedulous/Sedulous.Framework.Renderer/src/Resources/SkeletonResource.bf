using System;
using Sedulous.Resources;
using Sedulous.Geometry;

namespace Sedulous.Framework.Renderer;

/// CPU-side skeleton resource for skeletal animation.
/// Can be shared between multiple SkinnedMeshResources.
class SkeletonResource : Resource
{
	private Skeleton mSkeleton;
	private bool mOwnsSkeleton;

	/// The underlying skeleton data.
	public Skeleton Skeleton => mSkeleton;

	/// Number of bones in the skeleton.
	public int32 BoneCount => mSkeleton?.BoneCount ?? 0;

	public this(Skeleton skeleton, bool ownsSkeleton = false)
	{
		mSkeleton = skeleton;
		mOwnsSkeleton = ownsSkeleton;
	}

	public ~this()
	{
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
	}

	/// Create an AnimationPlayer for this skeleton.
	public AnimationPlayer CreatePlayer()
	{
		if (mSkeleton == null)
			return null;
		return new AnimationPlayer(mSkeleton);
	}
}
