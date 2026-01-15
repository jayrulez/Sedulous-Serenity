namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Manages trail data for a single trail source.
/// Uses a circular buffer to efficiently store and age trail points.
class TrailEmitter : IDisposable
{
	/// Maximum number of points in this trail.
	public int32 MaxPoints { get; private set; }

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

	/// Trail settings.
	private TrailSettings mSettings;
	private bool mOwnsSettings = false;

	/// Camera position for vertex generation.
	public Vector3 CameraPosition = .Zero;

	/// Number of active points in the trail.
	public int32 PointCount => mCount;

	/// Whether the trail has any points.
	public bool HasPoints => mCount > 0;

	/// Current settings.
	public TrailSettings Settings => mSettings;

	public this(int32 maxPoints = 20)
	{
		MaxPoints = maxPoints;
		mPoints = new TrailPoint[maxPoints];
		mSettings = .Default;
	}

	public this(TrailSettings settings)
	{
		MaxPoints = settings.MaxPoints;
		mPoints = new TrailPoint[MaxPoints];
		mSettings = settings;
		MinVertexDistance = settings.MinVertexDistance;
	}

	/// Sets the trail settings.
	public void SetSettings(TrailSettings settings)
	{
		mSettings = settings;
		MinVertexDistance = settings.MinVertexDistance;

		// Resize if needed
		if (settings.MaxPoints != MaxPoints)
		{
			delete mPoints;
			MaxPoints = settings.MaxPoints;
			mPoints = new TrailPoint[MaxPoints];
			Clear();
		}
	}

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

	/// Updates the trail - call each frame to age out old points.
	public void Update(float currentTime)
	{
		RemoveOldPoints(currentTime, mSettings.MaxAge);
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
	public int32 GenerateVertices(Span<TrailVertex> outVertices, float currentTime)
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
			float width = Math.Lerp(mSettings.WidthEnd, mSettings.WidthStart, t) * point.Width;

			// Calculate perpendicular direction (billboard toward camera)
			Vector3 toCamera = CameraPosition - point.Position;
			Vector3 forward = point.Direction;
			if (forward.LengthSquared() < 0.001f && i + 1 < mCount)
			{
				// Use direction to next point
				let nextPoint = GetPoint(i + 1);
				let toNext = nextPoint.Position - point.Position;
				if (toNext.LengthSquared() > 0.001f)
					forward = Vector3.Normalize(toNext);
			}

			// Calculate perpendicular direction
			Vector3 crossResult = Vector3.Cross(forward, toCamera);
			float crossLengthSq = crossResult.LengthSquared();
			Vector3 right;
			if (crossLengthSq > 0.0001f)
				right = crossResult / Math.Sqrt(crossLengthSq);
			else
				right = .(1, 0, 0); // Fallback

			// Calculate age-based alpha fade
			float age = currentTime - point.Time;
			float ageFactor = mSettings.MaxAge > 0 ? 1.0f - Math.Clamp(age / mSettings.MaxAge, 0, 1) : 1.0f;

			// Create color with modified alpha
			Color color = mSettings.InheritParticleColor ? point.Color : mSettings.TrailColor;
			uint8 newAlpha = (uint8)(color.A * ageFactor);
			color = .(color.R, color.G, color.B, newAlpha);

			// U coordinate along the trail
			float u = t;

			// Generate two vertices (left and right of center)
			outVertices[vertexCount++] = .(point.Position - right * width * 0.5f, .(u, 0), color);
			outVertices[vertexCount++] = .(point.Position + right * width * 0.5f, .(u, 1), color);
		}

		return vertexCount;
	}

	/// Writes vertices to span. Returns number of vertices written.
	public int32 WriteVertices(Span<TrailVertex> output, float currentTime)
	{
		return GenerateVertices(output, currentTime);
	}

	/// Gets the maximum number of vertices this trail could generate.
	public int32 MaxVertexCount => MaxPoints * 2;

	public void Dispose()
	{
		// Resources cleaned up by destructor
	}
}

/// Manages multiple trail emitters, typically attached to particle systems.
class TrailManager : IDisposable
{
	private List<TrailEmitter> mTrails = new .() ~ DeleteContainerAndItems!(_);
	private TrailSettings mSettings;

	public int32 TrailCount => (int32)mTrails.Count;
	public List<TrailEmitter> Trails => mTrails;

	public this(TrailSettings settings = .Default)
	{
		mSettings = settings;
	}

	/// Creates a new trail emitter.
	public TrailEmitter CreateTrail()
	{
		let trail = new TrailEmitter(mSettings);
		mTrails.Add(trail);
		return trail;
	}

	/// Removes a trail emitter.
	public void RemoveTrail(TrailEmitter trail)
	{
		mTrails.Remove(trail);
		delete trail;
	}

	/// Updates all trails.
	public void Update(float currentTime)
	{
		for (let trail in mTrails)
			trail.Update(currentTime);
	}

	/// Sets camera position for all trails.
	public void SetCameraPosition(Vector3 position)
	{
		for (let trail in mTrails)
			trail.CameraPosition = position;
	}

	/// Clears all trails.
	public void Clear()
	{
		for (let trail in mTrails)
			trail.Clear();
	}

	/// Gets total vertex count across all trails.
	public int32 GetTotalVertexCount()
	{
		int32 count = 0;
		for (let trail in mTrails)
			count += trail.PointCount * 2;
		return count;
	}

	public void Dispose()
	{
		// Resources cleaned up by destructor
	}
}
