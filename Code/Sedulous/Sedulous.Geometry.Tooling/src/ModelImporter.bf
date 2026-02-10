using System;
using System.IO;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Models;
using Sedulous.Imaging;
using Sedulous.Animation.Resources;
using Sedulous.Geometry.Resources;
using Sedulous.Resources;

namespace Sedulous.Geometry.Tooling;

/// Imports models and creates CPU resources.
class ModelImporter
{
	private ModelImportOptions mOptions ~ delete _;
	/// Maps each skin index to the skeleton result index in result.Skeletons.
	/// Duplicate skins map to the same skeleton index as their first occurrence.
	/// -1 means skeleton creation failed for that skin.
	private List<int32> mSkinToSkeletonIdx = new .() ~ delete _;

	/// Create an importer with the given options and image loader.
	/// The importer does NOT take ownership of the image loader.
	public this(ModelImportOptions options)
	{
		mOptions = options;
	}

	/// Import resources from a loaded model.
	/// Order: Skeletons → Textures → Materials → StaticMeshes → SkinnedMeshes → Animations
	/// Textures are imported before materials so materials can reference them via ResourceRef.
	/// Skeletons are imported before skinned meshes so meshes can reference them via ResourceRef.
	public ModelImportResult Import(Model model)
	{
		let result = new ModelImportResult();

		if (model == null)
		{
			result.AddError("Model is null");
			return result;
		}

		// 1. Skeletons first (needed by skinned meshes for SkeletonRef)
		if (mOptions.Flags.HasFlag(.Skeletons))
		{
			ImportSkeletons(model, result);
		}

		// 2. Textures (needed by materials for texture ResourceRefs)
		if (mOptions.Flags.HasFlag(.Textures))
		{
			ImportTextures(model, result);
		}

		// 3. Materials (can now reference imported textures by GUID)
		if (mOptions.Flags.HasFlag(.Materials))
		{
			ImportMaterials(model, result);
		}

		// 4. Static meshes
		if (mOptions.Flags.HasFlag(.Meshes))
		{
			ImportStaticMeshes(model, result);
		}

		// 5. Skinned meshes (reference skeletons via SkeletonRef, no embedded data)
		if (mOptions.Flags.HasFlag(.SkinnedMeshes))
		{
			ImportSkinnedMeshes(model, result);
		}

		// 6. Standalone animations
		if (mOptions.Flags.HasFlag(.Animations))
		{
			ImportAnimations(model, result);
		}

		return result;
	}

	private void ImportSkeletons(Model model, ModelImportResult result)
	{

		mSkinToSkeletonIdx.Clear();

		for (int skinIdx = 0; skinIdx < model.Skins.Count; skinIdx++)
		{
			let skin = model.Skins[skinIdx];

	
			// Check if this skin is a duplicate of an earlier one (same joint node indices)
			int duplicateOf = -1;
			for (int prevIdx = 0; prevIdx < skinIdx; prevIdx++)
			{
				let prevSkin = model.Skins[prevIdx];
				if (prevSkin.Joints.Count == skin.Joints.Count)
				{
					bool same = true;
					for (int j = 0; j < skin.Joints.Count; j++)
					{
						if (skin.Joints[j] != prevSkin.Joints[j])
						{
							same = false;
							break;
						}
					}
					if (same)
					{
						duplicateOf = prevIdx;
						break;
					}
				}
			}

			if (duplicateOf >= 0)
			{
				// Map this skin to the same skeleton as the original
				mSkinToSkeletonIdx.Add(mSkinToSkeletonIdx[duplicateOf]);
					continue;
			}

			let skeleton = SkeletonConverter.CreateFromSkin(model, skin);
			if (skeleton == null)
			{
				mSkinToSkeletonIdx.Add(-1);
				result.AddWarning(scope $"Failed to create skeleton from skin {skinIdx}");
				continue;
			}

			let skeletonResultIdx = (int32)result.Skeletons.Count;
			mSkinToSkeletonIdx.Add(skeletonResultIdx);

			let skeletonRes = new SkeletonResource(skeleton, true);

			// Generate name
			let name = scope String();
			if (skin.Joints.Count > 0 && skin.Joints[0] >= 0 && skin.Joints[0] < model.Bones.Count)
			{
				name.AppendF("{}_skeleton", model.Bones[skin.Joints[0]].Name);
			}
			else
			{
				name.AppendF("skeleton_{}", skinIdx);
			}
			skeletonRes.Name.Set(name);
	
			result.Skeletons.Add(skeletonRes);
		}
	}

	private void ImportStaticMeshes(Model model, ModelImportResult result)
	{
		// Convert each ModelMesh to a StaticMesh with transform baked in
		let convertedMeshes = scope List<StaticMesh>();
		String firstName = scope .();

		for (int meshIdx = 0; meshIdx < model.Meshes.Count; meshIdx++)
		{
			let modelMesh = model.Meshes[meshIdx];

			let mesh = ModelMeshConverter.ConvertToStaticMesh(modelMesh, mOptions.GenerateNormals, mOptions.GenerateTangents);
			if (mesh == null)
			{
				result.AddWarning(scope $"Failed to convert mesh '{modelMesh.Name}'");
				continue;
			}

			// Bake the mesh node's world transform into vertices
			let nodeTransform = ComputeMeshNodeWorldTransform(model, (int32)meshIdx);
			ApplyTransform(mesh, nodeTransform);

			if (mOptions.Scale != 1.0f)
				ApplyScale(mesh, mOptions.Scale);

			if (firstName.IsEmpty)
				firstName.Set(modelMesh.Name);

			convertedMeshes.Add(mesh);
		}

		if (convertedMeshes.Count == 0)
			return;

		// Merge all static meshes into one resource
		StaticMesh mergedMesh;
		if (convertedMeshes.Count == 1)
		{
			mergedMesh = convertedMeshes[0];
		}
		else
		{
			mergedMesh = MergeStaticMeshes(convertedMeshes);
			// Delete source meshes (merged mesh has its own data)
			for (let m in convertedMeshes)
				delete m;
		}

		let meshRes = new StaticMeshResource(mergedMesh, true);
		meshRes.Name.Set(firstName);
		result.StaticMeshes.Add(meshRes);
	}

	private void ImportSkinnedMeshes(Model model, ModelImportResult result)
	{

		// Track which skeleton indices we've already produced a skinned mesh for.
		// Duplicate skins map to the same skeleton, so we skip the second occurrence.
		let processedSkeletons = scope HashSet<int32>();

		for (int skinIdx = 0; skinIdx < model.Skins.Count; skinIdx++)
		{
			let skeletonIdx = (skinIdx < mSkinToSkeletonIdx.Count) ? mSkinToSkeletonIdx[skinIdx] : -1;

			if (skeletonIdx < 0)
			{
					continue;
			}

			if (!processedSkeletons.Add(skeletonIdx))
			{
					continue;
			}

			let skin = model.Skins[skinIdx];
	
			// Convert all meshes that use this skin
			let convertedMeshes = scope List<SkinnedMesh>();
			int32[] nodeToBoneMapping = null;
			String firstName = scope .();

			for (int meshIdx = 0; meshIdx < model.Meshes.Count; meshIdx++)
			{
				let modelMesh = model.Meshes[meshIdx];

				bool hasSkinning = false;
				for (let element in modelMesh.VertexElements)
				{
					if (element.Semantic == .Joints)
					{
						hasSkinning = true;
						break;
					}
				}

				if (!hasSkinning)
					continue;

				if (ModelMeshConverter.ConvertToSkinnedMesh(modelMesh, skin, mOptions.GenerateNormals, mOptions.GenerateTangents) case .Ok(var conversionResult))
				{
					if (mOptions.Scale != 1.0f)
						ApplyScaleSkinned(conversionResult.Mesh, mOptions.Scale);

					if (firstName.IsEmpty)
						firstName.Set(modelMesh.Name);

					convertedMeshes.Add(conversionResult.Mesh);

					// Keep the first node-to-bone mapping for animation import
					if (nodeToBoneMapping == null)
						nodeToBoneMapping = conversionResult.NodeToBoneMapping;
					else
						delete conversionResult.NodeToBoneMapping;
				}
				else
				{
					result.AddWarning(scope $"Failed to convert skinned mesh '{modelMesh.Name}'");
				}
			}

			if (convertedMeshes.Count == 0)
			{
				delete nodeToBoneMapping;
				continue;
			}

			// Merge all skinned meshes for this skin into one resource
			SkinnedMesh mergedMesh;
			if (convertedMeshes.Count == 1)
			{
				mergedMesh = convertedMeshes[0];
			}
			else
			{
				mergedMesh = MergeSkinnedMeshes(convertedMeshes);
				for (let m in convertedMeshes)
					delete m;
			}

			let skinnedMeshRes = new SkinnedMeshResource(mergedMesh, true);
			skinnedMeshRes.Name.Set(firstName);

			// Link to skeleton
			if (skeletonIdx < result.Skeletons.Count)
			{
				let skeletonRes = result.Skeletons[skeletonIdx];
				skinnedMeshRes.SkeletonRef = ResourceRef(skeletonRes.Id, skeletonRes.Name);
			}

	
			result.SkinnedMeshes.Add(skinnedMeshRes);

			delete nodeToBoneMapping;
		}
	}

	/// Merges multiple StaticMeshes into a single mesh with SubMeshes preserved.
	private StaticMesh MergeStaticMeshes(List<StaticMesh> meshes)
	{
		// Calculate totals
		int32 totalVertices = 0;
		int32 totalIndices = 0;
		for (let m in meshes)
		{
			totalVertices += m.Vertices?.VertexCount ?? 0;
			totalIndices += m.Indices?.IndexCount ?? 0;
		}

		let merged = new StaticMesh();
		merged.SetupCommonVertexFormat();
		merged.Vertices.Resize(totalVertices);
		merged.Indices.Resize(totalIndices);

		int32 vertexOffset = 0;
		int32 indexOffset = 0;

		for (let src in meshes)
		{
			let srcVertCount = src.Vertices?.VertexCount ?? 0;
			let srcIdxCount = src.Indices?.IndexCount ?? 0;

			// Copy vertices
			for (int32 i = 0; i < srcVertCount; i++)
			{
				merged.SetPosition(vertexOffset + i, src.GetPosition(i));
				merged.SetNormal(vertexOffset + i, src.GetNormal(i));
				merged.SetUV(vertexOffset + i, src.GetUV(i));
				merged.SetColor(vertexOffset + i, src.GetColor(i));
				merged.SetTangent(vertexOffset + i, src.GetTangent(i));
			}

			// Copy indices (remapped by vertexOffset)
			for (int32 i = 0; i < srcIdxCount; i++)
			{
				let idx = src.Indices.GetIndex(i);
				merged.Indices.SetIndex(indexOffset + i, idx + (uint32)vertexOffset);
			}

			// Copy SubMeshes (adjusting startIndex by indexOffset)
			if (src.SubMeshes != null)
			{
				for (let sub in src.SubMeshes)
					merged.AddSubMesh(SubMesh(indexOffset + sub.startIndex, sub.indexCount, sub.materialIndex, sub.primitiveType));
			}

			vertexOffset += srcVertCount;
			indexOffset += srcIdxCount;
		}

		return merged;
	}

	/// Merges multiple SkinnedMeshes into a single mesh with SubMeshes preserved.
	private SkinnedMesh MergeSkinnedMeshes(List<SkinnedMesh> meshes)
	{
		// Calculate totals
		int32 totalVertices = 0;
		int32 totalIndices = 0;
		for (let m in meshes)
		{
			totalVertices += m.VertexCount;
			totalIndices += m.IndexCount;
		}

		let merged = new SkinnedMesh();
		merged.ResizeVertices(totalVertices);
		merged.ReserveIndices(totalIndices);

		int32 vertexOffset = 0;
		int32 indexOffset = 0;

		for (let src in meshes)
		{
			// Copy vertices
			for (int32 i = 0; i < src.VertexCount; i++)
				merged.SetVertex(vertexOffset + i, src.GetVertex(i));

			// Copy indices (remapped by vertexOffset)
			for (int32 i = 0; i < src.IndexCount; i++)
			{
				let idx = src.Indices.GetIndex(i);
				merged.Indices.SetIndex(indexOffset + i, idx + (uint32)vertexOffset);
			}

			// Copy SubMeshes (adjusting startIndex by indexOffset)
			if (src.SubMeshes != null)
			{
				for (let sub in src.SubMeshes)
					merged.AddSubMesh(SubMesh(indexOffset + sub.startIndex, sub.indexCount, sub.materialIndex, sub.primitiveType));
			}

			vertexOffset += src.VertexCount;
			indexOffset += src.IndexCount;
		}

		merged.CalculateBounds();
		return merged;
	}

	private void ImportTextures(Model model, ModelImportResult result)
	{
		for (int texIdx = 0; texIdx < model.Textures.Count; texIdx++)
		{
			let modelTex = model.Textures[texIdx];

			// Use TextureConverter which handles decoded pixel data
			let textureRes = TextureConverter.Convert(modelTex, mOptions.BasePath);

			if (textureRes == null)
			{
				result.AddWarning(scope $"Failed to load texture '{modelTex.Name}' (uri: {modelTex.Uri})");
				continue;
			}

			result.Textures.Add(textureRes);
		}
	}

	private void ImportMaterials(Model model, ModelImportResult result)
	{
		for (int matIdx = 0; matIdx < model.Materials.Count; matIdx++)
		{
			let modelMat = model.Materials[matIdx];

			// Create new MaterialResource (with texture ResourceRefs from imported textures)
			let mat = MaterialConverter.ConvertToNew(modelMat, model, result.Textures);
			if (mat != null)
				result.Materials.Add(mat);
			else
				result.AddWarning(scope $"Failed to convert material '{modelMat.Name}'");
		}
	}

	private void ImportAnimations(Model model, ModelImportResult result)
	{
		if (model.Animations.Count == 0 || model.Skins.Count == 0)
			return;

		// Use the first skin to get node-to-bone mapping
		let skin = model.Skins[0];
		let modelMesh = model.Meshes.Count > 0 ? model.Meshes[0] : null;

		// We need to find a mesh with skinning data to get the node-to-bone mapping
		int32[] nodeToBoneMapping = null;
		if (modelMesh != null)
		{
			bool hasSkinning = false;
			for (let element in modelMesh.VertexElements)
			{
				if (element.Semantic == .Joints)
				{
					hasSkinning = true;
					break;
				}
			}

			if (hasSkinning)
			{
				if (ModelMeshConverter.ConvertToSkinnedMesh(modelMesh, skin, mOptions.GenerateNormals, mOptions.GenerateTangents) case .Ok(var conversionResult))
				{
					nodeToBoneMapping = conversionResult.NodeToBoneMapping;
					delete conversionResult.Mesh;  // Not needed here, only using the mapping
					defer { conversionResult.Dispose(); }

					// Convert each animation to a resource
					for (let modelAnim in model.Animations)
					{
						let clip = AnimationConverter.Convert(modelAnim, nodeToBoneMapping);
						if (clip != null)
						{
							let animRes = new AnimationClipResource(clip, true);
							result.Animations.Add(animRes);
						}
						else
						{
							result.AddWarning(scope $"Failed to convert animation '{modelAnim.Name}'");
						}
					}
				}
			}
		}
	}

	private Image LoadImageFromMemory(Span<uint8> data)
	{
		if (ImageLoaderFactory.LoadImageFromMemory(data) case .Ok(var image))
		{
			return image;
		}

		return null;
	}

	private Image LoadImageFromFile(StringView path)
	{
		if (ImageLoaderFactory.LoadImage(path) case .Ok(var image))
		{
			return image;
		}

		return null;
	}

	/// Finds the first node that references the given mesh index and computes its world transform.
	/// Traverses the parent chain to accumulate transforms from the full hierarchy.
	private Matrix ComputeMeshNodeWorldTransform(Model model, int32 meshIndex)
	{
		// Find the first node that references this mesh
		int32 nodeIndex = -1;
		for (let bone in model.Bones)
		{
			if (bone.MeshIndex == meshIndex)
			{
				nodeIndex = bone.Index;
				break;
			}
		}

		if (nodeIndex < 0)
			return Matrix.Identity;

		// Walk up the parent chain, accumulating transforms
		Matrix worldTransform = Matrix.Identity;
		int32 current = nodeIndex;
		while (current >= 0 && current < model.Bones.Count)
		{
			let bone = model.Bones[current];
			bone.UpdateLocalTransform();
			worldTransform = worldTransform * bone.LocalTransform;
			current = bone.ParentIndex;
		}

		return worldTransform;
	}

	private void ApplyTransform(StaticMesh mesh, Matrix transform)
	{
		if (mesh.Vertices == null)
			return;

		// Extract the normal matrix (inverse transpose of upper 3x3) for transforming normals/tangents
		Matrix normalMatrix;
		Matrix.Invert(transform, out normalMatrix);
		normalMatrix = Matrix.Transpose(normalMatrix);

		for (int32 i = 0; i < mesh.Vertices.VertexCount; i++)
		{
			// Transform position
			var pos = mesh.GetPosition(i);
			pos = Vector3.Transform(pos, transform);
			mesh.SetPosition(i, pos);

			// Transform normal
			var normal = mesh.GetNormal(i);
			normal = Vector3.Normalize(Vector3.TransformNormal(normal, normalMatrix));
			mesh.SetNormal(i, normal);

			// Transform tangent
			var tangent = mesh.GetTangent(i);
			tangent = Vector3.Normalize(Vector3.TransformNormal(tangent, normalMatrix));
			mesh.SetTangent(i, tangent);
		}
	}

	private void ApplyScale(StaticMesh mesh, float scale)
	{
		if (mesh.Vertices == null)
			return;

		for (int32 i = 0; i < mesh.Vertices.VertexCount; i++)
		{
			var pos = mesh.GetPosition(i);
			mesh.SetPosition(i, pos * scale);
		}
	}

	private void ApplyScaleSkinned(SkinnedMesh mesh, float scale)
	{
		for (int32 i = 0; i < mesh.VertexCount; i++)
		{
			var vertex = mesh.GetVertex(i);
			vertex.Position = vertex.Position * scale;
			mesh.SetVertex(i, vertex);
		}
	}
}
