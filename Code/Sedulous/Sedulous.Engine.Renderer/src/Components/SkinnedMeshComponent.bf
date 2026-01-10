namespace Sedulous.Engine.Renderer;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Geometry;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;
using Sedulous.Renderer;

/// Entity component that renders a skinned mesh with skeletal animation.
class SkinnedMeshComponent : IEntityComponent
{
	// GPU mesh handle
	private GPUSkinnedMeshHandle mGPUMesh = .Invalid;
	private BoundingBox mLocalBounds = .(.Zero, .Zero);

	// Animation data
	private Skeleton mSkeleton;
	private bool mOwnsSkeleton = false;
	private AnimationPlayer mAnimationPlayer ~ delete _;
	private List<AnimationClip> mAnimationClips = new .() ~ delete _;  // Don't delete items - we don't own them
	private bool mOwnsAnimationClips = false;

	// GPU bone matrix buffer
	private IBuffer mBoneMatrixBuffer ~ delete _;

	// GPU object uniform buffer (model matrix) - per-component to avoid sharing issues
	private IBuffer mObjectUniformBuffer ~ delete _;

	// Texture for this skinned mesh
	private ITexture mTexture ~ delete _;
	private ITextureView mTextureView ~ delete _;

	// Cached bind group for this skinned mesh
	private IBindGroup mBindGroup ~ delete _;

	// Material instance (for PBR rendering)
	private MaterialInstanceHandle mMaterialInstance = .Invalid;

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

	/// Gets the local bounding box.
	public BoundingBox LocalBounds => mLocalBounds;

	/// Gets the skeleton.
	public Skeleton Skeleton => mSkeleton;

	/// Gets the animation player.
	public AnimationPlayer AnimationPlayer => mAnimationPlayer;

	/// Gets the bone matrix buffer for shader binding (framework use).
	public IBuffer BoneMatrixBuffer => mBoneMatrixBuffer;

	/// Gets the object uniform buffer for shader binding (framework use).
	public IBuffer ObjectUniformBuffer => mObjectUniformBuffer;

	/// Gets the list of available animation clips.
	public List<AnimationClip> AnimationClips => mAnimationClips;

	/// Gets whether an animation is currently playing.
	public bool IsPlaying => mAnimationPlayer != null && mAnimationPlayer.State == .Playing;

	/// Gets the GPU mesh handle (framework use).
	public GPUSkinnedMeshHandle GPUMeshHandle => mGPUMesh;

	/// Gets or sets the cached bind group for rendering (framework use).
	public IBindGroup BindGroup
	{
		get => mBindGroup;
		set
		{
			if (mBindGroup != null)
				delete mBindGroup;
			mBindGroup = value;
		}
	}

	/// Gets the entity this component is attached to (framework use).
	public Entity Entity => mEntity;

	/// Gets the texture view for this skinned mesh, or null if none set.
	public ITextureView TextureView => mTextureView;

	/// Gets or sets the material instance handle for PBR rendering.
	public MaterialInstanceHandle MaterialInstance
	{
		get => mMaterialInstance;
		set
		{
			mMaterialInstance = value;
			// Invalidate bind group so it gets recreated
			if (mBindGroup != null)
			{
				delete mBindGroup;
				mBindGroup = null;
			}
		}
	}

	/// Sets the material for this skinned mesh.
	/// The material instance must be valid and registered with the MaterialSystem.
	public void SetMaterial(MaterialInstanceHandle material)
	{
		MaterialInstance = material;
	}

	/// Creates a new SkinnedMeshRendererComponent.
	public this()
	{
	}

	public ~this()
	{
		// Only delete skeleton if we own it
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;

		// Only delete animation clips if we own them
		if (mOwnsAnimationClips)
			DeleteContainerAndItems!(mAnimationClips);
	}

	/// Sets the skeleton for this skinned mesh.
	/// Must be called before SetMesh.
	/// If ownsSkeleton is false, the skeleton is shared and won't be deleted.
	public void SetSkeleton(Skeleton skeleton, bool ownsSkeleton = false)
	{
		// Delete old skeleton and player if we own it
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
		if (mAnimationPlayer != null)
		{
			delete mAnimationPlayer;
			mAnimationPlayer = null;
		}

		mSkeleton = skeleton;
		mOwnsSkeleton = ownsSkeleton;

		if (skeleton != null)
		{
			mAnimationPlayer = new AnimationPlayer(skeleton);

			// Create/resize bone matrix buffer if renderer service is available
			CreateBoneMatrixBuffer();
		}
	}

	/// Sets the texture for this skinned mesh.
	/// Takes ownership of the texture and view.
	public void SetTexture(ITexture texture, ITextureView textureView)
	{
		// Delete old texture resources
		if (mTextureView != null)
			delete mTextureView;
		if (mTexture != null)
			delete mTexture;

		mTexture = texture;
		mTextureView = textureView;

		// Invalidate bind group so it gets recreated with new texture
		if (mBindGroup != null)
		{
			delete mBindGroup;
			mBindGroup = null;
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

	/// Sets the skinned mesh to render from CPU mesh data.
	/// Automatically uploads to GPU via the RendererService.
	public void SetMesh(SkinnedMesh mesh)
	{
		if (mesh == null)
			return;

		if (mRenderScene?.RendererService?.ResourceManager == null)
		{
			// Store for later when attached
			mLocalBounds = mesh.Bounds;
			return;
		}

		// Upload to GPU
		let resourceManager = mRenderScene.RendererService.ResourceManager;
		mGPUMesh = resourceManager.CreateSkinnedMesh(mesh);
		mLocalBounds = mesh.Bounds;

		// Create proxy FIRST (before registration needs it)
		if (mEntity != null && mGPUMesh.IsValid)
		{
			CreateOrUpdateProxy();
		}

		// Register with render scene for rendering (proxy must exist)
		mRenderScene.RegisterSkinnedMesh(this);
	}

	/// Sets the GPU skinned mesh to render (low-level API).
	internal void SetMesh(GPUSkinnedMeshHandle mesh, BoundingBox bounds)
	{
		mGPUMesh = mesh;
		mLocalBounds = bounds;

		// Create proxy FIRST (before registration needs it)
		if (mEntity != null && mRenderScene != null && mesh.IsValid)
		{
			CreateOrUpdateProxy();
		}

		// Register with render scene for rendering (proxy must exist)
		if (mRenderScene != null)
			mRenderScene.RegisterSkinnedMesh(this);
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
					// Create proxy first, then register (proxy must exist for registration)
					CreateOrUpdateProxy();
					mRenderScene.RegisterSkinnedMesh(this);
				}
			}
		}
	}

	/// Called when the component is detached from an entity.
	public void OnDetach()
	{
		mRenderScene?.UnregisterSkinnedMesh(this);
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

		// Update proxy with current transform, material, and visibility
		if (mRenderScene != null && mProxyHandle.IsValid)
		{
			if (let proxy = mRenderScene.RenderWorld.GetSkinnedMeshProxy(mProxyHandle))
			{
				// Update transform
				if (mEntity != null)
				{
					proxy.Transform = mEntity.Transform.WorldMatrix;
					proxy.UpdateWorldBounds();
				}

				// Update material (may have been set after SetMesh)
				proxy.MaterialInstance = mMaterialInstance;

				// Update visibility
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

		let device = mRenderScene.RendererService.Device;

		// Create bone matrix buffer if not already created
		if (mBoneMatrixBuffer == null)
		{
			// Create buffer for MAX_BONES matrices
			const int32 maxBones = Sedulous.Renderer.Skeleton.MAX_BONES;
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

		// Create object uniform buffer if not already created (128 bytes for SkinnedObjectUniforms)
		if (mObjectUniformBuffer == null)
		{
			BufferDescriptor objDesc = .(128, .Uniform, .Upload);
			objDesc.Label = "SkinnedObjectUniforms";

			if (device.CreateBuffer(&objDesc) case .Ok(let objBuffer))
			{
				mObjectUniformBuffer = objBuffer;
			}
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
		const int32 maxBones = Sedulous.Renderer.Skeleton.MAX_BONES;
		uint64 dataSize = (uint64)(maxBones * sizeof(Matrix));
		Span<uint8> data = .((uint8*)mAnimationPlayer.BoneMatrices.Ptr, (int)dataSize);
		device.Queue.WriteBuffer(mBoneMatrixBuffer, 0, data);
	}

	private void CreateOrUpdateProxy()
	{
		if (mRenderScene == null || mEntity == null || mRenderScene.RenderWorld == null)
			return;

		// Create skinned mesh proxy in RenderWorld
		if (!mProxyHandle.IsValid)
		{
			mProxyHandle = mRenderScene.RenderWorld.CreateSkinnedMeshProxy(
				mGPUMesh,
				mEntity.Transform.WorldMatrix,
				mLocalBounds
			);
		}

		// Update proxy with current state
		if (let proxy = mRenderScene.RenderWorld.GetSkinnedMeshProxy(mProxyHandle))
		{
			proxy.Transform = mEntity.Transform.WorldMatrix;
			proxy.MeshHandle = mGPUMesh;
			proxy.MaterialInstance = mMaterialInstance;
			proxy.BoneMatrixBuffer = mBoneMatrixBuffer;
			proxy.ObjectUniformBuffer = mObjectUniformBuffer;
			proxy.LocalBounds = mLocalBounds;
			proxy.UpdateWorldBounds();

			// Update flags
			if (Visible)
				proxy.Flags |= .Visible;
			else
				proxy.Flags &= ~.Visible;

			if (CastShadows)
				proxy.Flags |= .CastShadows;
			else
				proxy.Flags &= ~.CastShadows;

			if (ReceiveShadows)
				proxy.Flags |= .ReceiveShadows;
			else
				proxy.Flags &= ~.ReceiveShadows;
		}
	}

	private void RemoveProxy()
	{
		if (mRenderScene != null && mRenderScene.RenderWorld != null && mProxyHandle.IsValid)
		{
			mRenderScene.RenderWorld.DestroySkinnedMeshProxy(mProxyHandle);
		}
		mProxyHandle = .Invalid;
	}

	/// Gets the proxy handle for this skinned mesh.
	public ProxyHandle ProxyHandle => mProxyHandle;
}
