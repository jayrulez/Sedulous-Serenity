namespace SceneEditor;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.GUI;
using Sedulous.Framework.Scenes;

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

	// Callbacks
	public delegate void() OnPropertyChanged ~ delete _;

	/// The root UI element to add to the layout.
	public Grid Root => mRoot;

	public this()
	{
		BuildUI();
	}

	// ==================== UI Construction ====================

	private void BuildUI()
	{
		mRoot = new Grid();
		mRoot.RowDefinitions.Add(new .() { Height = .Auto });  // header
		mRoot.RowDefinitions.Add(new .() { Height = .Star });  // property grid
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
					OnPropertyChanged?.Invoke();
				}
			});
		mRoot.AddChild(mPropertyGrid);
	}

	// ==================== Selection ====================

	/// Updates the inspector for the current tab and selection.
	public void RefreshForSelection(SceneTab tab)
	{
		mCurrentTab = tab;

		if (tab == null || tab.SelectedEntities.Count == 0)
		{
			mCurrentEntity = .Invalid;
			mPropertyGrid.Clear();
			mHeaderLabel.ContentText = "Inspector";
			return;
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
		mPropertyGrid.Clear();
		mHeaderLabel.ContentText = "Inspector";
	}

	// ==================== Property Building ====================

	private void BuildPropertiesForEntity(SceneTab tab, EntityId entity)
	{
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
		// Position X/Y/Z
		mPropertyGrid.AddFloatProperty("Position X", "Transform",
			new () => { return new box scene.GetTransform(entity).Position.X; },
			new (val) =>
			{
				if (let f = val as float?)
				{
					var pos = scene.GetTransform(entity).Position;
					pos.X = f;
					scene.SetPosition(entity, pos);
				}
			});

		mPropertyGrid.AddFloatProperty("Position Y", "Transform",
			new () => { return new box scene.GetTransform(entity).Position.Y; },
			new (val) =>
			{
				if (let f = val as float?)
				{
					var pos = scene.GetTransform(entity).Position;
					pos.Y = f;
					scene.SetPosition(entity, pos);
				}
			});

		mPropertyGrid.AddFloatProperty("Position Z", "Transform",
			new () => { return new box scene.GetTransform(entity).Position.Z; },
			new (val) =>
			{
				if (let f = val as float?)
				{
					var pos = scene.GetTransform(entity).Position;
					pos.Z = f;
					scene.SetPosition(entity, pos);
				}
			});

		// Rotation as Euler degrees
		mPropertyGrid.AddFloatProperty("Rotation X", "Transform",
			new () =>
			{
				let euler = QuaternionToEulerDegrees(scene.GetTransform(entity).Rotation);
				return new box euler.X;
			},
			new (val) =>
			{
				if (let f = val as float?)
				{
					var euler = QuaternionToEulerDegrees(scene.GetTransform(entity).Rotation);
					euler.X = f;
					scene.SetRotation(entity, EulerDegreesToQuaternion(euler));
				}
			});

		mPropertyGrid.AddFloatProperty("Rotation Y", "Transform",
			new () =>
			{
				let euler = QuaternionToEulerDegrees(scene.GetTransform(entity).Rotation);
				return new box euler.Y;
			},
			new (val) =>
			{
				if (let f = val as float?)
				{
					var euler = QuaternionToEulerDegrees(scene.GetTransform(entity).Rotation);
					euler.Y = f;
					scene.SetRotation(entity, EulerDegreesToQuaternion(euler));
				}
			});

		mPropertyGrid.AddFloatProperty("Rotation Z", "Transform",
			new () =>
			{
				let euler = QuaternionToEulerDegrees(scene.GetTransform(entity).Rotation);
				return new box euler.Z;
			},
			new (val) =>
			{
				if (let f = val as float?)
				{
					var euler = QuaternionToEulerDegrees(scene.GetTransform(entity).Rotation);
					euler.Z = f;
					scene.SetRotation(entity, EulerDegreesToQuaternion(euler));
				}
			});

		// Scale X/Y/Z
		mPropertyGrid.AddFloatProperty("Scale X", "Transform",
			new () => { return new box scene.GetTransform(entity).Scale.X; },
			new (val) =>
			{
				if (let f = val as float?)
				{
					var scale = scene.GetTransform(entity).Scale;
					scale.X = f;
					scene.SetScale(entity, scale);
				}
			});

		mPropertyGrid.AddFloatProperty("Scale Y", "Transform",
			new () => { return new box scene.GetTransform(entity).Scale.Y; },
			new (val) =>
			{
				if (let f = val as float?)
				{
					var scale = scene.GetTransform(entity).Scale;
					scale.Y = f;
					scene.SetScale(entity, scale);
				}
			});

		mPropertyGrid.AddFloatProperty("Scale Z", "Transform",
			new () => { return new box scene.GetTransform(entity).Scale.Z; },
			new (val) =>
			{
				if (let f = val as float?)
				{
					var scale = scene.GetTransform(entity).Scale;
					scale.Z = f;
					scene.SetScale(entity, scale);
				}
			});
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
}
