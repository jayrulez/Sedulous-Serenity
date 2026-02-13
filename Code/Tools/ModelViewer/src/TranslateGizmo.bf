namespace ModelViewer;

using System;
using Sedulous.Mathematics;
using Sedulous.Render;

/// Represents which axis or plane of the gizmo is selected.
public enum GizmoAxis
{
	None,
	X,
	Y,
	Z,
	XY,  // XY plane
	XZ,  // XZ plane
	YZ   // YZ plane
}

/// A 3D translate gizmo for moving objects along axes.
public class TranslateGizmo
{
	// Gizmo state
	public Vector3 Position = .Zero;
	public float Size = 1.0f;
	public GizmoAxis HoveredAxis = .None;
	public GizmoAxis SelectedAxis = .None;
	public bool IsDragging = false;

	// Drag state
	private Vector3 mDragStartPosition;
	private Vector3 mDragStartHitPoint;

	// Colors
	private static readonly Color sColorX = Color(220, 50, 50, 255);
	private static readonly Color sColorY = Color(50, 220, 50, 255);
	private static readonly Color sColorZ = Color(50, 100, 220, 255);
	private static readonly Color sColorXHover = Color(255, 150, 150, 255);
	private static readonly Color sColorYHover = Color(150, 255, 150, 255);
	private static readonly Color sColorZHover = Color(150, 180, 255, 255);
	private static readonly Color sColorSelected = Color(255, 255, 100, 255);

	/// Creates a ray from camera through screen point.
	/// screenX, screenY: Screen coordinates (0,0 = top-left)
	/// width, height: Viewport dimensions
	/// viewMatrix, projMatrix: Camera matrices (projMatrix should NOT have Vulkan Y-flip)
	public static Ray CreatePickRay(float screenX, float screenY, uint32 width, uint32 height,
		Matrix viewMatrix, Matrix projMatrix)
	{
		// Convert screen to NDC (-1 to 1)
		float ndcX = (2.0f * screenX / (float)width) - 1.0f;
		float ndcY = 1.0f - (2.0f * screenY / (float)height);  // Flip Y (screen Y down -> NDC Y up)

		// Create points at near and far planes
		Vector4 nearPoint = .(ndcX, ndcY, 0.0f, 1.0f);
		Vector4 farPoint = .(ndcX, ndcY, 1.0f, 1.0f);

		// Unproject - use TryInvert to avoid divide by zero
		Matrix invViewProj;
		if (!Matrix.TryInvert(viewMatrix * projMatrix, out invViewProj))
		{
			// Matrix is degenerate, return a default forward ray
			return .(.(0, 0, 0), .(0, 0, -1));
		}

		var nearWorld = Vector4.Transform(nearPoint, invViewProj);
		var farWorld = Vector4.Transform(farPoint, invViewProj);

		// Perspective divide - check for near-zero W
		if (Math.Abs(nearWorld.W) < 0.0001f || Math.Abs(farWorld.W) < 0.0001f)
			return .(.(0, 0, 0), .(0, 0, -1));

		nearWorld /= nearWorld.W;
		farWorld /= farWorld.W;

		let position = Vector3(nearWorld.X, nearWorld.Y, nearWorld.Z);
		let dir = Vector3(farWorld.X, farWorld.Y, farWorld.Z) - position;

		// Check for zero-length direction
		let lenSq = dir.LengthSquared();
		if (lenSq < 0.0001f)
			return .(position, .(0, 0, -1));

		return .(position, dir / Math.Sqrt(lenSq));
	}

	/// Updates the gizmo hover state based on mouse position.
	/// Returns the hovered axis.
	public GizmoAxis UpdateHover(Ray pickRay, float pickThreshold = 0.15f)
	{
		if (IsDragging)
			return HoveredAxis;

		HoveredAxis = .None;
		float closestDist = float.MaxValue;

		// Test X axis
		float distX = RayAxisDistance(pickRay, Position, .(1, 0, 0), Size);
		if (distX < pickThreshold && distX < closestDist)
		{
			closestDist = distX;
			HoveredAxis = .X;
		}

		// Test Y axis
		float distY = RayAxisDistance(pickRay, Position, .(0, 1, 0), Size);
		if (distY < pickThreshold && distY < closestDist)
		{
			closestDist = distY;
			HoveredAxis = .Y;
		}

		// Test Z axis
		float distZ = RayAxisDistance(pickRay, Position, .(0, 0, 1), Size);
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

		// Calculate initial hit point on the drag plane/line (use current position)
		mDragStartHitPoint = GetDragHitPoint(pickRay, SelectedAxis, mDragStartPosition);

		return true;
	}

	/// Updates the drag and returns the new position delta.
	public Vector3 UpdateDrag(Ray pickRay)
	{
		if (!IsDragging || SelectedAxis == .None)
			return .Zero;

		// Get current hit point using the ORIGINAL drag start position for plane calculation
		// This prevents feedback loop where moving the gizmo moves the plane
		let currentHitPoint = GetDragHitPoint(pickRay, SelectedAxis, mDragStartPosition);

		// Calculate movement along the axis
		let delta = currentHitPoint - mDragStartHitPoint;

		// Constrain to selected axis
		Vector3 constrainedDelta = .Zero;
		switch (SelectedAxis)
		{
		case .X:
			constrainedDelta.X = delta.X;
		case .Y:
			constrainedDelta.Y = delta.Y;
		case .Z:
			constrainedDelta.Z = delta.Z;
		case .XY:
			constrainedDelta.X = delta.X;
			constrainedDelta.Y = delta.Y;
		case .XZ:
			constrainedDelta.X = delta.X;
			constrainedDelta.Z = delta.Z;
		case .YZ:
			constrainedDelta.Y = delta.Y;
			constrainedDelta.Z = delta.Z;
		default:
		}

		return constrainedDelta;
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
		let headSize = Size * 0.15f;

		// X axis (red)
		let colorX = GetAxisColor(.X);
		overlay.AddArrow(Position, Position + .(axisLength, 0, 0), colorX, headSize, .Overlay);

		// Y axis (green)
		let colorY = GetAxisColor(.Y);
		overlay.AddArrow(Position, Position + .(0, axisLength, 0), colorY, headSize, .Overlay);

		// Z axis (blue)
		let colorZ = GetAxisColor(.Z);
		overlay.AddArrow(Position, Position + .(0, 0, axisLength), colorZ, headSize, .Overlay);

		// Draw small center box
		let centerSize = Size * 0.08f;
		overlay.AddFilledBox(
			BoundingBox(Position - .(centerSize, centerSize, centerSize), Position + .(centerSize, centerSize, centerSize)),
			.(200, 200, 200, 255),
			.Overlay
		);
	}

	/// Gets the color for an axis based on hover/selection state.
	private Color GetAxisColor(GizmoAxis axis)
	{
		if (SelectedAxis == axis)
			return sColorSelected;

		if (HoveredAxis == axis)
		{
			switch (axis)
			{
			case .X: return sColorXHover;
			case .Y: return sColorYHover;
			case .Z: return sColorZHover;
			default: return .White;
			}
		}

		switch (axis)
		{
		case .X: return sColorX;
		case .Y: return sColorY;
		case .Z: return sColorZ;
		default: return .White;
		}
	}

	/// Calculates the closest distance from a ray to an axis line segment.
	private float RayAxisDistance(Ray ray, Vector3 axisOrigin, Vector3 axisDir, float axisLength)
	{
		// Find closest points between two lines
		let d1 = ray.Direction;
		let d2 = axisDir;
		let r = ray.Position - axisOrigin;

		let a = Vector3.Dot(d1, d1);
		let b = Vector3.Dot(d1, d2);
		let c = Vector3.Dot(d2, d2);
		let d = Vector3.Dot(d1, r);
		let e = Vector3.Dot(d2, r);

		let denom = a * c - b * b;

		float t1, t2;
		if (Math.Abs(denom) < 0.0001f)
		{
			// Lines are parallel
			t1 = 0;
			t2 = e / c;
		}
		else
		{
			t1 = (b * e - c * d) / denom;
			t2 = (a * e - b * d) / denom;
		}

		// Clamp t2 to axis segment (0 to 1)
		t2 = Math.Clamp(t2 / axisLength, 0.0f, 1.0f) * axisLength;
		t1 = Math.Max(t1, 0.0f);  // Ray can't go backwards

		let p1 = ray.Position + d1 * t1;
		let p2 = axisOrigin + d2 * t2;

		return Vector3.Distance(p1, p2);
	}

	/// Gets the hit point on a plane for dragging.
	/// planeOrigin: The point the plane passes through (use fixed position during drag to avoid feedback)
	private Vector3 GetDragHitPoint(Ray ray, GizmoAxis axis, Vector3 planeOrigin)
	{
		// For single-axis movement, we need to pick a plane that contains the axis
		// and is most perpendicular to the view direction
		Vector3 planeNormal;

		switch (axis)
		{
		case .X:
			// Use plane with normal that has least X component
			if (Math.Abs(ray.Direction.Y) > Math.Abs(ray.Direction.Z))
				planeNormal = .(0, 1, 0);
			else
				planeNormal = .(0, 0, 1);
		case .Y:
			if (Math.Abs(ray.Direction.X) > Math.Abs(ray.Direction.Z))
				planeNormal = .(1, 0, 0);
			else
				planeNormal = .(0, 0, 1);
		case .Z:
			if (Math.Abs(ray.Direction.X) > Math.Abs(ray.Direction.Y))
				planeNormal = .(1, 0, 0);
			else
				planeNormal = .(0, 1, 0);
		case .XY:
			planeNormal = .(0, 0, 1);
		case .XZ:
			planeNormal = .(0, 1, 0);
		case .YZ:
			planeNormal = .(1, 0, 0);
		default:
			return planeOrigin;
		}

		// Ray-plane intersection
		let denom = Vector3.Dot(planeNormal, ray.Direction);
		if (Math.Abs(denom) < 0.0001f)
			return planeOrigin;

		let t = Vector3.Dot(planeNormal, planeOrigin - ray.Position) / denom;
		return ray.Position + ray.Direction * t;
	}
}
