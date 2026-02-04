namespace Sedulous.Editor.Scenes;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Editor.Core;

/// Camera mode for the scene editor.
enum EditorCameraMode
{
	Orbit,   // Orbit around a target point
	Fly      // Free fly camera (WASD + mouse)
}

/// Editor camera state.
class EditorCamera
{
	/// Camera position in world space.
	public Vector3 Position = .(0, 5, 10);

	/// Camera target (for orbit mode).
	public Vector3 Target = .Zero;

	/// Camera forward direction (normalized).
	public Vector3 Forward = .(0, 0, -1);

	/// Camera up direction.
	public Vector3 Up = .(0, 1, 0);

	/// Orbit distance from target.
	public float OrbitDistance = 10.0f;

	/// Orbit yaw angle (radians).
	public float OrbitYaw = 0.0f;

	/// Orbit pitch angle (radians).
	public float OrbitPitch = 0.3f;

	/// Field of view (radians).
	public float FieldOfView = Math.PI_f / 4.0f;

	/// Near clipping plane.
	public float NearPlane = 0.1f;

	/// Far clipping plane.
	public float FarPlane = 1000.0f;

	/// Current camera mode.
	public EditorCameraMode Mode = .Orbit;

	/// Movement speed (units per second).
	public float MoveSpeed = 10.0f;

	/// Rotation sensitivity.
	public float RotationSensitivity = 0.005f;

	/// Updates camera position from orbit parameters.
	public void UpdateFromOrbit()
	{
		// Calculate position on sphere around target
		let cosPitch = Math.Cos(OrbitPitch);
		let sinPitch = Math.Sin(OrbitPitch);
		let cosYaw = Math.Cos(OrbitYaw);
		let sinYaw = Math.Sin(OrbitYaw);

		Position = Target + Vector3(
			OrbitDistance * cosPitch * sinYaw,
			OrbitDistance * sinPitch,
			OrbitDistance * cosPitch * cosYaw
		);

		Forward = Vector3.Normalize(Target - Position);
	}

	/// Orbits the camera around the target.
	public void Orbit(float deltaYaw, float deltaPitch)
	{
		OrbitYaw += deltaYaw;
		OrbitPitch = Math.Clamp(OrbitPitch + deltaPitch, -Math.PI_f / 2.0f + 0.1f, Math.PI_f / 2.0f - 0.1f);
		UpdateFromOrbit();
	}

	/// Zooms the camera (changes orbit distance).
	public void Zoom(float delta)
	{
		OrbitDistance = Math.Max(0.5f, OrbitDistance - delta);
		UpdateFromOrbit();
	}

	/// Pans the camera (moves target in screen space).
	public void Pan(float deltaX, float deltaY)
	{
		let right = Vector3.Normalize(Vector3.Cross(Forward, Up));
		let up = Vector3.Normalize(Vector3.Cross(right, Forward));

		Target = Target + right * deltaX * OrbitDistance * 0.01f;
		Target = Target + up * deltaY * OrbitDistance * 0.01f;
		UpdateFromOrbit();
	}

	/// Focuses on a position.
	public void FocusOn(Vector3 position, float distance = 0)
	{
		Target = position;
		if (distance > 0)
			OrbitDistance = distance;
		UpdateFromOrbit();
	}

	/// Gets the view matrix.
	public Matrix GetViewMatrix()
	{
		return Matrix.CreateLookAt(Position, Position + Forward, Up);
	}

	/// Gets the projection matrix.
	public Matrix GetProjectionMatrix(float aspectRatio)
	{
		return Matrix.CreatePerspectiveFieldOfView(FieldOfView, aspectRatio, NearPlane, FarPlane);
	}
}

/// Gizmo mode for transform manipulation.
enum GizmoMode
{
	None,
	Translate,
	Rotate,
	Scale
}

/// Transform space for gizmo operations.
enum GizmoSpace
{
	Local,
	World
}

/// 3D viewport for scene editing.
/// Displays the scene from the editor camera and handles interaction.
class SceneEditorView : Control
{
	private SceneAssetDocument mDocument;
	private EditorCamera mCamera = new .() ~ delete _;

	// Gizmo state
	private GizmoMode mGizmoMode = .Translate;
	private GizmoSpace mGizmoSpace = .World;
	private bool mIsDraggingGizmo = false;

	// Mouse state for camera controls
	private bool mIsOrbiting = false;
	private bool mIsPanning = false;
	private float mLastMouseX = 0;
	private float mLastMouseY = 0;

	// Grid settings
	private bool mShowGrid = true;
	private float mGridSize = 1.0f;
	private int mGridLines = 20;

	// Selection outline
	private bool mShowSelectionOutline = true;

	public this(SceneAssetDocument document)
	{
		mDocument = document;
		mCamera.UpdateFromOrbit();

		// Set default background color
		Background = Color(64, 69, 74);
	}

	/// Gets the editor camera.
	public EditorCamera Camera => mCamera;

	/// Gets/sets the current gizmo mode.
	public GizmoMode CurrentGizmoMode
	{
		get => mGizmoMode;
		set => mGizmoMode = value;
	}

	/// Gets/sets the current gizmo space.
	public GizmoSpace CurrentGizmoSpace
	{
		get => mGizmoSpace;
		set => mGizmoSpace = value;
	}

	/// Gets/sets whether to show the grid.
	public bool ShowGrid
	{
		get => mShowGrid;
		set => mShowGrid = value;
	}

	/// Syncs the preview scene with the asset data.
	/// Called when the asset changes.
	public void SyncFromAsset()
	{
		// TODO: Create/update runtime preview scene from asset data
		// This requires RenderSystem integration
	}

	/// Focuses the camera on the selected entity.
	public void FocusOnSelection()
	{
		if (mDocument.SelectedEntities.Length > 0)
		{
			// Get first selected entity
			let entityId = mDocument.SelectedEntities[0];
			if (let entity = mDocument.SceneAsset.FindEntity(entityId))
			{
				mCamera.FocusOn(entity.Position, 5.0f);
			}
		}
	}

	/// Performs picking at the given screen coordinates.
	public Guid PickEntity(float screenX, float screenY)
	{
		// TODO: Implement raycasting against scene entities
		// For now return default (no selection)
		return default;
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Fill available space
		return .(constraints.MaxWidth, constraints.MaxHeight);
	}

	protected override void RenderOverride(DrawContext ctx)
	{
		let bounds = ArrangedBounds;

		// Draw background
		if (Background.A > 0)
			ctx.FillRect(bounds, Background);

		// Draw placeholder content
		DrawViewportInfo(ctx, bounds);
	}

	private void DrawViewportInfo(DrawContext ctx, RectangleF bounds)
	{
		// Draw grid placeholder lines
		if (mShowGrid)
		{
			DrawGridPlaceholder(ctx, bounds);
		}

		// Draw axis indicator in bottom-left
		DrawAxisIndicator(ctx, bounds);

		// Note: Text rendering requires CachedFont which needs font service
		// For now we just draw visual elements
	}

	private void DrawGridPlaceholder(DrawContext ctx, RectangleF bounds)
	{
		// Draw a simple 2D grid representation as placeholder
		let gridColor = Color(90, 95, 100);
		let axisColorX = Color(200, 50, 50);
		let axisColorZ = Color(50, 50, 200);

		let centerX = bounds.X + bounds.Width / 2;
		let centerY = bounds.Y + bounds.Height / 2 + 50;
		let gridSpacing = 30.0f;
		let halfLines = 5;

		// Draw grid lines
		for (int i = -halfLines; i <= halfLines; i++)
		{
			let offset = i * gridSpacing;

			// Horizontal lines
			let lineColor = (i == 0) ? axisColorX : gridColor;
			ctx.DrawLine(
				.(centerX - halfLines * gridSpacing, centerY + offset),
				.(centerX + halfLines * gridSpacing, centerY + offset),
				lineColor, 1.0f);

			// Vertical lines (representing Z)
			let vLineColor = (i == 0) ? axisColorZ : gridColor;
			ctx.DrawLine(
				.(centerX + offset, centerY - halfLines * gridSpacing),
				.(centerX + offset, centerY + halfLines * gridSpacing),
				vLineColor, 1.0f);
		}
	}

	private void DrawAxisIndicator(DrawContext ctx, RectangleF bounds)
	{
		// Draw a small axis indicator in bottom-left corner
		let originX = bounds.X + 40;
		let originY = bounds.Bottom - 40;
		let axisLength = 25.0f;

		// X axis (red, pointing right)
		ctx.DrawLine(.(originX, originY), .(originX + axisLength, originY), Color(220, 60, 60), 2.0f);

		// Y axis (green, pointing up)
		ctx.DrawLine(.(originX, originY), .(originX, originY - axisLength), Color(60, 220, 60), 2.0f);

		// Z axis (blue, pointing up-right for pseudo-3D)
		ctx.DrawLine(.(originX, originY), .(originX + axisLength * 0.7f, originY - axisLength * 0.7f), Color(60, 60, 220), 2.0f);
	}

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button == .Right)
		{
			mIsOrbiting = true;
			mLastMouseX = e.LocalX;
			mLastMouseY = e.LocalY;
			Context?.FocusManager?.SetFocus(this);
		}
		else if (e.Button == .Middle)
		{
			mIsPanning = true;
			mLastMouseX = e.LocalX;
			mLastMouseY = e.LocalY;
			Context?.FocusManager?.SetFocus(this);
		}
		else if (e.Button == .Left)
		{
			// TODO: Check for gizmo hit first
			// Then do picking
			let entityId = PickEntity(e.LocalX, e.LocalY);
			if (entityId != default)
			{
				// TODO: Check for shift key for multi-select
				mDocument.Select(entityId, false);
			}
			else
			{
				mDocument.ClearSelection();
			}
		}

		base.OnMouseDown(e);
	}

	protected override void OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Right)
		{
			mIsOrbiting = false;
		}
		else if (e.Button == .Middle)
		{
			mIsPanning = false;
		}

		base.OnMouseUp(e);
	}

	protected override void OnMouseMove(MouseEventArgs e)
	{
		if (mIsOrbiting)
		{
			let deltaX = e.LocalX - mLastMouseX;
			let deltaY = e.LocalY - mLastMouseY;
			mCamera.Orbit(-deltaX * mCamera.RotationSensitivity, -deltaY * mCamera.RotationSensitivity);
			mLastMouseX = e.LocalX;
			mLastMouseY = e.LocalY;
			// Visual update happens automatically on next render
		}
		else if (mIsPanning)
		{
			let deltaX = e.LocalX - mLastMouseX;
			let deltaY = e.LocalY - mLastMouseY;
			mCamera.Pan(-deltaX, deltaY);
			mLastMouseX = e.LocalX;
			mLastMouseY = e.LocalY;
			// Visual update happens automatically on next render
		}

		base.OnMouseMove(e);
	}

	protected override void OnMouseWheel(MouseWheelEventArgs e)
	{
		mCamera.Zoom(e.DeltaY * 0.5f);
		// Visual update happens automatically on next render
		base.OnMouseWheel(e);
	}

	protected override void OnKeyDown(KeyEventArgs e)
	{
		switch (e.Key)
		{
		case .F:
			FocusOnSelection();
		case .W:
			mGizmoMode = .Translate;
		case .E:
			mGizmoMode = .Rotate;
		case .R:
			mGizmoMode = .Scale;
		case .Q:
			mGizmoMode = .None;
		case .G:
			mShowGrid = !mShowGrid;
		case .X:
			mGizmoSpace = (mGizmoSpace == .World) ? .Local : .World;
		default:
		}

		base.OnKeyDown(e);
	}
}
