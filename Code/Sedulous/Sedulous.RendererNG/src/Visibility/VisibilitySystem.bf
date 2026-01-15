namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Visibility flags for objects.
[AllowDuplicates]
enum VisibilityFlags : uint32
{
	None = 0,

	/// Visible in view 0.
	View0 = 1 << 0,
	/// Visible in view 1.
	View1 = 1 << 1,
	/// Visible in view 2.
	View2 = 1 << 2,
	/// Visible in view 3.
	View3 = 1 << 3,

	/// Visible in any shadow view.
	Shadow = 1 << 16,
	/// Casts shadows.
	CastsShadow = 1 << 17,
	/// Receives shadows.
	ReceivesShadow = 1 << 18,

	/// Visible in all main views.
	AllViews = View0 | View1 | View2 | View3
}

/// Result of visibility determination for an object.
struct VisibilityResult
{
	/// Combined visibility flags across all views.
	public VisibilityFlags Flags;

	/// Mask of which views this object is visible in (bit per view).
	public uint32 ViewMask;

	/// Distance to the nearest camera (for LOD selection).
	public float NearestDistance;

	/// Whether the object is visible in any view.
	public bool IsVisible => ViewMask != 0;
}

/// Manages visibility determination across multiple views.
class VisibilitySystem
{
	// Per-view cullers
	private FrustumCuller[4] mViewCullers;
	private int32 mViewCount = 0;
	private RenderView[4] mViews;

	// Shadow cullers
	private List<FrustumCuller> mShadowCullers = new .() ~ delete _;

	// Batching
	private DrawBatcher mBatcher = new .() ~ delete _;

	// Visibility results (indexed by proxy index)
	private List<VisibilityResult> mResults = new .() ~ delete _;

	// Statistics
	private int32 mObjectsTested = 0;
	private int32 mObjectsCulled = 0;
	private int32 mObjectsVisible = 0;

	// Properties
	public DrawBatcher Batcher => mBatcher;
	public int32 ObjectsTested => mObjectsTested;
	public int32 ObjectsCulled => mObjectsCulled;
	public int32 ObjectsVisible => mObjectsVisible;
	public float CullRatio => mObjectsTested > 0 ? (float)mObjectsCulled / mObjectsTested : 0;

	/// Prepares for a new frame.
	public void BeginFrame()
	{
		mViewCount = 0;
		mShadowCullers.Clear();
		mBatcher.Clear();
		mResults.Clear();
		mObjectsTested = 0;
		mObjectsCulled = 0;
		mObjectsVisible = 0;
	}

	/// Adds a camera view for visibility testing.
	/// Returns the view index (0-3).
	public int32 AddView(RenderView view)
	{
		if (mViewCount >= 4)
			return -1;

		int32 index = mViewCount;
		mViews[index] = view;
		mViewCullers[index] = FrustumCuller(view);
		mViewCount++;
		return index;
	}

	/// Adds a shadow view for shadow caster testing.
	public void AddShadowView(RenderView view)
	{
		mShadowCullers.Add(FrustumCuller(view));
	}

	/// Tests an AABB against all views.
	/// Returns combined visibility across all views.
	public VisibilityResult TestAABB(BoundingBox bounds)
	{
		mObjectsTested++;

		VisibilityResult result = .();
		result.NearestDistance = float.MaxValue;

		// Test against each camera view
		for (int32 i = 0; i < mViewCount; i++)
		{
			if (mViewCullers[i].IsVisibleAABB(bounds))
			{
				result.ViewMask |= (1u << i);

				// Calculate distance to view position
				let view = mViews[i];
				let center = (bounds.Min + bounds.Max) * 0.5f;
				let distance = Vector3.Distance(view.Position, center);
				result.NearestDistance = Math.Min(result.NearestDistance, distance);
			}
		}

		// Test against shadow views
		for (let culler in mShadowCullers)
		{
			if (culler.IsVisibleAABB(bounds))
			{
				result.Flags |= .Shadow;
				break;
			}
		}

		if (result.ViewMask != 0)
		{
			result.Flags |= (VisibilityFlags)result.ViewMask;
			mObjectsVisible++;
		}
		else
		{
			mObjectsCulled++;
		}

		return result;
	}

	/// Tests a bounding sphere against all views.
	public VisibilityResult TestSphere(BoundingSphere sphere)
	{
		mObjectsTested++;

		VisibilityResult result = .();
		result.NearestDistance = float.MaxValue;

		// Test against each camera view
		for (int32 i = 0; i < mViewCount; i++)
		{
			if (mViewCullers[i].IsVisibleSphere(sphere))
			{
				result.ViewMask |= (1u << i);

				// Calculate distance to view position
				let view = mViews[i];
				let distance = Vector3.Distance(view.Position, sphere.Center);
				result.NearestDistance = Math.Min(result.NearestDistance, distance);
			}
		}

		// Test against shadow views
		for (let culler in mShadowCullers)
		{
			if (culler.IsVisibleSphere(sphere))
			{
				result.Flags |= .Shadow;
				break;
			}
		}

		if (result.ViewMask != 0)
		{
			result.Flags |= (VisibilityFlags)result.ViewMask;
			mObjectsVisible++;
		}
		else
		{
			mObjectsCulled++;
		}

		return result;
	}

	/// Tests a sphere against all views (convenience overload).
	public VisibilityResult TestSphere(Vector3 center, float radius)
	{
		return TestSphere(BoundingSphere(center, radius));
	}

	/// Computes normalized depth for sorting (0 = near, 1 = far).
	public float ComputeDepth(int32 viewIndex, Vector3 position)
	{
		if (viewIndex < 0 || viewIndex >= mViewCount)
			return 0.5f;

		let view = mViews[viewIndex];

		// Transform to view space and get Z
		let viewPos = Vector3.Transform(position, view.ViewMatrix);
		let z = -viewPos.Z; // Negate because view space looks down -Z

		// Normalize to [0,1] range
		return Math.Clamp((z - view.NearPlane) / (view.FarPlane - view.NearPlane), 0.0f, 1.0f);
	}

	/// Builds draw batches from accumulated commands.
	public void BuildBatches()
	{
		mBatcher.BuildBatches();
	}

	/// Gets statistics string.
	public void GetStats(String outStr)
	{
		outStr.AppendF("Visibility System Stats:\n");
		outStr.AppendF("  Views: {0}\n", mViewCount);
		outStr.AppendF("  Shadow Views: {0}\n", mShadowCullers.Count);
		outStr.AppendF("  Objects Tested: {0}\n", mObjectsTested);
		outStr.AppendF("  Objects Visible: {0}\n", mObjectsVisible);
		outStr.AppendF("  Objects Culled: {0}\n", mObjectsCulled);
		outStr.AppendF("  Cull Ratio: {0:F1}%\n", CullRatio * 100);
		outStr.Append("\n");
		mBatcher.GetStats(outStr);
	}
}

/// Helper for batch culling multiple objects.
class BatchCuller
{
	private FrustumCuller mCuller;
	private List<int32> mVisibleIndices = new .() ~ delete _;

	public this(RenderView view)
	{
		mCuller = FrustumCuller(view);
	}

	public this(Matrix viewProjection)
	{
		mCuller = FrustumCuller(viewProjection);
	}

	/// Clears visible indices for reuse.
	public void Clear()
	{
		mVisibleIndices.Clear();
	}

	/// Tests AABBs in batch, storing indices of visible ones.
	public void CullAABBs(Span<BoundingBox> boxes)
	{
		for (int i = 0; i < boxes.Length; i++)
		{
			if (mCuller.IsVisibleAABB(boxes[i]))
				mVisibleIndices.Add((int32)i);
		}
	}

	/// Tests spheres in batch, storing indices of visible ones.
	public void CullSpheres(Span<BoundingSphere> spheres)
	{
		for (int i = 0; i < spheres.Length; i++)
		{
			if (mCuller.IsVisibleSphere(spheres[i]))
				mVisibleIndices.Add((int32)i);
		}
	}

	/// Gets the indices of visible objects.
	public Span<int32> VisibleIndices => mVisibleIndices;

	/// Gets the count of visible objects.
	public int32 VisibleCount => (int32)mVisibleIndices.Count;
}
