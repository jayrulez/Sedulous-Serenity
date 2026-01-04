using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Models;

namespace Sedulous.Geometry.Tooling;

/// Result of converting a skinned model mesh.
struct SkinnedMeshConversionResult : IDisposable
{
	/// The converted skinned mesh (caller owns).
	public SkinnedMesh Mesh;

	/// Node-to-skeleton-bone mapping for animation channel remapping.
	/// Index by node index to get skeleton bone index (-1 if not a skin joint).
	public int32[] NodeToBoneMapping;

	public void Dispose() mut
	{
		if (NodeToBoneMapping != null)
		{
			delete NodeToBoneMapping;
			NodeToBoneMapping = null;
		}
		// Mesh is owned by caller
	}
}

/// Converts Model data to Geometry mesh data.
/// Handles joint index remapping so that vertex joint indices directly match skeleton bone indices.
static class ModelMeshConverter
{
	/// Converts a ModelMesh to a basic Mesh (non-skinned).
	public static Mesh ConvertToMesh(ModelMesh modelMesh)
	{
		if (modelMesh == null)
			return null;

		let mesh = new Mesh();
		mesh.SetupCommonVertexFormat();

		// Find vertex element offsets
		int32 posOffset = 0, normalOffset = 12, texCoordOffset = 24, colorOffset = 32, tangentOffset = 36;

		for (let element in modelMesh.VertexElements)
		{
			switch (element.Semantic)
			{
			case .Position: posOffset = element.Offset;
			case .Normal: normalOffset = element.Offset;
			case .TexCoord: texCoordOffset = element.Offset;
			case .Color: colorOffset = element.Offset;
			case .Tangent: tangentOffset = element.Offset;
			default:
			}
		}

		let srcData = modelMesh.GetVertexData();
		let srcStride = modelMesh.VertexStride;

		// Allocate and set vertices
		mesh.Vertices.Resize(modelMesh.VertexCount);

		for (int32 i = 0; i < modelMesh.VertexCount; i++)
		{
			uint8* v = srcData + i * srcStride;

			mesh.SetPosition(i, *(Vector3*)(v + posOffset));
			mesh.SetNormal(i, *(Vector3*)(v + normalOffset));
			mesh.SetUV(i, *(Vector2*)(v + texCoordOffset));
			mesh.SetColor(i, *(uint32*)(v + colorOffset));
			mesh.SetTangent(i, *(Vector3*)(v + tangentOffset));
		}

		// Copy indices
		if (modelMesh.IndexCount > 0)
		{
			mesh.Indices.Resize(modelMesh.IndexCount);
			let srcIdx = modelMesh.GetIndexData();

			if (modelMesh.Use32BitIndices)
			{
				let indices = (uint32*)srcIdx;
				for (int32 i = 0; i < modelMesh.IndexCount; i++)
					mesh.Indices.SetIndex(i, indices[i]);
			}
			else
			{
				let indices = (uint16*)srcIdx;
				for (int32 i = 0; i < modelMesh.IndexCount; i++)
					mesh.Indices.SetIndex(i, (uint32)indices[i]);
			}
		}

		// Add default submesh
		mesh.AddSubMesh(SubMesh(0, modelMesh.IndexCount));

		return mesh;
	}

	/// Converts a ModelMesh to a SkinnedMesh using the provided skin for joint mapping.
	/// The resulting mesh has joint indices that directly match the skeleton bone ordering.
	/// Returns the mesh and a node-to-bone mapping for animation channel remapping.
	public static Result<SkinnedMeshConversionResult> ConvertToSkinnedMesh(ModelMesh modelMesh, ModelSkin skin)
	{
		if (modelMesh == null)
			return .Err;

		if (skin == null || skin.Joints.Count == 0)
			return .Err;

		// Find vertex element offsets
		int32 posOffset = 0, normalOffset = 12, texCoordOffset = 24, colorOffset = 32, tangentOffset = 36;
		int32 jointsOffset = -1, weightsOffset = -1;

		for (let element in modelMesh.VertexElements)
		{
			switch (element.Semantic)
			{
			case .Position: posOffset = element.Offset;
			case .Normal: normalOffset = element.Offset;
			case .TexCoord: texCoordOffset = element.Offset;
			case .Color: colorOffset = element.Offset;
			case .Tangent: tangentOffset = element.Offset;
			case .Joints: jointsOffset = element.Offset;
			case .Weights: weightsOffset = element.Offset;
			}
		}

		if (jointsOffset < 0 || weightsOffset < 0)
			return .Err;  // No skinning data

		let skinnedMesh = new SkinnedMesh();
		let srcData = modelMesh.GetVertexData();
		let srcStride = modelMesh.VertexStride;

		skinnedMesh.ResizeVertices(modelMesh.VertexCount);

		for (int32 i = 0; i < modelMesh.VertexCount; i++)
		{
			uint8* v = srcData + i * srcStride;
			SkinnedVertex vertex = .();

			vertex.Position = *(Vector3*)(v + posOffset);
			vertex.Normal = *(Vector3*)(v + normalOffset);
			vertex.TexCoord = *(Vector2*)(v + texCoordOffset);
			vertex.Color = *(uint32*)(v + colorOffset);
			vertex.Tangent = *(Vector3*)(v + tangentOffset);

			// Joint indices are already indices into the skin's joints array,
			// which is exactly what we want for skeleton bone indices
			vertex.Joints = *(uint16[4]*)(v + jointsOffset);
			vertex.Weights = *(Vector4*)(v + weightsOffset);

			skinnedMesh.SetVertex(i, vertex);
		}

		// Copy indices
		if (modelMesh.IndexCount > 0)
		{
			skinnedMesh.ReserveIndices(modelMesh.IndexCount);
			let srcIdx = modelMesh.GetIndexData();

			if (modelMesh.Use32BitIndices)
			{
				let indices = (uint32*)srcIdx;
				for (int32 i = 0; i < modelMesh.IndexCount; i++)
					skinnedMesh.AddIndex(indices[i]);
			}
			else
			{
				let indices = (uint16*)srcIdx;
				for (int32 i = 0; i < modelMesh.IndexCount; i++)
					skinnedMesh.AddIndex((uint32)indices[i]);
			}
		}

		skinnedMesh.CalculateBounds();

		// Build node-to-bone mapping for animation channel remapping
		// This allows converting animation channel targets (node indices) to skeleton bone indices
		// We need to know the max node count to size the array properly
		int32 maxNodeIndex = 0;
		for (let nodeIdx in skin.Joints)
		{
			if (nodeIdx > maxNodeIndex)
				maxNodeIndex = nodeIdx;
		}

		let nodeToSkinJoint = new int32[maxNodeIndex + 1];
		for (int i = 0; i < nodeToSkinJoint.Count; i++)
			nodeToSkinJoint[i] = -1;

		for (int32 skinJointIdx = 0; skinJointIdx < skin.Joints.Count; skinJointIdx++)
		{
			let nodeIdx = skin.Joints[skinJointIdx];
			if (nodeIdx >= 0 && nodeIdx < nodeToSkinJoint.Count)
				nodeToSkinJoint[nodeIdx] = skinJointIdx;
		}

		return .Ok(.()
		{
			Mesh = skinnedMesh,
			NodeToBoneMapping = nodeToSkinJoint
		});
	}
}
