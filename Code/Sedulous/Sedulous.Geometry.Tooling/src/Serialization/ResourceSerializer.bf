using System;
using System.IO;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Imaging;
using Sedulous.Framework.Renderer;

namespace Sedulous.Geometry.Tooling;

/// Resource file type identifiers.
enum ResourceFileType
{
	Unknown,
	Mesh,
	SkinnedMesh,
	Skeleton,
	Animation,
	AnimationSet,
	Material,
	SkinnedMeshBundle  // Contains mesh + skeleton + animations together
}

/// Serializes and deserializes renderer resources to/from OpenDDL files.
static class ResourceSerializer
{
	public const int32 CurrentVersion = 1;

	/// Save a MeshResource to a file.
	public static Result<void> SaveMesh(MeshResource resource, StringView path)
	{
		if (resource?.Mesh == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = CurrentVersion;
		writer.Int32("version", ref version);

		int32 fileType = (int32)ResourceFileType.Mesh;
		writer.Int32("type", ref fileType);

		String name = scope String(resource.Name);
		writer.String("name", name);

		MeshSerializer.Serialize(writer, "mesh", resource.Mesh);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load a MeshResource from a file.
	public static Result<MeshResource> LoadMesh(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > CurrentVersion)
			return .Err;

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != (int32)ResourceFileType.Mesh)
			return .Err;

		String name = scope String();
		reader.String("name", name);

		if (MeshSerializer.Deserialize(reader, "mesh") case .Ok(let mesh))
		{
			let resource = new MeshResource(mesh, true);
			resource.Name.Set(name);
			return .Ok(resource);
		}

		return .Err;
	}

	/// Save a SkinnedMeshResource to a file (mesh only, no skeleton/animations).
	public static Result<void> SaveSkinnedMesh(SkinnedMeshResource resource, StringView path)
	{
		if (resource?.Mesh == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = CurrentVersion;
		writer.Int32("version", ref version);

		int32 fileType = (int32)ResourceFileType.SkinnedMesh;
		writer.Int32("type", ref fileType);

		String name = scope String(resource.Name);
		writer.String("name", name);

		SkinnedMeshSerializer.Serialize(writer, "mesh", resource.Mesh);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Save a SkinnedMeshResource bundle (mesh + skeleton + animations).
	public static Result<void> SaveSkinnedMeshBundle(SkinnedMeshResource resource, StringView path)
	{
		if (resource?.Mesh == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = CurrentVersion;
		writer.Int32("version", ref version);

		int32 fileType = (int32)ResourceFileType.SkinnedMeshBundle;
		writer.Int32("type", ref fileType);

		String name = scope String(resource.Name);
		writer.String("name", name);

		SkinnedMeshSerializer.Serialize(writer, "mesh", resource.Mesh);

		bool hasSkeleton = resource.Skeleton != null;
		writer.Bool("hasSkeleton", ref hasSkeleton);
		if (hasSkeleton)
		{
			SkeletonSerializer.Serialize(writer, "skeleton", resource.Skeleton);
		}

		int32 animCount = (int32)(resource.Animations?.Count ?? 0);
		writer.Int32("animationCount", ref animCount);
		if (animCount > 0)
		{
			AnimationSerializer.SerializeList(writer, "animations", resource.Animations);
		}

		let output = scope String();
		writer.GetOutput(output);

		let writeResult = File.WriteAllText(path, output);

		// Verify serialization by immediately deserializing and comparing
		if (writeResult == .Ok)
		{
			VerifySkinnedMeshBundle(resource, output);
		}

		return writeResult;
	}

	/// Verifies that serialization/deserialization produces matching data.
	private static void VerifySkinnedMeshBundle(SkinnedMeshResource original, StringView serializedText)
	{
		let doc = scope SerializerDataDescription();
		if (doc.ParseText(serializedText) != .Ok)
		{
			Console.WriteLine("VERIFY FAILED: Could not parse serialized text");
			return;
		}

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);

		int32 fileType = 0;
		reader.Int32("type", ref fileType);

		String name = scope String();
		reader.String("name", name);

		// Verify mesh
		if (SkinnedMeshSerializer.Deserialize(reader, "mesh") case .Ok(let loadedMesh))
		{
			defer delete loadedMesh;
			let origMesh = original.Mesh;

			Console.WriteLine("=== MESH VERIFICATION ===");
			Console.WriteLine(scope $"  Vertex count: orig={origMesh.VertexCount}, loaded={loadedMesh.VertexCount} {(origMesh.VertexCount == loadedMesh.VertexCount ? "OK" : "MISMATCH")}");
			Console.WriteLine(scope $"  Index count: orig={origMesh.IndexCount}, loaded={loadedMesh.IndexCount} {(origMesh.IndexCount == loadedMesh.IndexCount ? "OK" : "MISMATCH")}");

			// Compare first few vertices
			if (origMesh.VertexCount > 0 && loadedMesh.VertexCount > 0)
			{
				let origV = origMesh.Vertices[0];
				let loadV = loadedMesh.Vertices[0];
				Console.WriteLine("  First vertex comparison:");
				Console.WriteLine(scope $"    Position: orig=({origV.Position.X:0.###}, {origV.Position.Y:0.###}, {origV.Position.Z:0.###})");
				Console.WriteLine(scope $"              load=({loadV.Position.X:0.###}, {loadV.Position.Y:0.###}, {loadV.Position.Z:0.###})");
				Console.WriteLine(scope $"    Joints: orig=({origV.Joints[0]}, {origV.Joints[1]}, {origV.Joints[2]}, {origV.Joints[3]})");
				Console.WriteLine(scope $"            load=({loadV.Joints[0]}, {loadV.Joints[1]}, {loadV.Joints[2]}, {loadV.Joints[3]})");
				Console.WriteLine(scope $"    Weights: orig=({origV.Weights.X:0.###}, {origV.Weights.Y:0.###}, {origV.Weights.Z:0.###}, {origV.Weights.W:0.###})");
				Console.WriteLine(scope $"             load=({loadV.Weights.X:0.###}, {loadV.Weights.Y:0.###}, {loadV.Weights.Z:0.###}, {loadV.Weights.W:0.###})");

				// Check position match
				bool posMatch = Math.Abs(origV.Position.X - loadV.Position.X) < 0.001f &&
				                Math.Abs(origV.Position.Y - loadV.Position.Y) < 0.001f &&
				                Math.Abs(origV.Position.Z - loadV.Position.Z) < 0.001f;
				Console.WriteLine(scope $"    Position match: {(posMatch ? "OK" : "MISMATCH")}");

				// Check joints match
				bool jointsMatch = origV.Joints[0] == loadV.Joints[0] && origV.Joints[1] == loadV.Joints[1] &&
				                   origV.Joints[2] == loadV.Joints[2] && origV.Joints[3] == loadV.Joints[3];
				Console.WriteLine(scope $"    Joints match: {(jointsMatch ? "OK" : "MISMATCH")}");
			}
		}
		else
		{
			Console.WriteLine("VERIFY FAILED: Could not deserialize mesh");
		}

		// Verify skeleton
		bool hasSkeleton = false;
		reader.Bool("hasSkeleton", ref hasSkeleton);
		if (hasSkeleton && original.Skeleton != null)
		{
			if (SkeletonSerializer.Deserialize(reader, "skeleton") case .Ok(let loadedSkel))
			{
				defer delete loadedSkel;
				let origSkel = original.Skeleton;

				Console.WriteLine("=== SKELETON VERIFICATION ===");
				Console.WriteLine(scope $"  Bone count: orig={origSkel.BoneCount}, loaded={loadedSkel.BoneCount} {(origSkel.BoneCount == loadedSkel.BoneCount ? "OK" : "MISMATCH")}");

				// Compare first bone
				if (origSkel.BoneCount > 0 && loadedSkel.BoneCount > 0)
				{
					let origBone = origSkel.Bones[0];
					let loadBone = loadedSkel.Bones[0];
					Console.WriteLine(scope $"  First bone: orig='{origSkel.GetBoneName(0)}' parent={origBone.ParentIndex}");
					Console.WriteLine(scope $"              load='{loadedSkel.GetBoneName(0)}' parent={loadBone.ParentIndex}");

					// Compare inverse bind matrix
					let origIBM = origBone.InverseBindMatrix;
					let loadIBM = loadBone.InverseBindMatrix;
					Console.WriteLine(scope $"  InvBindMatrix row0: orig=({origIBM.M11:0.###}, {origIBM.M12:0.###}, {origIBM.M13:0.###}, {origIBM.M14:0.###})");
					Console.WriteLine(scope $"                      load=({loadIBM.M11:0.###}, {loadIBM.M12:0.###}, {loadIBM.M13:0.###}, {loadIBM.M14:0.###})");

					bool ibmMatch = Math.Abs(origIBM.M11 - loadIBM.M11) < 0.001f;
					Console.WriteLine(scope $"  InvBindMatrix match: {(ibmMatch ? "OK" : "MISMATCH")}");
				}
			}
			else
			{
				Console.WriteLine("VERIFY FAILED: Could not deserialize skeleton");
			}
		}

		// Verify animations
		int32 animCount = 0;
		reader.Int32("animationCount", ref animCount);
		if (animCount > 0 && original.Animations != null)
		{
			if (AnimationSerializer.DeserializeList(reader, "animations") case .Ok(let loadedAnims))
			{
				defer { for (let a in loadedAnims) delete a; delete loadedAnims; }

				Console.WriteLine("=== ANIMATION VERIFICATION ===");
				Console.WriteLine(scope $"  Animation count: orig={original.Animations.Count}, loaded={loadedAnims.Count} {(original.Animations.Count == loadedAnims.Count ? "OK" : "MISMATCH")}");

				if (original.Animations.Count > 0 && loadedAnims.Count > 0)
				{
					let origAnim = original.Animations[0];
					let loadAnim = loadedAnims[0];
					Console.WriteLine(scope $"  First animation: orig='{origAnim.Name}' duration={origAnim.Duration:0.###}s channels={origAnim.Channels.Count}");
					Console.WriteLine(scope $"                   load='{loadAnim.Name}' duration={loadAnim.Duration:0.###}s channels={loadAnim.Channels.Count}");

					if (origAnim.Channels.Count > 0 && loadAnim.Channels.Count > 0)
					{
						let origCh = origAnim.Channels[0];
						let loadCh = loadAnim.Channels[0];
						Console.WriteLine(scope $"  First channel: orig bone={origCh.BoneIndex} prop={origCh.Property} keys={origCh.Keyframes.Count}");
						Console.WriteLine(scope $"                 load bone={loadCh.BoneIndex} prop={loadCh.Property} keys={loadCh.Keyframes.Count}");

						// Check first keyframe
						if (origCh.Keyframes.Count > 0 && loadCh.Keyframes.Count > 0)
						{
							let origKey = origCh.Keyframes[0];
							let loadKey = loadCh.Keyframes[0];
							Console.WriteLine(scope $"  First keyframe: orig t={origKey.Time:0.###} v=({origKey.Value.X:0.###}, {origKey.Value.Y:0.###}, {origKey.Value.Z:0.###}, {origKey.Value.W:0.###})");
							Console.WriteLine(scope $"                  load t={loadKey.Time:0.###} v=({loadKey.Value.X:0.###}, {loadKey.Value.Y:0.###}, {loadKey.Value.Z:0.###}, {loadKey.Value.W:0.###})");

							bool keyMatch = Math.Abs(origKey.Time - loadKey.Time) < 0.001f &&
							                Math.Abs(origKey.Value.X - loadKey.Value.X) < 0.001f;
							Console.WriteLine(scope $"  First keyframe match: {(keyMatch ? "OK" : "MISMATCH")}");
						}
					}
				}
			}
			else
			{
				Console.WriteLine("VERIFY FAILED: Could not deserialize animations");
			}
		}

		Console.WriteLine("=== END VERIFICATION ===");
	}

	/// Load a SkinnedMeshResource bundle from a file.
	public static Result<SkinnedMeshResource> LoadSkinnedMeshBundle(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > CurrentVersion)
			return .Err;

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != (int32)ResourceFileType.SkinnedMeshBundle &&
			fileType != (int32)ResourceFileType.SkinnedMesh)
			return .Err;

		String name = scope String();
		reader.String("name", name);

		SkinnedMesh mesh = null;
		if (SkinnedMeshSerializer.Deserialize(reader, "mesh") case .Ok(let m))
			mesh = m;
		else
			return .Err;

		let resource = new SkinnedMeshResource(mesh, true);
		resource.Name.Set(name);

		// Try to load skeleton
		bool hasSkeleton = false;
		reader.Bool("hasSkeleton", ref hasSkeleton);
		if (hasSkeleton)
		{
			if (SkeletonSerializer.Deserialize(reader, "skeleton") case .Ok(let skeleton))
			{
				resource.SetSkeleton(skeleton, true);
			}
		}

		// Try to load animations
		int32 animCount = 0;
		reader.Int32("animationCount", ref animCount);
		if (animCount > 0)
		{
			if (AnimationSerializer.DeserializeList(reader, "animations") case .Ok(let anims))
			{
				resource.SetAnimations(anims, true);
			}
		}

		return .Ok(resource);
	}

	/// Save a SkeletonResource to a file.
	public static Result<void> SaveSkeleton(SkeletonResource resource, StringView path)
	{
		if (resource?.Skeleton == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = CurrentVersion;
		writer.Int32("version", ref version);

		int32 fileType = (int32)ResourceFileType.Skeleton;
		writer.Int32("type", ref fileType);

		String name = scope String(resource.Name);
		writer.String("name", name);

		SkeletonSerializer.Serialize(writer, "skeleton", resource.Skeleton);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load a SkeletonResource from a file.
	public static Result<SkeletonResource> LoadSkeleton(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > CurrentVersion)
			return .Err;

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != (int32)ResourceFileType.Skeleton)
			return .Err;

		String name = scope String();
		reader.String("name", name);

		if (SkeletonSerializer.Deserialize(reader, "skeleton") case .Ok(let skeleton))
		{
			let resource = new SkeletonResource(skeleton, true);
			resource.Name.Set(name);
			return .Ok(resource);
		}

		return .Err;
	}

	/// Save a MaterialDefinition to a file.
	public static Result<void> SaveMaterial(MaterialDefinition material, StringView path)
	{
		if (material == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = CurrentVersion;
		writer.Int32("version", ref version);

		int32 fileType = (int32)ResourceFileType.Material;
		writer.Int32("type", ref fileType);

		String name = scope String(material.Name);
		writer.String("name", name);

		// Write material properties
		float[4] baseColor = material.BaseColor;
		writer.FixedFloatArray("baseColor", &baseColor[0], 4);

		float metallic = material.Metallic;
		writer.Float("metallic", ref metallic);

		float roughness = material.Roughness;
		writer.Float("roughness", ref roughness);

		float[3] emissive = material.EmissiveFactor;
		writer.FixedFloatArray("emissiveFactor", &emissive[0], 3);

		bool doubleSided = material.DoubleSided;
		writer.Bool("doubleSided", ref doubleSided);

		int32 alphaMode = (int32)material.AlphaMode;
		writer.Int32("alphaMode", ref alphaMode);

		float alphaCutoff = material.AlphaCutoff;
		writer.Float("alphaCutoff", ref alphaCutoff);

		// Texture references
		String baseColorTex = scope String(material.BaseColorTexture);
		writer.String("baseColorTexture", baseColorTex);

		String normalTex = scope String(material.NormalTexture);
		writer.String("normalTexture", normalTex);

		String mrTex = scope String(material.MetallicRoughnessTexture);
		writer.String("metallicRoughnessTexture", mrTex);

		String occTex = scope String(material.OcclusionTexture);
		writer.String("occlusionTexture", occTex);

		String emissiveTex = scope String(material.EmissiveTexture);
		writer.String("emissiveTexture", emissiveTex);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load a MaterialDefinition from a file.
	public static Result<MaterialDefinition> LoadMaterial(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > CurrentVersion)
			return .Err;

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != (int32)ResourceFileType.Material)
			return .Err;

		let material = new MaterialDefinition();

		String name = scope String();
		reader.String("name", name);
		material.Name.Set(name);

		reader.FixedFloatArray("baseColor", &material.BaseColor[0], 4);
		reader.Float("metallic", ref material.Metallic);
		reader.Float("roughness", ref material.Roughness);
		reader.FixedFloatArray("emissiveFactor", &material.EmissiveFactor[0], 3);
		reader.Bool("doubleSided", ref material.DoubleSided);

		int32 alphaMode = 0;
		reader.Int32("alphaMode", ref alphaMode);
		material.AlphaMode = (AlphaMode)alphaMode;

		reader.Float("alphaCutoff", ref material.AlphaCutoff);

		reader.String("baseColorTexture", material.BaseColorTexture);
		reader.String("normalTexture", material.NormalTexture);
		reader.String("metallicRoughnessTexture", material.MetallicRoughnessTexture);
		reader.String("occlusionTexture", material.OcclusionTexture);
		reader.String("emissiveTexture", material.EmissiveTexture);

		return .Ok(material);
	}

	/// Save all resources from an import result to a directory.
	public static Result<void> SaveImportResult(ModelImportResult result, StringView outputDir)
	{
		// Ensure directory exists
		if (!Directory.Exists(outputDir))
		{
			if (Directory.CreateDirectory(outputDir) case .Err)
				return .Err;
		}

		// Save meshes
		for (let mesh in result.Meshes)
		{
			let path = scope String();
			path.AppendF("{}/{}.mesh", outputDir, mesh.Name);
			SanitizePath(path);
			SaveMesh(mesh, path);
		}

		// Save skinned meshes (as bundles)
		for (let mesh in result.SkinnedMeshes)
		{
			let path = scope String();
			path.AppendF("{}/{}.skinnedmesh", outputDir, mesh.Name);
			SanitizePath(path);
			SaveSkinnedMeshBundle(mesh, path);
		}

		// Save standalone skeletons
		for (let skeleton in result.Skeletons)
		{
			let path = scope String();
			path.AppendF("{}/{}.skeleton", outputDir, skeleton.Name);
			SanitizePath(path);
			SaveSkeleton(skeleton, path);
		}

		// Save materials
		for (let material in result.Materials)
		{
			let path = scope String();
			path.AppendF("{}/{}.material", outputDir, material.Name);
			SanitizePath(path);
			SaveMaterial(material, path);
		}

		// Note: Textures are saved as images, not OpenDDL
		// They can be saved separately using image encoders

		return .Ok;
	}

	private static void SanitizePath(String path)
	{
		// Replace invalid filename characters
		for (int i = 0; i < path.Length; i++)
		{
			char8 c = path[i];
			if (c == '<' || c == '>' || c == ':' || c == '"' || c == '|' || c == '?' || c == '*')
			{
				path[i] = '_';
			}
		}
	}
}
