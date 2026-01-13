namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// A single point in a particle trail.
struct TrailPoint
{
	/// Position in world space.
	public Vector3 Position;

	/// Width at this point.
	public float Width;

	/// Color at this point.
	public Color Color;

	/// Time when this point was created.
	public float Time;

	/// Direction of movement (for orientation).
	public Vector3 Direction;

	/// Default constructor.
	public this()
	{
		Position = .Zero;
		Width = 1.0f;
		Color = .White;
		Time = 0;
		Direction = .Zero;
	}

	public this(Vector3 position, float width, Color color, float time, Vector3 direction)
	{
		Position = position;
		Width = width;
		Color = color;
		Time = time;
		Direction = direction;
	}
}

/// GPU vertex format for trail rendering.
[CRepr]
struct TrailVertex
{
	/// Position in world space.
	public Vector3 Position;

	/// Texture coordinate (U = along trail, V = across trail).
	public Vector2 TexCoord;

	/// Vertex color with alpha.
	public Color Color;

	/// Total size: 12 + 8 + 4 = 24 bytes

	public this(Vector3 position, Vector2 texCoord, Color color)
	{
		Position = position;
		TexCoord = texCoord;
		Color = color;
	}
}

/// Manages trail data for a single particle.
class ParticleTrail
{
	/// Maximum number of points in this trail.
	public int32 MaxPoints;

	/// Circular buffer of trail points.
	private TrailPoint[] mPoints ~ delete _;

	/// Index of the head (newest point).
	private int32 mHead = 0;

	/// Number of active points.
	private int32 mCount = 0;

	/// Minimum distance before adding a new point.
	public float MinVertexDistance = 0.1f;

	/// Last position where a point was added.
	private Vector3 mLastPosition = .Zero;

	/// Whether this trail has been initialized with a position.
	private bool mInitialized = false;

	public this(int32 maxPoints = 20)
	{
		MaxPoints = maxPoints;
		mPoints = new TrailPoint[maxPoints];
	}

	/// Number of active points in the trail.
	public int32 PointCount => mCount;

	/// Whether the trail has any points.
	public bool HasPoints => mCount > 0;

	/// Adds a new point to the trail if distance threshold is met.
	/// Returns true if a point was added.
	public bool TryAddPoint(Vector3 position, float width, Color color, float time)
	{
		if (!mInitialized)
		{
			mLastPosition = position;
			mInitialized = true;
		}

		// Check distance threshold
		float distance = Vector3.Distance(position, mLastPosition);
		if (distance < MinVertexDistance && mCount > 0)
			return false;

		// Calculate direction
		Vector3 direction = .Zero;
		if (distance > 0.001f)
			direction = (position - mLastPosition) / distance;

		// Add point
		mPoints[mHead] = .(position, width, color, time, direction);
		mHead = (mHead + 1) % MaxPoints;
		mCount = Math.Min(mCount + 1, MaxPoints);
		mLastPosition = position;

		return true;
	}

	/// Forces adding a point regardless of distance.
	public void ForceAddPoint(Vector3 position, float width, Color color, float time)
	{
		Vector3 direction = .Zero;
		if (mInitialized)
		{
			float distance = Vector3.Distance(position, mLastPosition);
			if (distance > 0.001f)
				direction = (position - mLastPosition) / distance;
		}
		else
		{
			mInitialized = true;
		}

		mPoints[mHead] = .(position, width, color, time, direction);
		mHead = (mHead + 1) % MaxPoints;
		mCount = Math.Min(mCount + 1, MaxPoints);
		mLastPosition = position;
	}

	/// Gets a point by index (0 = oldest, PointCount-1 = newest).
	public TrailPoint GetPoint(int32 index)
	{
		if (index < 0 || index >= mCount)
			return .();

		// Calculate actual index in circular buffer
		int32 actualIndex = (mHead - mCount + index + MaxPoints) % MaxPoints;
		return mPoints[actualIndex];
	}

	/// Gets the newest point (head).
	public TrailPoint GetNewestPoint()
	{
		if (mCount == 0)
			return .();
		return mPoints[(mHead - 1 + MaxPoints) % MaxPoints];
	}

	/// Gets the oldest point (tail).
	public TrailPoint GetOldestPoint()
	{
		if (mCount == 0)
			return .();
		return GetPoint(0);
	}

	/// Removes old points based on max age.
	public void RemoveOldPoints(float currentTime, float maxAge)
	{
		while (mCount > 0)
		{
			let oldest = GetPoint(0);
			if (currentTime - oldest.Time > maxAge)
			{
				mCount--;
			}
			else
			{
				break;
			}
		}
	}

	/// Clears all points.
	public void Clear()
	{
		mCount = 0;
		mHead = 0;
		mInitialized = false;
	}

	/// Generates triangle strip vertices for rendering.
	/// Returns the number of vertices written.
	public int32 GenerateVertices(Span<TrailVertex> outVertices, Vector3 cameraPosition, float widthStart, float widthEnd, float currentTime, float maxAge)
	{
		if (mCount < 2)
			return 0;

		int32 vertexCount = 0;
		int32 maxVerts = (int32)outVertices.Length;

		for (int32 i = 0; i < mCount && vertexCount + 2 <= maxVerts; i++)
		{
			let point = GetPoint(i);

			// Calculate T value (0 at tail, 1 at head)
			float t = mCount > 1 ? (float)i / (float)(mCount - 1) : 0;

			// Interpolate width
			float width = Math.Lerp(widthEnd, widthStart, t) * point.Width;

			// Calculate perpendicular direction (billboard toward camera)
			Vector3 toCamera = cameraPosition - point.Position;
			Vector3 forward = point.Direction;
			if (forward.LengthSquared() < 0.001f && i + 1 < mCount)
			{
				// Use direction to next point
				let nextPoint = GetPoint(i + 1);
				let toNext = nextPoint.Position - point.Position;
				if (toNext.LengthSquared() > 0.001f)
					forward = Vector3.Normalize(toNext);
			}

			// Calculate perpendicular direction - check cross product length BEFORE normalizing
			// to avoid NaN from normalizing near-zero vectors
			Vector3 crossResult = Vector3.Cross(forward, toCamera);
			float crossLengthSq = crossResult.LengthSquared();
			Vector3 right;
			if (crossLengthSq > 0.0001f)
				right = crossResult / Math.Sqrt(crossLengthSq);  // Manual normalize
			else
				right = .(1, 0, 0); // Fallback when forward is parallel to view direction

			// Calculate age-based alpha fade
			float age = currentTime - point.Time;
			float ageFactor = maxAge > 0 ? 1.0f - Math.Clamp(age / maxAge, 0, 1) : 1.0f;

			// Create color with modified alpha
			uint8 newAlpha = (uint8)(point.Color.A * ageFactor);
			Color color = .(point.Color.R, point.Color.G, point.Color.B, newAlpha);

			// U coordinate along the trail
			float u = t;

			// Generate two vertices (left and right of center)
			outVertices[vertexCount++] = .(point.Position - right * width * 0.5f, .(u, 0), color);
			outVertices[vertexCount++] = .(point.Position + right * width * 0.5f, .(u, 1), color);
		}

		return vertexCount;
	}
}

/// Trail settings for particle emitters.
struct TrailSettings
{
	/// Whether trails are enabled.
	public bool Enabled = false;

	/// Maximum number of points per trail.
	public int32 MaxPoints = 20;

	/// Minimum distance between trail points.
	public float MinVertexDistance = 0.1f;

	/// Width at the particle (head of trail).
	public float WidthStart = 1.0f;

	/// Width at the tail of the trail.
	public float WidthEnd = 0.0f;

	/// Maximum age of trail points in seconds.
	public float MaxAge = 1.0f;

	/// Whether to inherit particle color.
	public bool InheritParticleColor = true;

	/// Fixed trail color (used if InheritParticleColor is false).
	public Color TrailColor = .White;

	/// Creates default trail settings.
	public static Self Default => .() { Enabled = true };

	/// Creates laser beam trail settings.
	public static Self Laser => .()
	{
		Enabled = true,
		MaxPoints = 30,
		MinVertexDistance = 0.05f,
		WidthStart = 0.1f,
		WidthEnd = 0.05f,
		MaxAge = 0.5f
	};

	/// Creates magic trail settings.
	public static Self Magic => .()
	{
		Enabled = true,
		MaxPoints = 40,
		MinVertexDistance = 0.08f,
		WidthStart = 0.2f,
		WidthEnd = 0.0f,
		MaxAge = 0.8f
	};

	/// Creates motion blur trail settings.
	public static Self MotionBlur => .()
	{
		Enabled = true,
		MaxPoints = 10,
		MinVertexDistance = 0.02f,
		WidthStart = 1.0f,
		WidthEnd = 0.5f,
		MaxAge = 0.1f
	};
}
