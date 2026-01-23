namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Trail emitter that renders a ribbon trail from user-submitted points.
/// Game code calls AddPoint() each frame; the emitter manages the ring buffer,
/// ages out old points, generates camera-facing ribbon vertices, and uploads to GPU.
public class TrailEmitter
{
	private IDevice mDevice;

	// Ring buffer of trail points
	private TrailPoint[] mPoints ~ delete _;
	private int32 mHead;
	private int32 mCount;
	private int32 mMaxPoints;

	// Vertex generation
	private TrailVertex[] mVertexData ~ delete _;
	private int32 mMaxVertices;
	private int32 mVertexCount;

	// Double-buffered GPU vertex buffers
	private IBuffer[RenderConfig.FrameBufferCount] mVertexBuffers ~ { for (let b in _) delete b; };

	// Timing
	private float mTotalTime;
	private Vector3 mLastPosition;
	private bool mHasLastPosition;

	/// Number of trail vertices generated this frame.
	public int32 VertexCount => mVertexCount;

	/// Creates a new standalone trail emitter.
	public this(IDevice device, int32 maxPoints)
	{
		mDevice = device;
		mMaxPoints = Math.Max(maxPoints, 2);
		mHead = 0;
		mCount = 0;
		mTotalTime = 0;
		mHasLastPosition = false;

		mPoints = new TrailPoint[mMaxPoints];

		// Each pair of adjacent points generates a quad (6 vertices)
		mMaxVertices = (mMaxPoints - 1) * 6;
		mVertexData = new TrailVertex[mMaxVertices];

		// Create GPU vertex buffers (host-visible for direct CPU writes each frame)
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDescriptor desc = .()
			{
				Label = "Standalone Trail Vertex Buffer",
				Size = (uint64)(mMaxVertices * TrailVertex.SizeInBytes),
				Usage = .Vertex,
				MemoryAccess = .Upload
			};

			switch (device.CreateBuffer(&desc))
			{
			case .Ok(let buf): mVertexBuffers[i] = buf;
			case .Err:
			}
		}
	}

	/// Gets the vertex buffer for the given frame index.
	public IBuffer GetVertexBuffer(uint32 frameIndex)
	{
		return mVertexBuffers[frameIndex % RenderConfig.FrameBufferCount];
	}

	/// Adds a new trail point at the given world position.
	public void AddPoint(Vector3 position, float width, Color color)
	{
		// Check minimum distance
		if (mHasLastPosition)
		{
			let dist = (position - mLastPosition).Length();
			if (dist < 0.001f)
				return;
		}

		mPoints[mHead] = .()
		{
			Position = position,
			Width = width,
			Color = color,
			RecordTime = mTotalTime
		};

		mHead = (mHead + 1) % mMaxPoints;
		if (mCount < mMaxPoints)
			mCount++;

		mLastPosition = position;
		mHasLastPosition = true;
	}

	/// Adds a point with distance filtering using the proxy's MinVertexDistance.
	public void AddPointFiltered(Vector3 position, float width, Color color, float minDistance)
	{
		if (mHasLastPosition)
		{
			let dist = (position - mLastPosition).Length();
			if (dist < minDistance)
				return;
		}

		AddPoint(position, width, color);
	}

	/// Updates the trail timing and discards expired points.
	public void Update(float deltaTime)
	{
		mTotalTime += deltaTime;
	}

	/// Generates ribbon vertices and uploads to the GPU buffer.
	public void Upload(uint32 frameIndex, Vector3 cameraPos, TrailEmitterProxy* config)
	{
		mVertexCount = 0;

		if (mCount < 2)
			return;

		let buffer = mVertexBuffers[frameIndex % RenderConfig.FrameBufferCount];
		if (buffer == null)
			return;

		int32 vertexIdx = 0;

		// Walk from newest to oldest point
		for (int32 seg = 0; seg < mCount - 1; seg++)
		{
			if (vertexIdx + 6 > mMaxVertices)
				break;

			// Ring buffer indices (newest first)
			let currRingIdx = ((mHead - 1 - seg) % mMaxPoints + mMaxPoints) % mMaxPoints;
			let nextRingIdx = ((mHead - 2 - seg) % mMaxPoints + mMaxPoints) % mMaxPoints;

			let currPoint = mPoints[currRingIdx];
			let nextPoint = mPoints[nextRingIdx];

			// Age-based fade
			let currAge = mTotalTime - currPoint.RecordTime;
			let nextAge = mTotalTime - nextPoint.RecordTime;

			if (currAge > config.Lifetime || nextAge > config.Lifetime)
				break;

			let currFade = 1.0f - (currAge / config.Lifetime);
			let nextFade = 1.0f - (nextAge / config.Lifetime);

			// Direction along the ribbon
			var dir = currPoint.Position - nextPoint.Position;
			let dirLen = dir.Length();
			if (dirLen < 0.0001f)
				continue;
			dir = dir / dirLen;

			// Width direction: perpendicular to ribbon and camera-to-point
			let toCamera = Vector3.Normalize(cameraPos - currPoint.Position);
			var widthDir = Vector3.Cross(dir, toCamera);
			let widthLen = widthDir.Length();
			if (widthLen < 0.0001f)
				continue;
			widthDir = widthDir / widthLen;

			// Interpolate width from WidthStart (newest) to WidthEnd (oldest)
			let currT = (float)seg / (float)(mCount - 1);
			let nextT = (float)(seg + 1) / (float)(mCount - 1);
			let currBaseWidth = Math.Lerp(config.WidthStart, config.WidthEnd, currT);
			let nextBaseWidth = Math.Lerp(config.WidthStart, config.WidthEnd, nextT);

			let currWidth = currBaseWidth * currFade * 0.5f;
			let nextWidth = nextBaseWidth * nextFade * 0.5f;

			// V coordinates along trail length
			let vCurr = currT;
			let vNext = nextT;

			// Colors with fade and proxy color multiplier
			let currColor = Color(
				(float)currPoint.Color.R / 255.0f * config.Color.X,
				(float)currPoint.Color.G / 255.0f * config.Color.Y,
				(float)currPoint.Color.B / 255.0f * config.Color.Z,
				(float)currPoint.Color.A / 255.0f * config.Color.W * currFade
			);
			let nextColor = Color(
				(float)nextPoint.Color.R / 255.0f * config.Color.X,
				(float)nextPoint.Color.G / 255.0f * config.Color.Y,
				(float)nextPoint.Color.B / 255.0f * config.Color.Z,
				(float)nextPoint.Color.A / 255.0f * config.Color.W * nextFade
			);

			// Four corners of the quad
			let p0 = currPoint.Position - widthDir * currWidth;
			let p1 = currPoint.Position + widthDir * currWidth;
			let p2 = nextPoint.Position - widthDir * nextWidth;
			let p3 = nextPoint.Position + widthDir * nextWidth;

			// Triangle 1: p0, p1, p2
			mVertexData[vertexIdx] = .() { Position = p0, TexCoord = .(0, vCurr), Color = currColor };
			mVertexData[vertexIdx + 1] = .() { Position = p1, TexCoord = .(1, vCurr), Color = currColor };
			mVertexData[vertexIdx + 2] = .() { Position = p2, TexCoord = .(0, vNext), Color = nextColor };

			// Triangle 2: p2, p1, p3
			mVertexData[vertexIdx + 3] = .() { Position = p2, TexCoord = .(0, vNext), Color = nextColor };
			mVertexData[vertexIdx + 4] = .() { Position = p1, TexCoord = .(1, vCurr), Color = currColor };
			mVertexData[vertexIdx + 5] = .() { Position = p3, TexCoord = .(1, vNext), Color = nextColor };

			vertexIdx += 6;
		}

		mVertexCount = vertexIdx;

		if (mVertexCount > 0)
		{
			mDevice.Queue.WriteBuffer(
				buffer, 0,
				Span<uint8>((uint8*)&mVertexData[0], mVertexCount * TrailVertex.SizeInBytes)
			);
		}
	}

	/// Clears all trail points.
	public void Clear()
	{
		mHead = 0;
		mCount = 0;
		mHasLastPosition = false;
	}
}
