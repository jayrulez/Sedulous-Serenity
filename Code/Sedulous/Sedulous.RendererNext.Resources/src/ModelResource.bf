namespace Sedulous.RendererNext.Resources;

using System;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Models;

/// CPU-side model resource wrapping a Model (from GLTF or other formats).
/// A model can contain multiple meshes, materials, textures, and animations.
class ModelResource : Resource
{
	private Model mModel;
	private bool mOwnsModel;

	/// The underlying model data.
	public Model Model => mModel;

	public this()
	{
		mModel = null;
		mOwnsModel = false;
	}

	public this(Model model, bool ownsModel = false)
	{
		mModel = model;
		mOwnsModel = ownsModel;
	}

	public ~this()
	{
		if (mOwnsModel && mModel != null)
			delete mModel;
	}

	/// Sets the model. Takes ownership if ownsModel is true.
	public void SetModel(Model model, bool ownsModel = false)
	{
		if (mOwnsModel && mModel != null)
			delete mModel;
		mModel = model;
		mOwnsModel = ownsModel;
	}

	/// Number of meshes in the model.
	public int MeshCount => mModel?.Meshes?.Count ?? 0;

	/// Number of materials in the model.
	public int MaterialCount => mModel?.Materials?.Count ?? 0;

	/// Number of textures in the model.
	public int TextureCount => mModel?.Textures?.Count ?? 0;

	/// Whether the model has skeletal data (skins).
	public bool HasSkeleton => mModel != null && mModel.Skins != null && mModel.Skins.Count > 0;

	/// Number of animations in the model.
	public int AnimationCount => mModel?.Animations?.Count ?? 0;

	/// Number of bones in the model.
	public int BoneCount => mModel?.Bones?.Count ?? 0;
}
