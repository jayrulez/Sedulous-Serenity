namespace Sedulous.Editor.Scenes;

using System;
using System.IO;
using System.Collections;
using Sedulous.Editor.Core;
using Sedulous.Foundation.Mathematics;
using Sedulous.Serialization;
using Sedulous.Xml;

/// Scene settings (ambient light, fog, etc.)
public struct SceneSettings
{
	public Color AmbientColor = .(0.1f, 0.1f, 0.15f, 1.0f);
	public bool FogEnabled = false;
	public Color FogColor = .(0.5f, 0.5f, 0.5f, 1.0f);
	public float FogDensity = 0.01f;
}

/// Editable scene asset.
public class SceneAsset : IAsset
{
	private Guid mAssetId;
	private String mName = new .() ~ delete _;
	private String mPath = new .() ~ delete _;
	private bool mIsDirty;

	/// Scene name.
	public String SceneName = new .() ~ delete _;

	/// Root entities in the scene.
	public List<EntityData> Entities = new .() ~ DeleteContainerAndItems!(_);

	/// Scene settings.
	public SceneSettings Settings;

	// IAsset implementation
	public Guid AssetId => mAssetId;
	public String Name => mName;
	public StringView AssetType => "scene";
	public String Path => mPath;
	public bool IsDirty => mIsDirty;

	public this()
	{
		mAssetId = Guid.Create();
	}

	public this(StringView name) : this()
	{
		mName.Set(name);
		SceneName.Set(name);
	}

	public void MarkDirty()
	{
		mIsDirty = true;
	}

	public void ClearDirty()
	{
		mIsDirty = false;
	}

	/// Set the path for this asset.
	public void SetPath(StringView path)
	{
		mPath.Set(path);

		// Update name from filename
		let filename = System.IO.Path.GetFileNameWithoutExtension(path, .. scope .());
		mName.Set(filename);
	}

	/// Load scene from file.
	public Result<void> Load(StringView path)
	{
		SetPath(path);

		// Try to load as XML first
		if (path.EndsWith(".scene", .OrdinalIgnoreCase) || path.EndsWith(".xml", .OrdinalIgnoreCase))
		{
			return LoadXml(path);
		}

		// Default to XML
		return LoadXml(path);
	}

	/// Save scene to file.
	public Result<void> Save(StringView path = default)
	{
		let savePath = path.IsEmpty ? mPath : scope String(path);

		if (savePath.IsEmpty)
			return .Err;

		// Save as XML
		if (SaveXml(savePath) case .Err)
			return .Err;

		if (!path.IsEmpty && !StringView(path).Equals(mPath, true))
			SetPath(path);

		ClearDirty();
		return .Ok;
	}

	/// Create a default empty scene.
	public void CreateDefault()
	{
		Entities.ClearAndDeleteItems();
		SceneName.Set(mName);
		Settings = .();

		// Add a default directional light
		let sunEntity = new EntityData("Sun");
		sunEntity.Position = .(0, 10, 0);
		sunEntity.Rotation = .(45, -30, 0);

		let lightComponent = new ComponentData("DirectionalLightComponent");
		lightComponent.SetProperty("Color", "1.0, 0.95, 0.9, 1.0");
		lightComponent.SetProperty("Intensity", "2.0");
		lightComponent.SetProperty("CastShadows", "true");
		sunEntity.Components.Add(lightComponent);

		Entities.Add(sunEntity);
	}

	// ===== Entity Management =====

	/// Find entity by ID.
	public EntityData FindEntity(Guid entityId)
	{
		for (let entity in Entities)
		{
			if (entity.EntityId == entityId)
				return entity;
		}
		return null;
	}

	/// Add a new entity.
	public EntityData AddEntity(StringView name, Guid parentId = default)
	{
		let entity = new EntityData(name);
		entity.ParentId = parentId;

		// Add to parent's child list if has parent
		if (parentId != default)
		{
			if (let parent = FindEntity(parentId))
				parent.ChildIds.Add(entity.EntityId);
		}

		Entities.Add(entity);
		MarkDirty();
		return entity;
	}

	/// Remove an entity.
	public void RemoveEntity(Guid entityId)
	{
		for (int i = 0; i < Entities.Count; i++)
		{
			if (Entities[i].EntityId == entityId)
			{
				let entity = Entities[i];

				// Remove from parent's child list
				if (entity.ParentId != default)
				{
					if (let parent = FindEntity(entity.ParentId))
						parent.ChildIds.Remove(entityId);
				}

				// Recursively remove children
				for (let childId in entity.ChildIds)
					RemoveEntity(childId);

				Entities.RemoveAt(i);
				delete entity;
				MarkDirty();
				return;
			}
		}
	}

	/// Duplicate an entity.
	public EntityData DuplicateEntity(Guid entityId)
	{
		let source = FindEntity(entityId);
		if (source == null)
			return null;

		let clone = source.Clone();
		clone.Name.Append(" Copy");

		Entities.Add(clone);
		MarkDirty();
		return clone;
	}

	// ===== Serialization =====

	private Result<void> LoadXml(StringView path)
	{
		// Read file content
		let content = scope String();
		if (File.ReadAllText(path, content) case .Err)
		{
			CreateDefault();
			return .Ok;
		}

		// Parse XML
		let doc = scope XmlDocument();
		if (doc.Parse(content) != .Ok)
		{
			CreateDefault();
			return .Ok;
		}

		// Get root element
		let root = doc.RootElement;
		if (root == null || root.TagName != "Scene")
		{
			CreateDefault();
			return .Ok;
		}

		// Read scene name
		let nameAttr = root.GetAttribute("name");
		if (!nameAttr.IsEmpty)
			SceneName.Set(nameAttr);

		// Clear existing entities
		Entities.ClearAndDeleteItems();

		// Parse Settings
		if (let settingsElem = root.GetFirstChildElement("Settings"))
		{
			ParseSettings(settingsElem);
		}

		// Parse Entities
		var child = root.FirstChildElement;
		while (child != null)
		{
			if (child.TagName == "Entity")
			{
				if (let entity = ParseEntity(child))
					Entities.Add(entity);
			}
			child = child.NextSiblingElement;
		}

		return .Ok;
	}

	private void ParseSettings(XmlElement element)
	{
		if (let ambientElem = element.GetFirstChildElement("AmbientColor"))
		{
			let text = scope String();
			ambientElem.GetInnerText(text);
			if (TryParseColor(text, let color))
				Settings.AmbientColor = color;
		}

		if (let fogElem = element.GetFirstChildElement("FogEnabled"))
		{
			let text = scope String();
			fogElem.GetInnerText(text);
			Settings.FogEnabled = text.Equals("true", .OrdinalIgnoreCase);
		}

		if (let fogColorElem = element.GetFirstChildElement("FogColor"))
		{
			let text = scope String();
			fogColorElem.GetInnerText(text);
			if (TryParseColor(text, let color))
				Settings.FogColor = color;
		}

		if (let fogDensityElem = element.GetFirstChildElement("FogDensity"))
		{
			let text = scope String();
			fogDensityElem.GetInnerText(text);
			if (float.Parse(text) case .Ok(let val))
				Settings.FogDensity = val;
		}
	}

	private EntityData ParseEntity(XmlElement element)
	{
		let entity = new EntityData();

		// Parse attributes
		let idAttr = element.GetAttribute("id");
		if (!idAttr.IsEmpty)
		{
			if (Guid.Parse(idAttr) case .Ok(let guid))
				entity.EntityId = guid;
		}

		let nameAttr = element.GetAttribute("name");
		if (!nameAttr.IsEmpty)
			entity.Name.Set(nameAttr);

		// Parse transform
		if (let posElem = element.GetFirstChildElement("Position"))
		{
			let text = scope String();
			posElem.GetInnerText(text);
			if (TryParseVector3(text, let vec))
				entity.Position = vec;
		}

		if (let rotElem = element.GetFirstChildElement("Rotation"))
		{
			let text = scope String();
			rotElem.GetInnerText(text);
			if (TryParseVector3(text, let vec))
				entity.Rotation = vec;
		}

		if (let scaleElem = element.GetFirstChildElement("Scale"))
		{
			let text = scope String();
			scaleElem.GetInnerText(text);
			if (TryParseVector3(text, let vec))
				entity.Scale = vec;
		}

		// Parse components
		var child = element.FirstChildElement;
		while (child != null)
		{
			if (child.TagName == "Component")
			{
				if (let component = ParseComponent(child))
					entity.Components.Add(component);
			}
			child = child.NextSiblingElement;
		}

		return entity;
	}

	private ComponentData ParseComponent(XmlElement element)
	{
		let component = new ComponentData();

		let typeAttr = element.GetAttribute("type");
		if (!typeAttr.IsEmpty)
			component.TypeName.Set(typeAttr);

		// Parse properties (child elements)
		var child = element.FirstChildElement;
		while (child != null)
		{
			let propName = child.TagName;
			let propValue = scope String();
			child.GetInnerText(propValue);
			component.SetProperty(propName, propValue);
			child = child.NextSiblingElement;
		}

		return component;
	}

	private bool TryParseVector3(StringView text, out Vector3 result)
	{
		result = .Zero;

		let parts = scope List<StringView>();
		for (var part in text.Split(','))
		{
			part.Trim();
			parts.Add(part);
		}

		if (parts.Count < 3)
			return false;

		if (float.Parse(parts[0]) case .Ok(let x))
			result.X = x;
		else
			return false;

		if (float.Parse(parts[1]) case .Ok(let y))
			result.Y = y;
		else
			return false;

		if (float.Parse(parts[2]) case .Ok(let z))
			result.Z = z;
		else
			return false;

		return true;
	}

	private bool TryParseColor(StringView text, out Color result)
	{
		result = Color.White;

		let parts = scope List<StringView>();
		for (var part in text.Split(','))
		{
			part.Trim();
			parts.Add(part);
		}

		if (parts.Count < 3)
			return false;

		float r = 1, g = 1, b = 1, a = 1;

		if (float.Parse(parts[0]) case .Ok(let rv))
			r = rv;
		else
			return false;

		if (float.Parse(parts[1]) case .Ok(let gv))
			g = gv;
		else
			return false;

		if (float.Parse(parts[2]) case .Ok(let bv))
			b = bv;
		else
			return false;

		if (parts.Count >= 4)
		{
			if (float.Parse(parts[3]) case .Ok(let av))
				a = av;
		}

		result = Color(r, g, b, a);
		return true;
	}

	private Result<void> SaveXml(StringView path)
	{
		// Create directory if needed
		let dirPath = scope String();
		System.IO.Path.GetDirectoryPath(path, dirPath);
		if (!dirPath.IsEmpty && !Directory.Exists(dirPath))
		{
			if (Directory.CreateDirectory(dirPath) case .Err)
				return .Err;
		}

		// Build XML content
		let xml = scope String();
		xml.Append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
		xml.AppendF("<Scene name=\"{}\" version=\"1\">\n", SceneName);

		// Settings
		xml.Append("    <Settings>\n");
		xml.AppendF("        <AmbientColor>{}, {}, {}, {}</AmbientColor>\n",
			Settings.AmbientColor.R / 255.0f, Settings.AmbientColor.G / 255.0f, Settings.AmbientColor.B / 255.0f, Settings.AmbientColor.A / 255.0f);
		xml.AppendF("        <FogEnabled>{}</FogEnabled>\n", Settings.FogEnabled ? "true" : "false");
		xml.Append("    </Settings>\n\n");

		// Entities
		for (let entity in Entities)
		{
			WriteEntityXml(xml, entity, 1);
		}

		xml.Append("</Scene>\n");

		// Write to file
		if (File.WriteAllText(path, xml) case .Err)
			return .Err;

		return .Ok;
	}

	private void WriteEntityXml(String xml, EntityData entity, int indent)
	{
		let indentStr = scope String();
		for (int i = 0; i < indent; i++)
			indentStr.Append("    ");

		let guidStr = scope String();
		entity.EntityId.ToString(guidStr);

		xml.AppendF("{}<Entity id=\"{}\" name=\"{}\">\n", indentStr, guidStr, entity.Name);
		xml.AppendF("{}    <Position>{}, {}, {}</Position>\n", indentStr, entity.Position.X, entity.Position.Y, entity.Position.Z);
		xml.AppendF("{}    <Rotation>{}, {}, {}</Rotation>\n", indentStr, entity.Rotation.X, entity.Rotation.Y, entity.Rotation.Z);
		xml.AppendF("{}    <Scale>{}, {}, {}</Scale>\n", indentStr, entity.Scale.X, entity.Scale.Y, entity.Scale.Z);

		// Components
		for (let component in entity.Components)
		{
			xml.AppendF("{}    <Component type=\"{}\">\n", indentStr, component.TypeName);
			for (let (key, val) in component.Properties)
			{
				xml.AppendF("{}        <{}>{}</{}>\n", indentStr, key, val, key);
			}
			xml.AppendF("{}    </Component>\n", indentStr);
		}

		xml.AppendF("{}</Entity>\n\n", indentStr);
	}
}
