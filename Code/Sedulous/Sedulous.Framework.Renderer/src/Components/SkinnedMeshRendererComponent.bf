namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.Framework.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;

/// Entity component that renders a skinned mesh with skeletal animation.
/// Bridges an entity to a MeshProxy in the RenderSceneComponent.
class SkinnedMeshRendererComponent : IEntityComponent
{
	// GPU mesh handle
	private GPUSkinnedMeshHandle mGPUMesh = .Invalid;
	private BoundingBox mLocalBounds = .(.Zero, .Zero);

	// Animation data
	private Skeleton mSkeleton ~ delete _;
	private AnimationPlayer mAnimationPlayer ~ delete _;
	private List<AnimationClip> mAnimationClips = new .() ~ DeleteContainerAndItems!(_);

	// GPU bone matrix buffer
	private IBuffer mBoneMatrixBuffer ~ delete _;

	// Entity and scene references
	private Entity mEntity;
	private RenderSceneComponent mRenderScene;
	private ProxyHandle mProxyHandle = .Invalid;

	/// Material IDs for each sub-mesh (up to 8).
	public uint32[8] MaterialIds;

	/// Number of materials used.
	public uint8 MaterialCount;

	/// Whether this mesh casts shadows.
	public bool CastShadows = true;

	/// Whether this mesh receives shadows.
	public bool ReceiveShadows = true;

	/// Whether the mesh is visible.
	public bool Visible = true;

	/// Gets the GPU skinned mesh handle.
	public GPUSkinnedMeshHandle GPUMesh => mGPUMesh;

	/// Gets the local bounding box.
	public BoundingBox LocalBounds => mLocalBounds;

	/// Gets the proxy handle for this mesh.
	public ProxyHandle ProxyHandle => mProxyHandle;

	/// Gets the skeleton.
	public Skeleton Skeleton => mSkeleton;

	/// Gets the animation player.
	public AnimationPlayer AnimationPlayer => mAnimationPlayer;

	/// Gets the bone matrix buffer for shader binding.
	public IBuffer BoneMatrixBuffer => mBoneMatrixBuffer;

	/// Gets the list of available animation clips.
	public List<AnimationClip> AnimationClips => mAnimationClips;

	/// Gets whether an animation is currently playing.
	public bool IsPlaying => mAnimationPlayer != null && mAnimationPlayer.State == .Playing;

	/// Creates a new SkinnedMeshRendererComponent.
	public this()
	{
	}

	/// Sets the skeleton for this skinned mesh.
	/// Must be called before SetMesh.
	public void SetSkeleton(Skeleton skeleton)
	{
		// Delete old skeleton and player
		if (mSkeleton != null)
			delete mSkeleton;
		if (mAnimationPlayer != null)
			delete mAnimationPlayer;

		mSkeleton = skeleton;

		if (skeleton != null)
		{
			mAnimationPlayer = new AnimationPlayer(skeleton);

			// Create/resize bone matrix buffer if renderer service is available
			CreateBoneMatrixBuffer();
		}
	}

	/// Adds an animation clip.
	public void AddAnimationClip(AnimationClip clip)
	{
		mAnimationClips.Add(clip);
	}

	/// Gets an animation clip by name.
	public AnimationClip GetAnimationClip(StringView name)
	{
		for (let clip in mAnimationClips)
		{
			if (clip.Name == name)
				return clip;
		}
		return null;
	}

	/// Gets an animation clip by index.
	public AnimationClip GetAnimationClip(int32 index)
	{
		if (index >= 0 && index < mAnimationClips.Count)
			return mAnimationClips[index];
		return null;
	}

	/// Plays an animation by name.
	public void PlayAnimation(StringView name, bool loop = true)
	{
		if (mAnimationPlayer == null)
			return;

		if (let clip = GetAnimationClip(name))
		{
			mAnimationPlayer.Looping = loop;
			mAnimationPlayer.Play(clip);
		}
	}

	/// Plays an animation by index.
	public void PlayAnimation(int32 index, bool loop = true)
	{
		if (mAnimationPlayer == null)
			return;

		if (let clip = GetAnimationClip(index))
		{
			mAnimationPlayer.Looping = loop;
			mAnimationPlayer.Play(clip);
		}
	}

	/// Stops the current animation.
	public void StopAnimation()
	{
		if (mAnimationPlayer != null)
			mAnimationPlayer.Stop();
	}

	/// Pauses the current animation.
	public void PauseAnimation()
	{
		if (mAnimationPlayer != null)
			mAnimationPlayer.Pause();
	}

	/// Resumes a paused animation.
	public void ResumeAnimation()
	{
		if (mAnimationPlayer != null)
			mAnimationPlayer.Resume();
	}

	/// Gets the name of the currently playing animation.
	public StringView CurrentAnimationName
	{
		get
		{
			if (mAnimationPlayer?.CurrentClip != null)
				return mAnimationPlayer.CurrentClip.Name;
			return "";
		}
	}

	/// Sets the GPU skinned mesh to render.
	/// Call SetSkeleton first.
	public void SetMesh(GPUSkinnedMeshHandle mesh, BoundingBox bounds)
	{
		mGPUMesh = mesh;
		mLocalBounds = bounds;

		// Update proxy if attached
		if (mEntity != null && mRenderScene != null && mesh.IsValid)
		{
			CreateOrUpdateProxy();
		}
	}

	// ==================== IEntityComponent Implementation ====================

	/// Called when the component is attached to an entity.
	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		// Find the RenderSceneComponent
		if (entity.Scene != null)
		{
			mRenderScene = entity.Scene.GetSceneComponent<RenderSceneComponent>();
			if (mRenderScene != null)
			{
				CreateBoneMatrixBuffer();

				if (mGPUMesh.IsValid)
				{
					CreateOrUpdateProxy();
				}
			}
		}
	}

	/// Called when the component is detached from an entity.
	public void OnDetach()
	{
		RemoveProxy();
		mEntity = null;
		mRenderScene = null;
	}

	/// Called each frame to update the component.
	public void OnUpdate(float deltaTime)
	{
		// Update animation
		if (mAnimationPlayer != null && mAnimationPlayer.State == .Playing)
		{
			// Update animation time and compute bone matrices
			mAnimationPlayer.Update(deltaTime);

			// Upload bone matrices to GPU
			UploadBoneMatrices();
		}

		// Update visibility flag on proxy if changed
		if (mRenderScene != null && mProxyHandle.IsValid)
		{
			if (let proxy = mRenderScene.RenderWorld.GetMeshProxy(mProxyHandle))
			{
				if (Visible)
					proxy.Flags |= .Visible;
				else
					proxy.Flags &= ~.Visible;
			}
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

		// Serialize rendering flags
		int32 flags = (CastShadows ? 1 : 0) | (ReceiveShadows ? 2 : 0) | (Visible ? 4 : 0);
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok)
			return result;

		if (serializer.IsReading)
		{
			CastShadows = (flags & 1) != 0;
			ReceiveShadows = (flags & 2) != 0;
			Visible = (flags & 4) != 0;
		}

		// Serialize material count and IDs
		int32 matCount = (int32)MaterialCount;
		result = serializer.Int32("materialCount", ref matCount);
		if (result != .Ok)
			return result;
		MaterialCount = (uint8)Math.Min(matCount, 8);

		for (int32 i = 0; i < MaterialCount; i++)
		{
			int32 matId = (int32)MaterialIds[i];
			result = serializer.Int32(null, ref matId);
			if (result != .Ok)
				return result;
			if (serializer.IsReading)
				MaterialIds[i] = (uint32)matId;
		}

		// Note: GPU mesh, skeleton, and animations are not serialized
		// They need to be set up by the loading code using resource references

		return .Ok;
	}

	// ==================== Internal ====================

	private void CreateBoneMatrixBuffer()
	{
		if (mRenderScene?.RendererService?.Device == null)
			return;
		if (mBoneMatrixBuffer != null)
			return; // Already created

		let device = mRenderScene.RendererService.Device;

		// Create buffer for MAX_BONES matrices
		const int32 maxBones = Sedulous.Framework.Renderer.Skeleton.MAX_BONES;
		uint64 bufferSize = (uint64)(maxBones * sizeof(Matrix));
		BufferDescriptor desc = .(bufferSize, .Uniform | .Storage, .Upload);
		desc.Label = "BoneMatrices";

		if (device.CreateBuffer(&desc) case .Ok(let buffer))
		{
			mBoneMatrixBuffer = buffer;

			// Initialize to identity matrices
			Matrix[maxBones] identity = .();
			for (int i = 0; i < maxBones; i++)
				identity[i] = .Identity;

			Span<uint8> data = .((uint8*)&identity[0], (int)bufferSize);
			device.Queue.WriteBuffer(buffer, 0, data);
		}
	}

	private void UploadBoneMatrices()
	{
		if (mRenderScene?.RendererService?.Device == null)
			return;
		if (mBoneMatrixBuffer == null)
			return;
		if (mAnimationPlayer?.BoneMatrices == null)
			return;

		let device = mRenderScene.RendererService.Device;

		// Upload bone matrices from animation player
		const int32 maxBones = Sedulous.Framework.Renderer.Skeleton.MAX_BONES;
		uint64 dataSize = (uint64)(maxBones * sizeof(Matrix));
		Span<uint8> data = .((uint8*)mAnimationPlayer.BoneMatrices.Ptr, (int)dataSize);
		device.Queue.WriteBuffer(mBoneMatrixBuffer, 0, data);
	}

	private void CreateOrUpdateProxy()
	{
		if (mRenderScene == null || mEntity == null)
			return;

		// For skinned meshes, we still create a regular mesh proxy for visibility/culling
		// The actual mesh handle will need to be converted from GPUSkinnedMeshHandle
		// For now, use a simple placeholder - in a full implementation you'd have
		// a separate skinned mesh proxy type or store the skinned handle differently

		// Create as regular mesh proxy with invalid mesh handle (skeleton-based rendering)
		mProxyHandle = mRenderScene.CreateMeshProxy(
			mEntity.Id,
			.Invalid, // We use bone matrix buffer directly for skinned rendering
			mEntity.Transform.WorldMatrix,
			mLocalBounds
		);
	}

	private void RemoveProxy()
	{
		if (mRenderScene != null && mEntity != null)
		{
			mRenderScene.DestroyMeshProxy(mEntity.Id);
		}
		mProxyHandle = .Invalid;
	}
}
