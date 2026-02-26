namespace Tools.Common;

using System;
using Sedulous.Foundation.Mathematics;
using Sedulous.Render;

/// A 3D scale gizmo for scaling objects along axes.
/// Displays three colored lines with cube endpoints; dragging scales along that axis.
public class ScaleGizmo
{
	// Gizmo state
	public Vector3 Position = .Zero;
	public float Size = 1.0f;
	public GizmoAxis HoveredAxis = .None;
	public GizmoAxis SelectedAxis = .None;
	public bool IsDragging = false;

	// Drag state
	private Vector3 mDragStartPosition;
	private float mDragStartDistance;
	private Vector3 mDragAxisVector;

	/// Updates the gizmo hover state based on mouse position.
	/// Returns the hovered axis.
	public GizmoAxis UpdateHover(Ray pickRay, float pickThreshold = 0.15f)
	{
		if (IsDragging)
			return HoveredAxis;

		HoveredAxis = .None;
		float closestDist = float.MaxValue;

		// Test X axis
		float distX = TranslateGizmo.RayAxisDistance(pickRay, Position, .(1, 0, 0), Size);
		if (distX < pickThreshold && distX < closestDist)
		{
			closestDist = distX;
			HoveredAxis = .X;
		}

		// Test Y axis
		float distY = TranslateGizmo.RayAxisDistance(pickRay, Position, .(0, 1, 0), Size);
		if (distY < pickThreshold && distY < closestDist)
		{
			closestDist = distY;
			HoveredAxis = .Y;
		}

		// Test Z axis
		float distZ = TranslateGizmo.RayAxisDistance(pickRay, Position, .(0, 0, 1), Size);
		if (distZ < pickThreshold && distZ < closestDist)
		{
			closestDist = distZ;
			HoveredAxis = .Z;
		}

		return HoveredAxis;
	}

	/// Begins dragging on the currently hovered axis.
	public bool BeginDrag(Ray pickRay)
	{
		if (HoveredAxis == .None)
			return false;

		SelectedAxis = HoveredAxis;
		IsDragging = true;
		mDragStartPosition = Position;
		mDragAxisVector = GetAxisVector(SelectedAxis);

		// Get initial hit point and project onto axis to get start distance
		let hitPoint = TranslateGizmo.GetDragHitPoint(pickRay, SelectedAxis, mDragStartPosition);
		let local = hitPoint - mDragStartPosition;
		mDragStartDistance = Vector3.Dot(local, mDragAxisVector);

		// Avoid zero start distance (would cause division by zero)
		if (Math.Abs(mDragStartDistance) < 0.001f)
			mDragStartDistance = 0.001f;

		return true;
	}

	/// Updates the drag and returns scale factors per axis.
	/// Returns Vector3 where each component is the scale multiplier for that axis.
	/// Unaffected axes have value 1.0.
	public Vector3 UpdateDrag(Ray pickRay)
	{
		if (!IsDragging || SelectedAxis == .None)
			return .(1, 1, 1);

		// Get current hit point on same fixed drag plane
		let currentHitPoint = TranslateGizmo.GetDragHitPoint(pickRay, SelectedAxis, mDragStartPosition);
		let local = currentHitPoint - mDragStartPosition;
		let currentDistance = Vector3.Dot(local, mDragAxisVector);

		// Compute scale factor (clamped to avoid zero/negative)
		float scaleFactor = Math.Max(currentDistance / mDragStartDistance, 0.01f);

		// Return scale factors with 1.0 for unaffected axes
		switch (SelectedAxis)
		{
		case .X: return .(scaleFactor, 1, 1);
		case .Y: return .(1, scaleFactor, 1);
		case .Z: return .(1, 1, scaleFactor);
		default: return .(1, 1, 1);
		}
	}

	/// Ends the drag operation.
	public void EndDrag()
	{
		IsDragging = false;
		SelectedAxis = .None;
	}

	/// Draws the gizmo using the debug render feature.
	public void Draw(OverlayRenderFeature overlay)
	{
		let axisLength = Size;
		let cubeSize = Size * 0.08f;

		// X axis (red) — line + cube at endpoint
		let colorX = GetAxisColor(.X);
		let xEnd = Position + .(axisLength, 0, 0);
		overlay.AddLine(Position, xEnd, colorX, .Overlay);
		overlay.AddFilledBox(
			BoundingBox(xEnd - .(cubeSize, cubeSize, cubeSize), xEnd + .(cubeSize, cubeSize, cubeSize)),
			colorX, .Overlay);

		// Y axis (green) — line + cube at endpoint
		let colorY = GetAxisColor(.Y);
		let yEnd = Position + .(0, axisLength, 0);
		overlay.AddLine(Position, yEnd, colorY, .Overlay);
		overlay.AddFilledBox(
			BoundingBox(yEnd - .(cubeSize, cubeSize, cubeSize), yEnd + .(cubeSize, cubeSize, cubeSize)),
			colorY, .Overlay);

		// Z axis (blue) — line + cube at endpoint
		let colorZ = GetAxisColor(.Z);
		let zEnd = Position + .(0, 0, axisLength);
		overlay.AddLine(Position, zEnd, colorZ, .Overlay);
		overlay.AddFilledBox(
			BoundingBox(zEnd - .(cubeSize, cubeSize, cubeSize), zEnd + .(cubeSize, cubeSize, cubeSize)),
			colorZ, .Overlay);

		// Draw small center box
		let centerSize = Size * 0.08f;
		overlay.AddFilledBox(
			BoundingBox(Position - .(centerSize, centerSize, centerSize), Position + .(centerSize, centerSize, centerSize)),
			.(200, 200, 200, 255),
			.Overlay
		);
	}

	/// Gets the axis vector for a gizmo axis.
	private static Vector3 GetAxisVector(GizmoAxis axis)
	{
		switch (axis)
		{
		case .X: return .(1, 0, 0);
		case .Y: return .(0, 1, 0);
		case .Z: return .(0, 0, 1);
		default: return .(0, 1, 0);
		}
	}

	/// Gets the color for an axis based on hover/selection state.
	private Color GetAxisColor(GizmoAxis axis)
	{
		if (SelectedAxis == axis)
			return TranslateGizmo.sColorSelected;

		if (HoveredAxis == axis)
		{
			switch (axis)
			{
			case .X: return TranslateGizmo.sColorXHover;
			case .Y: return TranslateGizmo.sColorYHover;
			case .Z: return TranslateGizmo.sColorZHover;
			default: return .White;
			}
		}

		switch (axis)
		{
		case .X: return TranslateGizmo.sColorX;
		case .Y: return TranslateGizmo.sColorY;
		case .Z: return TranslateGizmo.sColorZ;
		default: return .White;
		}
	}
}
