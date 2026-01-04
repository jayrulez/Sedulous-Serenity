using System;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Geometry;

namespace Sedulous.Framework.Renderer;

/// CPU-side skinned mesh resource wrapping a SkinnedMesh.
/// Contains the mesh data plus skeleton and animations for complete skeletal animation support.
class SkinnedMeshResource : Resource
{
	private SkinnedMesh mMesh;
	private bool mOwnsMesh;
	private Skeleton mSkeleton;
	private bool mOwnsSkeleton;
	private SkeletonResource mSkeletonResource;  // Optional shared skeleton
	private List<AnimationClip> mAnimations ~ if (mOwnsAnimations) DeleteContainerAndItems!(_);
	private bool mOwnsAnimations;

	/// The underlying skinned mesh data.
	public SkinnedMesh Mesh => mMesh;

	/// The skeleton for bone transforms.
	/// Returns from shared SkeletonResource if set, otherwise local skeleton.
	public Skeleton Skeleton => mSkeletonResource?.Skeleton ?? mSkeleton;

	/// The shared skeleton resource, if any.
	public SkeletonResource SkeletonResource => mSkeletonResource;

	/// Available animations.
	public List<AnimationClip> Animations => mAnimations;

	public this(SkinnedMesh mesh, bool ownsMesh = false)
	{
		mMesh = mesh;
		mOwnsMesh = ownsMesh;
	}

	public ~this()
	{
		if (mOwnsMesh && mMesh != null)
			delete mMesh;
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
		if (mSkeletonResource != null)
			mSkeletonResource.ReleaseRef();
	}

	/// Sets a local skeleton. Takes ownership if ownsSkeleton is true.
	/// Clears any shared skeleton resource.
	public void SetSkeleton(Skeleton skeleton, bool ownsSkeleton = false)
	{
		// Clear shared skeleton
		if (mSkeletonResource != null)
		{
			mSkeletonResource.ReleaseRef();
			mSkeletonResource = null;
		}
		// Clear local skeleton
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
		mSkeleton = skeleton;
		mOwnsSkeleton = ownsSkeleton;
	}

	/// Sets a shared skeleton resource. Adds a reference to it.
	/// Clears any local skeleton.
	public void SetSkeletonResource(SkeletonResource skeletonResource)
	{
		// Clear local skeleton
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
		mSkeleton = null;
		mOwnsSkeleton = false;

		// Clear old shared skeleton
		if (mSkeletonResource != null)
			mSkeletonResource.ReleaseRef();

		// Set new shared skeleton
		mSkeletonResource = skeletonResource;
		if (mSkeletonResource != null)
			mSkeletonResource.AddRef();
	}

	/// Sets the animations. Takes ownership if ownsAnimations is true.
	public void SetAnimations(List<AnimationClip> animations, bool ownsAnimations = false)
	{
		if (mOwnsAnimations && mAnimations != null)
			DeleteContainerAndItems!(mAnimations);
		mAnimations = animations;
		mOwnsAnimations = ownsAnimations;
	}

	/// Gets an animation by name, or null if not found.
	public AnimationClip GetAnimation(StringView name)
	{
		if (mAnimations == null)
			return null;

		for (let clip in mAnimations)
		{
			if (clip.Name == name)
				return clip;
		}
		return null;
	}

	/// Gets the number of animations.
	public int AnimationCount => mAnimations?.Count ?? 0;

	/// Creates an AnimationPlayer for this resource.
	/// Caller owns the returned player.
	public AnimationPlayer CreatePlayer()
	{
		if (mSkeleton == null)
			return null;
		return new AnimationPlayer(mSkeleton);
	}
}
