namespace SceneEditor;

using System;
using System.Collections;
using System.Reflection;
using Sedulous.Mathematics;
using Sedulous.GUI;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Physics;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.Serialization;

/// Encapsulates the inspector panel showing selected entity properties.
class InspectorPanel
{
	// UI elements
	private Grid mRoot;
	private PropertyGrid mPropertyGrid;
	private Label mHeaderLabel;

	// Current state
	private SceneTab mCurrentTab;
	private EntityId mCurrentEntity = .Invalid;
	private bool mShowingSceneSettings = false;

	// Render access
	private RenderSubsystem mRenderSubsystem;

	// Component type discovery
	private static List<Type> sComponentTypes ~ delete _;
	private ContextMenu mAddComponentMenu ~ delete _;

	// Callbacks
	public delegate void() OnPropertyChanged ~ delete _;

	/// The root UI element to add to the layout.
	public Grid Root => mRoot;

	public this(RenderSubsystem renderSubsystem)
	{
		mRenderSubsystem = renderSubsystem;
		BuildUI();
	}

	// ==================== UI Construction ====================

	private void BuildUI()
	{
		mRoot = new Grid();
		mRoot.RowDefinitions.Add(new .() { Height = .Auto });  // header
		mRoot.RowDefinitions.Add(new .() { Height = .Star });  // property grid
		mRoot.RowDefinitions.Add(new .() { Height = .Auto });  // add component button
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });
		mRoot.Background = Color(30, 30, 38, 255);

		// Header
		mHeaderLabel = new Label("Inspector");
		mHeaderLabel.FontSize = 13;
		mHeaderLabel.Foreground = Color(180, 180, 200, 255);
		mHeaderLabel.Padding = .(6, 4, 6, 4);
		GridProperties.SetRow(mHeaderLabel, 0);
		mRoot.AddChild(mHeaderLabel);

		// Property grid
		mPropertyGrid = new PropertyGrid();
		mPropertyGrid.NameColumnWidth = 90;
		GridProperties.SetRow(mPropertyGrid, 1);
		mPropertyGrid.PropertyChanged.Subscribe(new (pg, prop) =>
			{
				if (mCurrentTab != null)
				{
					mCurrentTab.MarkDirty();
					if (mShowingSceneSettings)
						SyncModuleSettingsToRuntime(mCurrentTab);
					OnPropertyChanged?.Invoke();
				}
			});
		// Context menu for component category headers (Remove Component)
		let categoryMenu = new ContextMenu();
		mPropertyGrid.ContextMenu = categoryMenu;
		mPropertyGrid.ContextMenuOpening.Subscribe(new (args) =>
			{
				if (!ShouldShowCategoryContextMenu())
					args.Cancel = true;
				else
					BuildCategoryContextMenu(args.Menu);
			});
		mRoot.AddChild(mPropertyGrid);

		// Add Component button
		let addCompBtn = new Button();
		addCompBtn.Content = new TextBlock("Add Component");
		addCompBtn.Margin = .(6, 4, 6, 6);
		addCompBtn.Click.Subscribe(new (btn) => ShowAddComponentMenu(btn));
		GridProperties.SetRow(addCompBtn, 2);
		mRoot.AddChild(addCompBtn);
	}

	// ==================== Selection ====================

	/// Updates the inspector for the current tab and selection.
	public void RefreshForSelection(SceneTab tab)
	{
		mCurrentTab = tab;

		if (tab == null)
		{
			mCurrentEntity = .Invalid;
			mShowingSceneSettings = false;
			mPropertyGrid.Clear();
			mHeaderLabel.ContentText = "Inspector";
			return;
		}

		if (tab.SelectedEntities.Count == 0)
		{
			// No entity selected — show scene settings
			mCurrentEntity = .Invalid;
			if (mShowingSceneSettings)
			{
				mPropertyGrid.RefreshValues();
				return;
			}
			mShowingSceneSettings = true;
			BuildSceneSettings(tab);
			return;
		}

		// Entity selected — switch out of scene settings mode if needed
		if (mShowingSceneSettings)
		{
			mShowingSceneSettings = false;
			mCurrentEntity = .Invalid;  // Force rebuild
		}

		let entity = tab.SelectedEntities[0];

		// Only rebuild if entity changed
		if (entity == mCurrentEntity)
		{
			// Just refresh values for live updates (e.g., gizmo manipulation)
			mPropertyGrid.RefreshValues();
			return;
		}

		mCurrentEntity = entity;
		BuildPropertiesForEntity(tab, entity);
	}

	/// Forces a full rebuild of the property grid.
	public void ForceRebuild()
	{
		if (mCurrentTab != null && mCurrentEntity.IsValid)
		{
			let entity = mCurrentEntity;
			mCurrentEntity = .Invalid;  // Force rebuild
			BuildPropertiesForEntity(mCurrentTab, entity);
			mCurrentEntity = entity;
		}
	}

	/// Clears the inspector (no tab/selection).
	public void Clear()
	{
		mCurrentTab = null;
		mCurrentEntity = .Invalid;
		mShowingSceneSettings = false;
		mPropertyGrid.Clear();
		mHeaderLabel.ContentText = "Inspector";
	}

	// ==================== Scene Settings ====================

	private void BuildSceneSettings(SceneTab tab)
	{
		mPropertyGrid.Clear();
		mHeaderLabel.ContentText = "Scene Settings";

		let scene = tab.Scene;
		if (scene == null)
			return;

		mPropertyGrid.BeginUpdate();

		// Scene name (read-only)
		mPropertyGrid.AddStringProperty("Name", "Scene",
			new () => new String(scene.Name),
			null);

		// Module settings via reflection
		for (let settingsType in Scene.SettingsTypes)
		{
			if (settingsType.GetCustomAttribute<ModuleSettingsAttribute>() case .Ok(let attr))
			{
				let settings = scene.GetModuleSettings(settingsType);
				if (settings != null)
					AddModuleSettingsProperties(settings, settingsType, attr.DisplayName);
			}
		}

		mPropertyGrid.EndUpdate();
	}

	/// Adds properties for a module settings class using reflection over its [Property]-tagged fields.
	private void AddModuleSettingsProperties(ISerializable settings, Type settingsType, StringView category)
	{
		let objPtr = Internal.UnsafeCastToPtr(settings);

		for (let field in settingsType.GetFields(.Instance | .Public))
		{
			if (!field.HasCustomAttribute<PropertyAttribute>())
				continue;

			let fieldType = field.FieldType;
			let offset = field.MemberOffset;

			if (fieldType == typeof(float))
			{
				mPropertyGrid.AddFloatProperty(field.Name, category,
					new [=objPtr, =offset]() =>
					{
						return new box *((float*)((uint8*)objPtr + offset));
					},
					new [=objPtr, =offset](val) =>
					{
						if (let f = val as float?)
							*((float*)((uint8*)objPtr + offset)) = f;
					});
			}
			else if (fieldType == typeof(int32))
			{
				mPropertyGrid.AddIntProperty(field.Name, category,
					new [=objPtr, =offset]() =>
					{
						return new box (int)*((int32*)((uint8*)objPtr + offset));
					},
					new [=objPtr, =offset](val) =>
					{
						if (let i = val as int?)
							*((int32*)((uint8*)objPtr + offset)) = (int32)i;
					});
			}
			else if (fieldType == typeof(bool))
			{
				mPropertyGrid.AddBoolProperty(field.Name, category,
					new [=objPtr, =offset]() =>
					{
						return new box *((bool*)((uint8*)objPtr + offset));
					},
					new [=objPtr, =offset](val) =>
					{
						if (let b = val as bool?)
							*((bool*)((uint8*)objPtr + offset)) = b;
					});
			}
			else if (fieldType == typeof(Vector3))
			{
				let item = new Vector3PropertyItem(field.Name,
					new [=objPtr, =offset]() =>
					{
						return *((Vector3*)((uint8*)objPtr + offset));
					},
					new [=objPtr, =offset](v) =>
					{
						*((Vector3*)((uint8*)objPtr + offset)) = v;
					});
				item.SetCategory(category);
				mPropertyGrid.AddItem(item);
			}
			else if (fieldType == typeof(Vector4))
			{
				let item = new Vector4PropertyItem(field.Name,
					new [=objPtr, =offset]() =>
					{
						return *((Vector4*)((uint8*)objPtr + offset));
					},
					new [=objPtr, =offset](v) =>
					{
						*((Vector4*)((uint8*)objPtr + offset)) = v;
					});
				item.SetCategory(category);
				mPropertyGrid.AddItem(item);
			}
			else if (fieldType.IsEnum)
			{
				let enumType = fieldType;
				let enumSize = enumType.Size;

				let names = scope List<StringView>();
				for (var e in Enum.GetEnumerator(enumType))
					names.Add(e.name);

				let item = new EnumPropertyItem(field.Name, names,
					new () =>
					{
						int64 rawVal = 0;
						Internal.MemCpy(&rawVal, (uint8*)objPtr + offset, enumSize);
						for (var e in Enum.GetEnumerator(enumType))
						{
							if (e.value == rawVal)
								return new String(e.name);
						}
						return new String("???");
					},
					new (name) =>
					{
						for (var e in Enum.GetEnumerator(enumType))
						{
							if (StringView(e.name) == name)
							{
								var val = e.value;
								Internal.MemCpy((uint8*)objPtr + offset, &val, enumSize);
								return;
							}
						}
					});
				item.SetCategory(category);
				mPropertyGrid.AddItem(item);
			}
		}
	}

	/// Pushes module settings values to the runtime systems for live preview.
	private void SyncModuleSettingsToRuntime(SceneTab tab)
	{
		let scene = tab.Scene;
		if (scene == null)
			return;

		// Render settings -> RenderWorld + SkyFeature
		if (let settings = scene.GetModuleSettings<RenderModuleSettings>())
		{
			let world = mRenderSubsystem?.GetWorld(scene);
			if (world != null)
			{
				world.AmbientColor = settings.AmbientColor;
				world.AmbientIntensity = settings.AmbientIntensity;
				world.Exposure = settings.Exposure;
			}

			if (let skyFeature = mRenderSubsystem?.RenderSystem?.GetFeature<SkyFeature>())
			{
				skyFeature.Mode = settings.SkyMode;
				var skyParams = ref skyFeature.SkyParams;
				skyParams.SunDirection = settings.SunDirection;
				skyParams.SunIntensity = settings.SunIntensity;
				skyParams.SunColor = settings.SunColor;
				skyParams.AtmosphereDensity = settings.AtmosphereDensity;
				skyParams.ZenithColor = settings.ZenithColor;
				skyParams.HorizonColor = settings.HorizonColor;
				skyParams.GroundColor = settings.GroundColor;
				skyParams.SolidColor = settings.SolidSkyColor;
			}
		}

		// Physics settings -> module
		if (let settings = scene.GetModuleSettings<PhysicsModuleSettings>())
		{
			let module = scene.GetModule<PhysicsSceneModule>();
			if (module != null)
				module.CollisionSteps = settings.CollisionSteps;
		}
	}

	// ==================== Property Building ====================

	/// Discovers all types with [Component] attribute. Called once on first use.
	private static void DiscoverComponentTypes()
	{
		if (sComponentTypes != null)
			return;

		sComponentTypes = new List<Type>();
		for (let type in Type.Types)
		{
			if (type.IsStruct && type.HasCustomAttribute<ComponentAttribute>())
				sComponentTypes.Add(type);
		}
	}

	private void BuildPropertiesForEntity(SceneTab tab, EntityId entity)
	{
		DiscoverComponentTypes();
		mPropertyGrid.Clear();

		let scene = tab.Scene;
		if (scene == null)
			return;

		let name = scene.GetName(entity);
		mHeaderLabel.ContentText = name.IsEmpty ? "Entity" : name;

		// Entity name property
		AddNameProperty(scene, entity);

		// Transform properties
		AddTransformProperties(scene, entity);

		// Component properties via reflection
		for (let compType in sComponentTypes)
		{
			if (scene.HasComponent(entity, compType))
				AddComponentProperties(scene, entity, compType);
		}
	}

	private void AddNameProperty(Scene scene, EntityId entity)
	{
		mPropertyGrid.AddStringProperty("Name", "Entity",
			new () => { return new String(scene.GetName(entity)); },
			new (val) =>
			{
				if (let str = val as String)
				{
					scene.SetName(entity, str);
					mHeaderLabel.ContentText = str;
				}
			});
	}

	private void AddTransformProperties(Scene scene, EntityId entity)
	{
		// Position
		let posItem = new Vector3PropertyItem("Position",
			new () => scene.GetTransform(entity).Position,
			new (v) => scene.SetPosition(entity, v));
		posItem.SetCategory("Transform");
		mPropertyGrid.AddItem(posItem);

		// Rotation (Euler degrees)
		let rotItem = new Vector3PropertyItem("Rotation",
			new () => QuaternionToEulerDegrees(scene.GetTransform(entity).Rotation),
			new (v) => scene.SetRotation(entity, EulerDegreesToQuaternion(v)));
		rotItem.SetCategory("Transform");
		mPropertyGrid.AddItem(rotItem);

		// Scale
		let scaleItem = new Vector3PropertyItem("Scale",
			new () => scene.GetTransform(entity).Scale,
			new (v) => scene.SetScale(entity, v));
		scaleItem.SetCategory("Transform");
		mPropertyGrid.AddItem(scaleItem);
	}

	// ==================== Component Properties (Reflection) ====================

	/// Gets a display-friendly name for a component type (e.g., "LightComponent" → "Light").
	private static void GetComponentDisplayName(Type type, String outName)
	{
		let typeName = type.GetName(.. scope .());
		if (typeName.EndsWith("Component"))
			outName.Append(typeName, 0, typeName.Length - 9);
		else
			outName.Append(typeName);
	}

	/// Adds properties for a component using reflection over its [Property]-tagged fields.
	private void AddComponentProperties(Scene scene, EntityId entity, Type compType)
	{
		let category = GetComponentDisplayName(compType, .. scope .());
		let dataPtr = scene.GetComponentRaw(entity, compType);
		if (dataPtr == null)
			return;

		for (let field in compType.GetFields(.Instance | .Public))
		{
			// Only show fields marked with [Property]
			if (!field.HasCustomAttribute<PropertyAttribute>())
				continue;

			let fieldType = field.FieldType;

			if (fieldType == typeof(float))
			{
				AddReflectedFloatProperty(scene, entity, compType, field, category);
			}
			else if (fieldType == typeof(bool))
			{
				AddReflectedBoolProperty(scene, entity, compType, field, category);
			}
			else if (fieldType == typeof(int32))
			{
				AddReflectedIntProperty(scene, entity, compType, field, category);
			}
			else if (fieldType == typeof(uint32))
			{
				AddReflectedUIntProperty(scene, entity, compType, field, category);
			}
			else if (fieldType.IsEnum)
			{
				AddReflectedEnumProperty(scene, entity, compType, field, category);
			}
			else if (fieldType == typeof(Vector2))
			{
				AddReflectedVector2Property(scene, entity, compType, field, category);
			}
			else if (fieldType == typeof(Vector3))
			{
				AddReflectedVector3Property(scene, entity, compType, field, category);
			}
			else if (fieldType == typeof(Vector4))
			{
				AddReflectedVector4Property(scene, entity, compType, field, category);
			}
			else if (fieldType == typeof(ResourceRef))
			{
				AddReflectedResourceRefProperty(scene, entity, compType, field, category);
			}
		}
	}

	private void AddReflectedFloatProperty(Scene scene, EntityId entity, Type compType, FieldInfo field, StringView category)
	{
		let offset = field.MemberOffset;
		mPropertyGrid.AddFloatProperty(field.Name, category,
			new () =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return new box 0.0f;
				return new box *((float*)((uint8*)ptr + offset));
			},
			new (obj) =>
			{
				if (let f = obj as float?)
				{
					let ptr = scene.GetComponentRaw(entity, compType);
					if (ptr != null)
					{
						*((float*)((uint8*)ptr + offset)) = f;
						scene.SetComponentRaw(entity, compType, ptr);
					}
				}
			});
	}

	private void AddReflectedBoolProperty(Scene scene, EntityId entity, Type compType, FieldInfo field, StringView category)
	{
		let offset = field.MemberOffset;
		mPropertyGrid.AddBoolProperty(field.Name, category,
			new () =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return new box false;
				return new box *((bool*)((uint8*)ptr + offset));
			},
			new (obj) =>
			{
				if (let b = obj as bool?)
				{
					let ptr = scene.GetComponentRaw(entity, compType);
					if (ptr != null)
					{
						*((bool*)((uint8*)ptr + offset)) = b;
						scene.SetComponentRaw(entity, compType, ptr);
					}
				}
			});
	}

	private void AddReflectedIntProperty(Scene scene, EntityId entity, Type compType, FieldInfo field, StringView category)
	{
		let offset = field.MemberOffset;
		mPropertyGrid.AddIntProperty(field.Name, category,
			new () =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return new box (int)0;
				return new box (int)*((int32*)((uint8*)ptr + offset));
			},
			new (obj) =>
			{
				if (let i = obj as int?)
				{
					let ptr = scene.GetComponentRaw(entity, compType);
					if (ptr != null)
					{
						*((int32*)((uint8*)ptr + offset)) = (int32)i;
						scene.SetComponentRaw(entity, compType, ptr);
					}
				}
			});
	}

	private void AddReflectedUIntProperty(Scene scene, EntityId entity, Type compType, FieldInfo field, StringView category)
	{
		let offset = field.MemberOffset;
		mPropertyGrid.AddIntProperty(field.Name, category,
			new () =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return new box (int)0;
				return new box (int)*((uint32*)((uint8*)ptr + offset));
			},
			new (obj) =>
			{
				if (let i = obj as int?)
				{
					let ptr = scene.GetComponentRaw(entity, compType);
					if (ptr != null)
					{
						*((uint32*)((uint8*)ptr + offset)) = (uint32)i;
						scene.SetComponentRaw(entity, compType, ptr);
					}
				}
			});
	}

	private void AddReflectedEnumProperty(Scene scene, EntityId entity, Type compType, FieldInfo field, StringView category)
	{
		let enumType = field.FieldType;
		let offset = field.MemberOffset;
		let enumSize = enumType.Size;

		// Collect enum value names
		let names = scope List<StringView>();
		for (var e in Enum.GetEnumerator(enumType))
			names.Add(e.name);

		let nameSpan = scope StringView[names.Count];
		for (let i < names.Count)
			nameSpan[i] = names[i];

		let item = new EnumPropertyItem(field.Name, nameSpan,
			new () =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return new String("???");
				let fieldPtr = (uint8*)ptr + offset;
				int64 rawVal = 0;
				Internal.MemCpy(&rawVal, fieldPtr, enumSize);
				for (var e in Enum.GetEnumerator(enumType))
				{
					if (e.value == rawVal)
						return new String(e.name);
				}
				return new String("???");
			},
			new (name) =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return;
				let fieldPtr = (uint8*)ptr + offset;
				for (var e in Enum.GetEnumerator(enumType))
				{
					if (StringView(e.name) == name)
					{
						var val = e.value;
						Internal.MemCpy(fieldPtr, &val, enumSize);
						scene.SetComponentRaw(entity, compType, ptr);
						return;
					}
				}
			});
		item.SetCategory(category);
		mPropertyGrid.AddItem(item);
	}

	private void AddReflectedVector2Property(Scene scene, EntityId entity, Type compType, FieldInfo field, StringView category)
	{
		let offset = field.MemberOffset;
		let item = new Vector2PropertyItem(field.Name,
			new () =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return .Zero;
				return *((Vector2*)((uint8*)ptr + offset));
			},
			new (v) =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr != null)
				{
					*((Vector2*)((uint8*)ptr + offset)) = v;
					scene.SetComponentRaw(entity, compType, ptr);
				}
			});
		item.SetCategory(category);
		mPropertyGrid.AddItem(item);
	}

	private void AddReflectedVector3Property(Scene scene, EntityId entity, Type compType, FieldInfo field, StringView category)
	{
		let offset = field.MemberOffset;
		let item = new Vector3PropertyItem(field.Name,
			new () =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return .Zero;
				return *((Vector3*)((uint8*)ptr + offset));
			},
			new (v) =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr != null)
				{
					*((Vector3*)((uint8*)ptr + offset)) = v;
					scene.SetComponentRaw(entity, compType, ptr);
				}
			});
		item.SetCategory(category);
		mPropertyGrid.AddItem(item);
	}

	private void AddReflectedVector4Property(Scene scene, EntityId entity, Type compType, FieldInfo field, StringView category)
	{
		let offset = field.MemberOffset;
		let item = new Vector4PropertyItem(field.Name,
			new () =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return .Zero;
				return *((Vector4*)((uint8*)ptr + offset));
			},
			new (v) =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr != null)
				{
					*((Vector4*)((uint8*)ptr + offset)) = v;
					scene.SetComponentRaw(entity, compType, ptr);
				}
			});
		item.SetCategory(category);
		mPropertyGrid.AddItem(item);
	}

	private void AddReflectedResourceRefProperty(Scene scene, EntityId entity, Type compType, FieldInfo field, StringView category)
	{
		let offset = field.MemberOffset;
		// Read-only display of the resource path (asset picker will come later)
		mPropertyGrid.AddStringProperty(field.Name, category,
			new () =>
			{
				let ptr = scene.GetComponentRaw(entity, compType);
				if (ptr == null) return new String("(none)");
				let resRef = (ResourceRef*)((uint8*)ptr + offset);
				if (resRef.HasPath)
					return new String(resRef.Path);
				else if (resRef.HasId)
				{
					let idStr = new String();
					resRef.Id.ToString(idStr);
					return idStr;
				}
				return new String("(none)");
			},
			null);  // Read-only for now — asset picker in future phase
	}

	// ==================== Euler <-> Quaternion ====================

	/// Converts a quaternion to Euler angles in degrees (pitch, yaw, roll = X, Y, Z).
	private static Vector3 QuaternionToEulerDegrees(Quaternion q)
	{
		// Roll (X-axis rotation)
		float sinr_cosp = 2.0f * (q.W * q.X + q.Y * q.Z);
		float cosr_cosp = 1.0f - 2.0f * (q.X * q.X + q.Y * q.Y);
		float roll = Math.Atan2(sinr_cosp, cosr_cosp);

		// Pitch (Y-axis rotation)
		float sinp = 2.0f * (q.W * q.Y - q.Z * q.X);
		float pitch;
		if (Math.Abs(sinp) >= 1.0f)
			pitch = sinp >= 0 ? Math.PI_f / 2.0f : -Math.PI_f / 2.0f;  // Gimbal lock
		else
			pitch = Math.Asin(sinp);

		// Yaw (Z-axis rotation)
		float siny_cosp = 2.0f * (q.W * q.Z + q.X * q.Y);
		float cosy_cosp = 1.0f - 2.0f * (q.Y * q.Y + q.Z * q.Z);
		float yaw = Math.Atan2(siny_cosp, cosy_cosp);

		let toDeg = 180.0f / Math.PI_f;
		return .(roll * toDeg, pitch * toDeg, yaw * toDeg);
	}

	/// Converts Euler angles in degrees (X=pitch, Y=yaw, Z=roll) to a quaternion.
	private static Quaternion EulerDegreesToQuaternion(Vector3 degrees)
	{
		let toRad = Math.PI_f / 180.0f;
		return Quaternion.CreateFromYawPitchRoll(degrees.Y * toRad, degrees.X * toRad, degrees.Z * toRad);
	}

	// ==================== Add / Remove Component ====================

	/// Checks whether the context menu should open for the currently hovered category.
	private bool ShouldShowCategoryContextMenu()
	{
		let hoveredName = mPropertyGrid.HoveredCategoryName;
		if (hoveredName == null)
			return false;

		let categoryName = hoveredName.Value;
		if (categoryName == "Transform" || categoryName == "Entity")
			return false;

		// Check that a matching component type exists
		DiscoverComponentTypes();
		for (let compType in sComponentTypes)
		{
			let displayName = GetComponentDisplayName(compType, .. scope .());
			if (displayName == categoryName)
				return true;
		}
		return false;
	}

	/// Populates the category context menu with a Remove item.
	private void BuildCategoryContextMenu(ContextMenu menu)
	{
		menu.ClearItems();

		let categoryName = mPropertyGrid.HoveredCategoryName.Value;

		DiscoverComponentTypes();
		for (let compType in sComponentTypes)
		{
			let displayName = GetComponentDisplayName(compType, .. scope .());
			if (displayName == categoryName)
			{
				let removeItem = menu.AddItem(scope $"Remove {categoryName}");
				let capturedType = compType;
				removeItem.Click.Subscribe(new (mi) =>
					{
						RemoveComponentFromSelected(capturedType);
					});
				break;
			}
		}
	}

	private void ShowAddComponentMenu(Button btn)
	{
		DiscoverComponentTypes();

		if (mCurrentTab == null || !mCurrentEntity.IsValid)
			return;

		let scene = mCurrentTab.Scene;
		if (scene == null)
			return;

		// Rebuild menu each time (components may have changed)
		if (mAddComponentMenu != null)
			delete mAddComponentMenu;
		mAddComponentMenu = new ContextMenu();

		bool anyAdded = false;
		for (let compType in sComponentTypes)
		{
			if (!scene.HasComponent(mCurrentEntity, compType))
			{
				let displayName = GetComponentDisplayName(compType, .. scope .());
				let menuItem = mAddComponentMenu.AddItem(displayName);
				let capturedType = compType;
				menuItem.Click.Subscribe(new (mi) =>
					{
						AddComponentToSelected(capturedType);
					});
				anyAdded = true;
			}
		}

		if (!anyAdded)
		{
			let item = mAddComponentMenu.AddItem("(all components present)");
			item.IsEnabled = false;
		}

		if (mAddComponentMenu.Context == null)
			mAddComponentMenu.OnAttachedToContext(btn.Context);

		let bounds = btn.ArrangedBounds;
		mAddComponentMenu.Show(btn, .(bounds.X, bounds.Bottom));
	}

	private void AddComponentToSelected(Type compType)
	{
		if (mCurrentTab == null || !mCurrentEntity.IsValid)
			return;

		let scene = mCurrentTab.Scene;
		if (scene == null)
			return;

		scene.AddDefaultComponent(mCurrentEntity, compType);
		mCurrentTab.MarkDirty();

		// Force rebuild inspector
		let entity = mCurrentEntity;
		mCurrentEntity = .Invalid;
		BuildPropertiesForEntity(mCurrentTab, entity);
		mCurrentEntity = entity;

		OnPropertyChanged?.Invoke();
	}

	/// Removes a component type from the currently selected entity.
	public void RemoveComponentFromSelected(Type compType)
	{
		if (mCurrentTab == null || !mCurrentEntity.IsValid)
			return;

		let scene = mCurrentTab.Scene;
		if (scene == null)
			return;

		scene.RemoveComponent(mCurrentEntity, compType);
		mCurrentTab.MarkDirty();

		// Force rebuild inspector
		let entity = mCurrentEntity;
		mCurrentEntity = .Invalid;
		BuildPropertiesForEntity(mCurrentTab, entity);
		mCurrentEntity = entity;

		OnPropertyChanged?.Invoke();
	}
}
