namespace Tools.Common;

using System;
using Sedulous.Mathematics;
using Sedulous.Render;

/// A 3D rotation gizmo for rotating objects around axes.
/// Displays three colored circles; dragging a circle rotates around that axis.
public class RotateGizmo
{
	// Gizmo state
	public Vector3 Position = .Zero;
	public float Size = 1.0f;
	public GizmoAxis HoveredAxis = .None;
	public GizmoAxis SelectedAxis = .None;
	public bool IsDragging = false;

	// Drag state
	private Vector3 mDragStartPosition;
	private float mDragStartAngle;
	private Vector3 mDragAxisVector;
	private Vector3 mDragRight;
	private Vector3 mDragForward;

	/// Updates the gizmo hover state based on mouse position.
	/// Returns the hovered axis.
	public GizmoAxis UpdateHover(Ray pickRay, float pickThreshold = 0.15f)
	{
		if (IsDragging)
			return HoveredAxis;

		HoveredAxis = .None;
		float closestDist = float.MaxValue;

		// Test each axis circle
		TestCircleHover(pickRay, .(1, 0, 0), .X, pickThreshold, ref closestDist);
		TestCircleHover(pickRay, .(0, 1, 0), .Y, pickThreshold, ref closestDist);
		TestCircleHover(pickRay, .(0, 0, 1), .Z, pickThreshold, ref closestDist);

		return HoveredAxis;
	}

	/// Tests hover against a single circle.
	private void TestCircleHover(Ray pickRay, Vector3 normal, GizmoAxis axis, float threshold, ref float closestDist)
	{
		// Intersect ray with the circle's plane
		let denom = Vector3.Dot(normal, pickRay.Direction);
		if (Math.Abs(denom) < 0.0001f)
			return; // Ray parallel to plane

		let t = Vector3.Dot(normal, Position - pickRay.Position) / denom;
		if (t < 0)
			return; // Behind camera

		let hitPoint = pickRay.Position + pickRay.Direction * t;
		let distFromCenter = Vector3.Distance(hitPoint, Position);

		// Distance from the circle perimeter
		let distFromCircle = Math.Abs(distFromCenter - Size);

		if (distFromCircle < threshold && distFromCircle < closestDist)
		{
			closestDist = distFromCircle;
			HoveredAxis = axis;
		}
	}

	/// Begins dragging on the currently hovered axis.
	public bool BeginDrag(Ray pickRay)
	{
		if (HoveredAxis == .None)
			return false;

		SelectedAxis = HoveredAxis;
		IsDragging = true;
		mDragStartPosition = Position;

		// Get axis vector and build 2D basis on the circle plane
		mDragAxisVector = GetAxisVector(SelectedAxis);
		BuildPlaneBasis(mDragAxisVector, out mDragRight, out mDragForward);

		// Compute start angle
		mDragStartAngle = GetAngleOnPlane(pickRay, mDragAxisVector, mDragStartPosition, mDragRight, mDragForward);

		return true;
	}

	/// Updates the drag and returns the delta rotation as a quaternion.
	public Quaternion UpdateDrag(Ray pickRay)
	{
		if (!IsDragging || SelectedAxis == .None)
			return .Identity;

		// Compute current angle using fixed plane at drag start position
		let currentAngle = GetAngleOnPlane(pickRay, mDragAxisVector, mDragStartPosition, mDragRight, mDragForward);
		let deltaAngle = currentAngle - mDragStartAngle;

		return Quaternion.CreateFromAxisAngle(mDragAxisVector, deltaAngle);
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
		let segments = 48;

		// X axis circle (red)
		let colorX = GetAxisColor(.X);
		overlay.AddCircle(Position, Size, .(1, 0, 0), colorX, segments, .Overlay);

		// Y axis circle (green)
		let colorY = GetAxisColor(.Y);
		overlay.AddCircle(Position, Size, .(0, 1, 0), colorY, segments, .Overlay);

		// Z axis circle (blue)
		let colorZ = GetAxisColor(.Z);
		overlay.AddCircle(Position, Size, .(0, 0, 1), colorZ, segments, .Overlay);
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

	/// Builds an orthonormal basis on a plane with the given normal.
	private static void BuildPlaneBasis(Vector3 normal, out Vector3 right, out Vector3 forward)
	{
		let up = Math.Abs(normal.Y) < 0.99f ? Vector3.UnitY : Vector3.UnitX;
		right = Vector3.Normalize(Vector3.Cross(up, normal));
		forward = Vector3.Cross(normal, right);
	}

	/// Computes the angle of the ray's hit point on a circle plane.
	private static float GetAngleOnPlane(Ray ray, Vector3 planeNormal, Vector3 planeOrigin, Vector3 right, Vector3 forward)
	{
		let denom = Vector3.Dot(planeNormal, ray.Direction);
		if (Math.Abs(denom) < 0.0001f)
			return 0;

		let t = Vector3.Dot(planeNormal, planeOrigin - ray.Position) / denom;
		let hitPoint = ray.Position + ray.Direction * Math.Max(t, 0.0f);
		let local = hitPoint - planeOrigin;

		return Math.Atan2(Vector3.Dot(local, forward), Vector3.Dot(local, right));
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
