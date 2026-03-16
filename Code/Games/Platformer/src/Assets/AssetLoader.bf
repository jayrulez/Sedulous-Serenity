namespace Platformer.Assets;

using System;
using System.IO;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Geometry.Tooling;
using Sedulous.Geometry.Tooling.Resources;
using Sedulous.Resources;
using Sedulous.Core.Logging.Abstractions;
using Sedulous.Runtime;

/// Imports glTF models from the Kenney Platformer Kit asset pack and builds a ResourceRegistry.
/// The Framework's RenderSceneModule will automatically resolve ResourceRefs and upload to GPU.
class AssetLoader
{
	/// Stores ResourceRef for each loaded static model by a short key name.
	public struct MeshEntry
	{
		public Guid MeshId;
		public String MeshPath;
		public List<ResourceRef> MaterialRefs;
	}

	/// Stores ResourceRef for skinned (animated) models.
	public struct SkinnedMeshEntry
	{
		public Guid MeshId;
		public String MeshPath;
		public List<ResourceRef> MaterialRefs;
		public Guid SkeletonId;
		public String SkeletonPath;
		public List<ResourceRef> AnimationRefs;
	}

	private ILogger mLogger;
	private ResourceRegistry mRegistry = new .() ~ delete _;
	private Dictionary<String, MeshEntry> mMeshEntries = new .() ~ {
		for (var kv in _)
		{
			delete kv.key;
			delete kv.value.MeshPath;
			if (kv.value.MaterialRefs != null)
			{
				for (var r in kv.value.MaterialRefs)
					r.Dispose();
				delete kv.value.MaterialRefs;
			}
		}
		delete _;
	};

	private Dictionary<String, SkinnedMeshEntry> mSkinnedEntries = new .() ~ {
		for (var kv in _)
		{
			delete kv.key;
			delete kv.value.MeshPath;
			delete kv.value.SkeletonPath;
			if (kv.value.MaterialRefs != null)
			{
				for (var r in kv.value.MaterialRefs)
					r.Dispose();
				delete kv.value.MaterialRefs;
			}
			if (kv.value.AnimationRefs != null)
			{
				for (var r in kv.value.AnimationRefs)
					r.Dispose();
				delete kv.value.AnimationRefs;
			}
		}
		delete _;
	};

	private String mCacheDir = new .() ~ delete _;
	private String mAssetDir = new .() ~ delete _;

	public this(ILogger logger)
	{
		mLogger = logger;
	}

	/// Initialize the loader. Call before ImportAssets.
	public void Initialize(StringView assetDir, StringView cacheDir)
	{
		mLogger?.LogInformation("Initializing GLTF model support...");
		GltfModels.Initialize();
		mAssetDir.Set(assetDir);
		mCacheDir.Set(cacheDir);
		mLogger?.LogDebug("Asset dir = {}", assetDir);
		mLogger?.LogDebug("Cache dir = {}", cacheDir);
	}

	/// Import all game assets and register them with the resource system.
	public void ImportAssets(Context context)
	{
		let registryPath = scope String();
		registryPath.AppendF("{}/kenney2/registry.txt", mCacheDir);

		let cachePlatformer = scope String();
		cachePlatformer.AppendF("{}/kenney2", mCacheDir);

		// Check if cache exists
		if (File.Exists(registryPath))
		{
			mLogger?.LogDebug("Found cached registry at {}", registryPath);
			if (mRegistry.LoadFromFile(registryPath) case .Ok)
			{
				mLogger?.LogInformation("Loaded registry from cache: {} entries", mRegistry.Count);
				RecoverCachedPaths(cachePlatformer);
				context.Resources.AddRegistry(mRegistry);
				return;
			}
			else
			{
				mLogger?.LogError("Failed to load cached registry, will re-import");
			}
		}
		else
		{
			mLogger?.LogInformation("No cached registry found, importing fresh");
		}

		mLogger?.LogInformation("Importing models from Kenney Platformer Kit...");
		Directory.CreateDirectory(cachePlatformer);

		let basePath = scope String();
		basePath.AppendF("{}/samples/models/kenney_platformer-kit/Models/GLB format", mAssetDir);

		// Characters (skinned with animations) - 5 playable characters
		ImportSkinnedGltfModel(basePath, "character-oobi.glb", "character_oobi", cachePlatformer);
		ImportSkinnedGltfModel(basePath, "character-oodi.glb", "character_oodi", cachePlatformer);
		ImportSkinnedGltfModel(basePath, "character-ooli.glb", "character_ooli", cachePlatformer);
		ImportSkinnedGltfModel(basePath, "character-oopi.glb", "character_oopi", cachePlatformer);
		ImportSkinnedGltfModel(basePath, "character-oozi.glb", "character_oozi", cachePlatformer);

		// Enemies (skinned - reuse character models with different colors)
		ImportSkinnedGltfModel(basePath, "character-oozi.glb", "enemy_slime", cachePlatformer);
		ImportSkinnedGltfModel(basePath, "character-ooli.glb", "enemy_bee", cachePlatformer);
		ImportSkinnedGltfModel(basePath, "character-oodi.glb", "enemy_crab", cachePlatformer);
		ImportSkinnedGltfModel(basePath, "character-oobi.glb", "enemy_skull", cachePlatformer);

		// Tiles (blocks) - all use full-size block variants for consistent grid sizing
		ImportGltfModel(basePath, "block-grass.glb", "cube_grass", cachePlatformer);
		ImportGltfModel(basePath, "block-snow.glb", "cube_dirt", cachePlatformer);
		ImportGltfModel(basePath, "block-snow.glb", "cube_brick", cachePlatformer);
		ImportGltfModel(basePath, "crate.glb", "cube_crate", cachePlatformer);
		ImportGltfModel(basePath, "spike-block.glb", "cube_spike", cachePlatformer);
		ImportGltfModel(basePath, "crate-item.glb", "cube_question", cachePlatformer);
		ImportGltfModel(basePath, "crate-item-strong.glb", "cube_exclamation", cachePlatformer);

		// Moving platform
		ImportGltfModel(basePath, "block-moving.glb", "block_moving", cachePlatformer);

		// Level mechanics
		ImportGltfModel(basePath, "flag.glb", "goal_flag", cachePlatformer);
		ImportGltfModel(basePath, "door-open.glb", "door", cachePlatformer);
		ImportGltfModel(basePath, "spring.glb", "bouncer", cachePlatformer);
		ImportGltfModel(basePath, "trap-spikes.glb", "spikes", cachePlatformer);
		ImportGltfModel(basePath, "bomb.glb", "spikyball", cachePlatformer);
		ImportGltfModel(basePath, "saw.glb", "saw", cachePlatformer);
		ImportGltfModel(basePath, "pipe.glb", "cannon", cachePlatformer);
		ImportGltfModel(basePath, "bomb.glb", "cannonball", cachePlatformer);
		ImportGltfModel(basePath, "lever.glb", "lever", cachePlatformer);
		ImportGltfModel(basePath, "chest.glb", "chest", cachePlatformer);
		ImportGltfModel(basePath, "arrow.glb", "arrow", cachePlatformer);

		// Pickups
		ImportGltfModel(basePath, "coin-gold.glb", "coin", cachePlatformer);
		ImportGltfModel(basePath, "jewel.glb", "gem_blue", cachePlatformer);
		ImportGltfModel(basePath, "jewel.glb", "gem_green", cachePlatformer);
		ImportGltfModel(basePath, "jewel.glb", "gem_pink", cachePlatformer);
		ImportGltfModel(basePath, "heart.glb", "heart", cachePlatformer);
		ImportGltfModel(basePath, "key.glb", "key", cachePlatformer);
		ImportGltfModel(basePath, "star.glb", "star", cachePlatformer);

		// Nature / decorations
		ImportGltfModel(basePath, "tree.glb", "tree", cachePlatformer);
		ImportGltfModel(basePath, "hedge.glb", "bush", cachePlatformer);
		ImportGltfModel(basePath, "rocks.glb", "rock1", cachePlatformer);
		ImportGltfModel(basePath, "stones.glb", "rock2", cachePlatformer);
		ImportGltfModel(basePath, "grass.glb", "grass1", cachePlatformer);

		// Save registry
		Directory.CreateDirectory(scope String()..AppendF("{}/kenney2", mCacheDir));
		if (mRegistry.SaveToFile(registryPath) case .Ok)
			mLogger?.LogInformation("Registry saved with {} entries", mRegistry.Count);
		else
			mLogger?.LogError("Failed to save registry to cache");

		context.Resources.AddRegistry(mRegistry);
		mLogger?.LogInformation("Import complete - {} static meshes, {} skinned meshes", mMeshEntries.Count, mSkinnedEntries.Count);
	}

	/// Import placeholder colored cubes for all model keys (for gameplay tuning).
	public void ImportPlaceholderModels(Context context)
	{
		let registryPath = scope String();
		registryPath.AppendF("{}/placeholder/registry.txt", mCacheDir);

		let cachePlaceholder = scope String();
		cachePlaceholder.AppendF("{}/placeholder", mCacheDir);

		// Check if cache exists
		if (File.Exists(registryPath))
		{
			if (mRegistry.LoadFromFile(registryPath) case .Ok)
			{
				mLogger?.LogInformation("Loaded placeholder registry from cache: {} entries", mRegistry.Count);
				RecoverCachedPaths(cachePlaceholder);
				context.Resources.AddRegistry(mRegistry);
				return;
			}
			else
			{
				mLogger?.LogError("Failed to load cached placeholder registry, will re-create");
			}
		}

		mLogger?.LogInformation("Creating placeholder models (colored cubes)...");
		Directory.CreateDirectory(cachePlaceholder);

		// Tiles
		CreatePlaceholderModel(cachePlaceholder, "cube_grass", .(0.3f, 0.7f, 0.2f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "cube_dirt", .(0.5f, 0.35f, 0.15f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "cube_brick", .(0.7f, 0.3f, 0.2f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "cube_crate", .(0.8f, 0.5f, 0.1f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "cube_spike", .(0.9f, 0.1f, 0.1f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "cube_question", .(0.9f, 0.8f, 0.1f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "cube_exclamation", .(0.9f, 0.8f, 0.1f, 1.0f));

		// Characters (5 playable - will be used as static mesh fallback)
		CreatePlaceholderModel(cachePlaceholder, "character_oobi", .(0.5f, 0.2f, 0.7f, 1.0f));  // Purple
		CreatePlaceholderModel(cachePlaceholder, "character_oodi", .(0.9f, 0.4f, 0.6f, 1.0f));  // Pink
		CreatePlaceholderModel(cachePlaceholder, "character_ooli", .(0.9f, 0.6f, 0.2f, 1.0f));  // Orange
		CreatePlaceholderModel(cachePlaceholder, "character_oopi", .(0.2f, 0.7f, 0.7f, 1.0f));  // Teal
		CreatePlaceholderModel(cachePlaceholder, "character_oozi", .(0.6f, 0.4f, 0.2f, 1.0f));  // Brown

		// Enemies
		CreatePlaceholderModel(cachePlaceholder, "enemy_slime", .(0.6f, 0.4f, 0.2f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "enemy_bee", .(0.9f, 0.6f, 0.2f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "enemy_crab", .(0.9f, 0.4f, 0.6f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "enemy_skull", .(0.5f, 0.2f, 0.7f, 1.0f));

		// Pickups
		CreatePlaceholderModel(cachePlaceholder, "coin", .(1.0f, 0.85f, 0.0f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "key", .(1.0f, 0.85f, 0.0f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "star", .(1.0f, 0.85f, 0.0f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "gem_blue", .(0.1f, 0.3f, 0.9f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "gem_green", .(0.1f, 0.8f, 0.2f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "gem_pink", .(0.9f, 0.3f, 0.6f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "heart", .(0.9f, 0.1f, 0.2f, 1.0f));

		// Level mechanics
		CreatePlaceholderModel(cachePlaceholder, "goal_flag", .(1.0f, 1.0f, 1.0f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "door", .(0.4f, 0.25f, 0.1f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "bouncer", .(0.0f, 0.9f, 0.4f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "spikes", .(0.9f, 0.1f, 0.1f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "spikyball", .(0.7f, 0.0f, 0.0f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "saw", .(0.7f, 0.0f, 0.0f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "cannon", .(0.6f, 0.6f, 0.6f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "cannonball", .(0.6f, 0.6f, 0.6f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "lever", .(0.6f, 0.6f, 0.6f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "chest", .(0.6f, 0.6f, 0.6f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "arrow", .(0.6f, 0.6f, 0.6f, 1.0f));

		// Moving platform
		CreatePlaceholderModel(cachePlaceholder, "block_moving", .(0.3f, 0.6f, 0.9f, 1.0f));

		// Nature / decorations
		CreatePlaceholderModel(cachePlaceholder, "tree", .(0.15f, 0.5f, 0.1f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "bush", .(0.15f, 0.5f, 0.1f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "rock1", .(0.5f, 0.5f, 0.5f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "rock2", .(0.5f, 0.5f, 0.5f, 1.0f));
		CreatePlaceholderModel(cachePlaceholder, "grass1", .(0.15f, 0.5f, 0.1f, 1.0f));

		// Save registry
		Directory.CreateDirectory(scope String()..AppendF("{}/placeholder", mCacheDir));
		if (mRegistry.SaveToFile(registryPath) case .Ok)
			mLogger?.LogInformation("Placeholder registry saved with {} entries", mRegistry.Count);
		else
			mLogger?.LogError("Failed to save placeholder registry");

		context.Resources.AddRegistry(mRegistry);
		mLogger?.LogInformation("Placeholder import complete - {} static mesh entries", mMeshEntries.Count);
	}

	/// Creates a single placeholder colored cube model and registers it.
	private void CreatePlaceholderModel(StringView cacheBase, StringView key, Vector4 color)
	{
		let modelCacheDir = scope String();
		modelCacheDir.AppendF("{}/{}", cacheBase, key);
		Directory.CreateDirectory(modelCacheDir);

		// Create cube mesh resource
		let mesh = MeshBuilder.CreateCube(1.0f);
		let meshResource = new StaticMeshResource(mesh, true);
		meshResource.Name.Set("cube");

		let meshPath = scope String();
		meshPath.AppendF("{}/cube.mesh", modelCacheDir);
		ResourceSerializer.SanitizePath(meshPath);

		if (meshResource.SaveToFile(meshPath) case .Err)
		{
			mLogger?.LogError("Failed to save placeholder mesh for '{}'", key);
			delete meshResource;
			return;
		}
		mRegistry.Register(meshResource.Id, meshPath);

		// Create colored PBR material
		let material = Materials.CreatePBR("placeholder");
		material.SetDefaultFloat4("BaseColor", color);

		let matResource = new MaterialResource(material, true);
		matResource.Name.Set("placeholder");

		let matPath = scope String();
		matPath.AppendF("{}/placeholder.material", modelCacheDir);
		ResourceSerializer.SanitizePath(matPath);

		if (matResource.SaveToFile(matPath) case .Err)
		{
			mLogger?.LogError("Failed to save placeholder material for '{}'", key);
			delete meshResource;
			delete matResource;
			return;
		}
		mRegistry.Register(matResource.Id, matPath);

		// Store mesh entry
		let materialRefs = new List<ResourceRef>();
		materialRefs.Add(ResourceRef(matResource.Id, matPath));

		mMeshEntries[new String(key)] = .()
		{
			MeshId = meshResource.Id,
			MeshPath = new String(meshPath),
			MaterialRefs = materialRefs
		};

		// Write manifest for cache recovery
		WriteManifest(modelCacheDir, "type=static\nmesh=cube\nmaterial=placeholder\n");

		mLogger?.LogDebug("Placeholder: {} (color={},{},{},{})", key, color.X, color.Y, color.Z, color.W);

		delete meshResource;
		delete matResource;
	}

	private void ImportGltfModel(StringView assetBase, StringView relPath, StringView key, StringView cacheBase)
	{
		let modelPath = scope String();
		modelPath.AppendF("{}/{}", assetBase, relPath);

		let modelBaseDir = scope String();
		modelBaseDir.Set(modelPath);
		// Strip filename to get base directory
		let lastSlash = modelBaseDir.LastIndexOf('/');
		if (lastSlash >= 0)
			modelBaseDir.RemoveToEnd(lastSlash);

		if (!File.Exists(modelPath))
		{
			mLogger?.LogWarning("Model not found: {}", relPath);
			return;
		}

		let model = new Model();
		if (ModelLoaderFactory.LoadModel(modelPath, model) != .Ok)
		{
			mLogger?.LogError("Failed to load: {}", relPath);
			delete model;
			return;
		}
		defer delete model;

		let options = new ModelImportOptions();
		options.BasePath.Set(modelBaseDir);
		options.Flags = .Meshes | .Materials | .Textures;
		options.RecenterMeshes = true;

		let importer = scope ModelImporter(options);
		let result = importer.Import(model);
		defer delete result;

		// Save to cache subdirectory
		let modelCacheDir = scope String();
		modelCacheDir.AppendF("{}/{}", cacheBase, key);
		Directory.CreateDirectory(modelCacheDir);

		switch (ResourceSerializer.SaveImportResult(result, modelCacheDir))
		{
		case .Err:
			mLogger?.LogError("Failed to cache: {}", key);
			return;
		case .Ok(let resourceResult):
		{
			// Register resources and store entry
			let materialRefs = new List<ResourceRef>();

			for (let texture in resourceResult.Textures)
				RegisterResource(texture, modelCacheDir, "texture");

			for (let material in resourceResult.Materials)
			{
				RegisterResource(material, modelCacheDir, "material");
				let matPath = scope String();
				matPath.AppendF("{}/{}.material", modelCacheDir, material.Name);
				ResourceSerializer.SanitizePath(matPath);
				materialRefs.Add(ResourceRef(material.Id, matPath));
			}

			Guid meshId = .();
			String meshPath = null;

			for (let mesh in resourceResult.StaticMeshes)
			{
				RegisterResource(mesh, modelCacheDir, "mesh");
				if (meshPath == null)
				{
					meshPath = new String();
					meshPath.AppendF("{}/{}.mesh", modelCacheDir, mesh.Name);
					ResourceSerializer.SanitizePath(meshPath);
					meshId = mesh.Id;
				}
			}

			if (meshPath != null)
			{
				// Save manifest to preserve resource ordering
				let manifest = scope String();
				manifest.AppendF("type=static\nmesh={}\n", result.StaticMeshes[0].Name);
				for (let mat in result.Materials)
					manifest.AppendF("material={}\n", mat.Name);
				WriteManifest(modelCacheDir, manifest);

				let storedKey = new String(key);
				mMeshEntries[storedKey] = .()
				{
					MeshId = meshId,
					MeshPath = meshPath,
					MaterialRefs = materialRefs
				};
				mLogger?.LogDebug("Imported: {} ({} meshes, {} materials)", key, result.StaticMeshes.Count, result.Materials.Count);
			}
			else
			{
				for (var r in materialRefs)
					r.Dispose();
				delete materialRefs;
				mLogger?.LogWarning("No static meshes in: {}", key);
			}

			delete resourceResult;
		}
		}
	}

	private void ImportSkinnedGltfModel(StringView assetBase, StringView relPath, StringView key, StringView cacheBase)
	{
		let modelPath = scope String();
		modelPath.AppendF("{}/{}", assetBase, relPath);

		let modelBaseDir = scope String();
		modelBaseDir.Set(modelPath);
		let lastSlash = modelBaseDir.LastIndexOf('/');
		if (lastSlash >= 0)
			modelBaseDir.RemoveToEnd(lastSlash);

		if (!File.Exists(modelPath))
		{
			mLogger?.LogWarning("Model not found: {}", relPath);
			return;
		}

		let model = new Model();
		if (ModelLoaderFactory.LoadModel(modelPath, model) != .Ok)
		{
			mLogger?.LogError("Failed to load: {}", relPath);
			delete model;
			return;
		}
		defer delete model;

		let options = new ModelImportOptions();
		options.BasePath.Set(modelBaseDir);
		options.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Materials | .Textures;
		options.RecenterMeshes = true;

		let importer = scope ModelImporter(options);
		let result = importer.Import(model);
		defer delete result;

		let modelCacheDir = scope String();
		modelCacheDir.AppendF("{}/{}", cacheBase, key);
		Directory.CreateDirectory(modelCacheDir);

		switch (ResourceSerializer.SaveImportResult(result, modelCacheDir))
		{
		case .Err:
			mLogger?.LogError("Failed to cache skinned: {}", key);
			return;
		case .Ok(let resourceResult):
		{
			let materialRefs = new List<ResourceRef>();
			let animationRefs = new List<ResourceRef>();

			for (let texture in resourceResult.Textures)
				RegisterResource(texture, modelCacheDir, "texture");

			for (let material in resourceResult.Materials)
			{
				RegisterResource(material, modelCacheDir, "material");
				let matPath = scope String();
				matPath.AppendF("{}/{}.material", modelCacheDir, material.Name);
				ResourceSerializer.SanitizePath(matPath);
				materialRefs.Add(ResourceRef(material.Id, matPath));
			}

			// Register skeletons
			Guid skeletonId = .();
			String skeletonPath = null;
			for (let skeleton in resourceResult.Skeletons)
			{
				RegisterResource(skeleton, modelCacheDir, "skeleton");
				if (skeletonPath == null)
				{
					skeletonPath = new String();
					skeletonPath.AppendF("{}/{}.skeleton", modelCacheDir, skeleton.Name);
					ResourceSerializer.SanitizePath(skeletonPath);
					skeletonId = skeleton.Id;
				}
			}

			// Register animations
			for (let animation in resourceResult.Animations)
			{
				RegisterResource(animation, modelCacheDir, "animation");
				let animPath = scope String();
				animPath.AppendF("{}/{}.animation", modelCacheDir, animation.Name);
				ResourceSerializer.SanitizePath(animPath);
				animationRefs.Add(ResourceRef(animation.Id, animPath));
			}

			// Register skinned meshes
			Guid meshId = .();
			String meshPath = null;
			for (let mesh in resourceResult.SkinnedMeshes)
			{
				RegisterResource(mesh, modelCacheDir, "skinnedmesh");
				if (meshPath == null)
				{
					meshPath = new String();
					meshPath.AppendF("{}/{}.skinnedmesh", modelCacheDir, mesh.Name);
					ResourceSerializer.SanitizePath(meshPath);
					meshId = mesh.Id;
				}
			}

			if (meshPath != null)
			{
				// Save manifest to preserve resource ordering (uses plain result names)
				let manifest = scope String();
				manifest.AppendF("type=skinned\nmesh={}\n", result.SkinnedMeshes[0].Name);
				if (result.Skeletons.Count > 0)
					manifest.AppendF("skeleton={}\n", result.Skeletons[0].Name);
				for (let mat in result.Materials)
					manifest.AppendF("material={}\n", mat.Name);
				for (let anim in result.Animations)
					manifest.AppendF("animation={}\n", anim.Name);
				WriteManifest(modelCacheDir, manifest);

				let storedKey = new String(key);
				mSkinnedEntries[storedKey] = .()
				{
					MeshId = meshId,
					MeshPath = meshPath,
					MaterialRefs = materialRefs,
					SkeletonId = skeletonId,
					SkeletonPath = skeletonPath,
					AnimationRefs = animationRefs
				};
				mLogger?.LogDebug("Imported skinned: {} ({} meshes, {} skeletons, {} animations)", key, result.SkinnedMeshes.Count, result.Skeletons.Count, result.Animations.Count);
			}
			else
			{
				delete skeletonPath;
				for (var r in materialRefs)
					r.Dispose();
				delete materialRefs;
				for (var r in animationRefs)
					r.Dispose();
				delete animationRefs;
				mLogger?.LogWarning("No skinned meshes in: {}", key);
			}

			delete resourceResult;
		}
		}
	}

	/// Writes a manifest string to _manifest.txt in the given cache directory.
	private void WriteManifest(StringView cacheDir, StringView content)
	{
		let manifestPath = scope String();
		manifestPath.AppendF("{}/_manifest.txt", cacheDir);
		if (File.WriteAllText(manifestPath, content) case .Err)
			mLogger?.LogWarning("Failed to write manifest: {}", manifestPath);
	}

	/// Reads the manifest file to get ordered resource names.
	/// Returns true if manifest was found and parsed.
	private bool LoadManifest(StringView cacheDir, List<String> outMaterialNames, List<String> outAnimationNames)
	{
		let manifestPath = scope String();
		manifestPath.AppendF("{}/_manifest.txt", cacheDir);

		let content = scope String();
		if (File.ReadAllText(manifestPath, content) case .Err)
			return false;

		for (let lineView in content.Split('\n'))
		{
			let line = scope String(lineView);
			line.Trim();
			if (line.IsEmpty) continue;

			if (line.StartsWith("material="))
			{
				let name = new String(line, "material=".Length, line.Length - "material=".Length);
				outMaterialNames.Add(name);
			}
			else if (line.StartsWith("animation="))
			{
				let name = new String(line, "animation=".Length, line.Length - "animation=".Length);
				outAnimationNames.Add(name);
			}
		}
		return true;
	}

	/// Resolves material refs in manifest order for a cache directory.
	private void RecoverMaterialsOrdered(StringView dirPath, List<String> materialNames, List<ResourceRef> outRefs)
	{
		for (let matName in materialNames)
		{
			let matPath = scope String();
			matPath.AppendF("{}/{}.material", dirPath, matName);
			ResourceSerializer.SanitizePath(matPath);
			Guid matId;
			if (mRegistry.TryResolveId(matPath, out matId))
				outRefs.Add(ResourceRef(matId, matPath));
		}
	}

	/// Resolves animation refs in manifest order for a cache directory.
	private void RecoverAnimationsOrdered(StringView dirPath, List<String> animNames, List<ResourceRef> outRefs)
	{
		for (let animName in animNames)
		{
			let animPath = scope String();
			animPath.AppendF("{}/{}.animation", dirPath, animName);
			ResourceSerializer.SanitizePath(animPath);
			Guid animId;
			if (mRegistry.TryResolveId(animPath, out animId))
				outRefs.Add(ResourceRef(animId, animPath));
		}
	}

	/// Resolves material refs by filesystem enumeration (fallback when no manifest).
	private void RecoverMaterialsUnordered(StringView dirPath, List<ResourceRef> outRefs)
	{
		for (let matFile in Directory.EnumerateFiles(dirPath, "*.material"))
		{
			let matPath = scope String();
			matFile.GetFilePath(matPath);
			ResourceSerializer.SanitizePath(matPath);
			Guid matId;
			if (mRegistry.TryResolveId(matPath, out matId))
				outRefs.Add(ResourceRef(matId, matPath));
		}
	}

	/// Resolves animation refs by filesystem enumeration (fallback when no manifest).
	private void RecoverAnimationsUnordered(StringView dirPath, List<ResourceRef> outRefs)
	{
		for (let animFile in Directory.EnumerateFiles(dirPath, "*.animation"))
		{
			let animPath = scope String();
			animFile.GetFilePath(animPath);
			ResourceSerializer.SanitizePath(animPath);
			Guid animId;
			if (mRegistry.TryResolveId(animPath, out animId))
				outRefs.Add(ResourceRef(animId, animPath));
		}
	}

	private void RegisterResource(IResource resource, StringView cacheDir, StringView ext)
	{
		let path = scope String();
		path.AppendF("{}/{}.{}", cacheDir, resource.Name, ext);
		ResourceSerializer.SanitizePath(path);
		mRegistry.Register(resource.Id, path);
	}

	private void RecoverCachedPaths(StringView cachePlatformer)
	{
		// Scan cache directories to rebuild mesh entries from saved files
		for (let dir in Directory.EnumerateDirectories(cachePlatformer))
		{
			let dirName = scope String();
			dir.GetFileName(dirName);

			let dirPath = scope String();
			dir.GetFilePath(dirPath);
			ResourceSerializer.SanitizePath(dirPath);

			// Try to load manifest for correct ordering
			let matNames = scope List<String>();
			let animNames = scope List<String>();
			defer { ClearAndDeleteItems(matNames); ClearAndDeleteItems(animNames); }
			bool hasManifest = LoadManifest(dirPath, matNames, animNames);

			// Check for skinned mesh first
			bool hasSkinned = false;
			for (let file in Directory.EnumerateFiles(dirPath, "*.skinnedmesh"))
			{
				let filePath = scope String();
				file.GetFilePath(filePath);
				ResourceSerializer.SanitizePath(filePath);

				Guid meshId;
				if (mRegistry.TryResolveId(filePath, out meshId))
				{
					let materialRefs = new List<ResourceRef>();
					let animationRefs = new List<ResourceRef>();
					Guid skeletonId = .();
					String skeletonPath = null;

					// Materials: use manifest order if available
					if (hasManifest && matNames.Count > 0)
						RecoverMaterialsOrdered(dirPath, matNames, materialRefs);
					else
						RecoverMaterialsUnordered(dirPath, materialRefs);

					// Skeleton
					for (let skelFile in Directory.EnumerateFiles(dirPath, "*.skeleton"))
					{
						let skelPath = scope String();
						skelFile.GetFilePath(skelPath);
						ResourceSerializer.SanitizePath(skelPath);
						Guid skelId;
						if (mRegistry.TryResolveId(skelPath, out skelId) && skeletonPath == null)
						{
							skeletonId = skelId;
							skeletonPath = new String(skelPath);
						}
					}

					// Animations: use manifest order if available
					if (hasManifest && animNames.Count > 0)
						RecoverAnimationsOrdered(dirPath, animNames, animationRefs);
					else
						RecoverAnimationsUnordered(dirPath, animationRefs);

					let storedKey = new String(dirName);
					mSkinnedEntries[storedKey] = .()
					{
						MeshId = meshId,
						MeshPath = new String(filePath),
						MaterialRefs = materialRefs,
						SkeletonId = skeletonId,
						SkeletonPath = skeletonPath,
						AnimationRefs = animationRefs
					};
					hasSkinned = true;
				}
				else
				{
					mLogger?.LogWarning("Cache recovery: failed to resolve skinned mesh ID for '{}'", dirName);
				}
				break; // Take first skinned mesh per directory
			}

			if (hasSkinned)
				continue;

			// Static mesh fallback
			for (let file in Directory.EnumerateFiles(dirPath, "*.mesh"))
			{
				let filePath = scope String();
				file.GetFilePath(filePath);
				ResourceSerializer.SanitizePath(filePath);

				Guid meshId;
				if (mRegistry.TryResolveId(filePath, out meshId))
				{
					let storedKey = new String(dirName);
					let materialRefs = new List<ResourceRef>();

					// Materials: use manifest order if available
					if (hasManifest && matNames.Count > 0)
						RecoverMaterialsOrdered(dirPath, matNames, materialRefs);
					else
						RecoverMaterialsUnordered(dirPath, materialRefs);

					mMeshEntries[storedKey] = .()
					{
						MeshId = meshId,
						MeshPath = new String(filePath),
						MaterialRefs = materialRefs
					};
				}
				else
				{
					mLogger?.LogWarning("Cache recovery: failed to resolve mesh ID for '{}'", dirName);
				}
				break; // Take first mesh per directory
			}
		}
		mLogger?.LogInformation("Recovered {} static + {} skinned entries from cache", mMeshEntries.Count, mSkinnedEntries.Count);
	}

	private static void ClearAndDeleteItems(List<String> list)
	{
		for (let s in list)
			delete s;
		list.Clear();
	}

	/// Gets the ResourceRef for a static mesh by its key name (e.g., "cube_grass", "coin").
	public bool GetMeshRef(StringView key, out ResourceRef meshRef, out List<ResourceRef> materialRefs)
	{
		let keyStr = scope String(key);
		if (mMeshEntries.TryGetValue(keyStr, let entry))
		{
			meshRef = ResourceRef(entry.MeshId, entry.MeshPath);
			materialRefs = entry.MaterialRefs;
			return true;
		}
		mLogger?.LogWarning("Static mesh not found for key '{}'", key);
		meshRef = .();
		materialRefs = null;
		return false;
	}

	/// Gets the ResourceRef for a skinned mesh by its key name (e.g., "character_oobi", "enemy_slime").
	public bool GetSkinnedMeshRef(StringView key, out ResourceRef meshRef, out List<ResourceRef> materialRefs,
		out ResourceRef skeletonRef, out List<ResourceRef> animationRefs)
	{
		let keyStr = scope String(key);
		if (mSkinnedEntries.TryGetValue(keyStr, let entry))
		{
			meshRef = ResourceRef(entry.MeshId, entry.MeshPath);
			materialRefs = entry.MaterialRefs;
			skeletonRef = entry.SkeletonPath != null ? ResourceRef(entry.SkeletonId, entry.SkeletonPath) : .();
			animationRefs = entry.AnimationRefs;
			return true;
		}
		mLogger?.LogWarning("Skinned mesh not found for key '{}'", key);
		meshRef = .();
		materialRefs = null;
		skeletonRef = .();
		animationRefs = null;
		return false;
	}

	/// Gets a specific animation ResourceRef by name from a skinned mesh entry.
	/// The returned ResourceRef owns its Path string - caller must Dispose it.
	public bool GetAnimationRefByName(StringView meshKey, StringView animName, out ResourceRef animRef)
	{
		let keyStr = scope String(meshKey);
		if (mSkinnedEntries.TryGetValue(keyStr, let entry))
		{
			if (entry.AnimationRefs != null)
			{
				let suffix = scope String();
				suffix.AppendF("/{}.animation", animName);
				for (let aRef in entry.AnimationRefs)
				{
					if (aRef.Path != null && aRef.Path.EndsWith(suffix, .OrdinalIgnoreCase))
					{
						animRef = ResourceRef(aRef.Id, aRef.Path);
						return true;
					}
				}
			}
		}
		animRef = .();
		return false;
	}

	/// Gets the default animation name for a skinned mesh (first available "Idle", otherwise first clip).
	public bool GetDefaultAnimationRef(StringView meshKey, out ResourceRef animRef)
	{
		// Try Idle first
		if (GetAnimationRefByName(meshKey, "Idle", out animRef))
			return true;

		// Fall back to first animation
		let keyStr = scope String(meshKey);
		if (mSkinnedEntries.TryGetValue(keyStr, let entry))
		{
			if (entry.AnimationRefs != null && entry.AnimationRefs.Count > 0)
			{
				let first = entry.AnimationRefs[0];
				animRef = ResourceRef(first.Id, first.Path);
				return true;
			}
		}
		animRef = .();
		return false;
	}

	/// Gets all available mesh keys.
	public void GetAvailableKeys(List<String> outKeys)
	{
		for (let kv in mMeshEntries)
			outKeys.Add(kv.key);
		for (let kv in mSkinnedEntries)
			outKeys.Add(kv.key);
	}
}
