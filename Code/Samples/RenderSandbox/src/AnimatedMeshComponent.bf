namespace RenderSandbox;

using System;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.Animation;

/// Component for rendering an animated (skinned) mesh.
/// Ties together animation playback with render system skinned mesh.
public class AnimatedMeshComponent
{
	/// The skeleton hierarchy for this mesh.
	public Skeleton Skeleton ~ delete _;

	/// Animation player for this instance.
	public AnimationPlayer Player ~ delete _;

	/// Available animation clips.
	public AnimationClip[] Clips ~ DeleteContainerAndItems!(_);

	/// Handle to the skinned mesh proxy in the render world.
	public SkinnedMeshProxyHandle MeshProxy;

	/// Handle to the GPU mesh in the resource manager.
	public GPUMeshHandle GPUMesh;

	/// Handle to the GPU bone buffer.
	public GPUBoneBufferHandle BoneBuffer;

	/// Cached bone count (so we can clear Skeleton reference for shared skeletons).
	public uint16 CachedBoneCount;

	/// World transform of this mesh.
	public Matrix Transform = .Identity;

	/// Whether this component is visible.
	public bool Visible = true;

	public this()
	{
		//Clips = new .[0];
	}

	/// Initializes the animation player with the skeleton.
	/// Call this after setting up the Skeleton.
	public void InitializePlayer()
	{
		if (Skeleton != null)
		{
			CachedBoneCount = (uint16)Skeleton.BoneCount;
			delete Player;
			Player = new AnimationPlayer(Skeleton);
		}
	}

	/// Plays an animation clip by index.
	public void PlayAnimation(int index, bool loop = true)
	{
		if (index >= 0 && index < Clips.Count && Player != null)
		{
			Clips[index].IsLooping = loop;
			Player.Play(Clips[index]);
		}
	}

	/// Plays an animation clip by name.
	public void PlayAnimation(StringView name, bool loop = true)
	{
		for (int i = 0; i < Clips.Count; i++)
		{
			if (Clips[i].Name == name)
			{
				PlayAnimation(i, loop);
				return;
			}
		}
	}

	/// Updates the animation state.
	public void Update(float deltaTime)
	{
		if (Player != null)
		{
			Player.Update(deltaTime);
			Player.Evaluate();
		}
	}

	/// Uploads bone matrices to the GPU.
	public void UploadBones(GPUResourceManager resourceManager)
	{
		if (Player == null || !BoneBuffer.IsValid)
			return;

		let currentMatrices = Player.GetSkinningMatrices();
		let prevMatrices = Player.GetPrevSkinningMatrices();

		resourceManager.UpdateBoneBuffer(
			BoneBuffer,
			currentMatrices.Ptr,
			prevMatrices.Ptr,
			CachedBoneCount
		);
	}

	/// Updates the mesh proxy transform in the render world.
	public void UpdateTransform(RenderWorld world)
	{
		if (let proxy = world.GetSkinnedMesh(MeshProxy))
		{
			proxy.WorldMatrix = Transform;
			// Set visibility via Flags
			if (Visible)
				proxy.Flags |= .Visible;
			else
				proxy.Flags &= ~.Visible;
		}
	}
}
