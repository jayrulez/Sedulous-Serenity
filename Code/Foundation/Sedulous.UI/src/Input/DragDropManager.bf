namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;

/// Drag state machine states.
public enum DragState
{
	/// No drag in progress.
	Idle,
	/// Mouse was pressed on a drag source, waiting for threshold.
	Potential,
	/// Drag is active: adorner shown, drop targets being queried.
	Active
}

/// Manages drag-and-drop operations within a UIContext.
/// Called by InputManager at the right points in the mouse event pipeline.
public class DragDropManager
{
	private UIContext mContext;

	// State
	private DragState mState = .Idle;

	// Drag session data
	private View mSourceView;
	private IDragSource mDragSource;
	private DragData mDragData ~ delete _;
	private DragAdorner mAdorner; // Owned by PopupLayer during drag
	private PopupLayer mAdornerPopupLayer; // PopupLayer that owns the adorner (stable across root changes)
	private MouseButton mDragButton;

	// Potential drag tracking
	private float mStartScreenX;
	private float mStartScreenY;

	// Drop target tracking
	private View mCurrentDropTargetView;
	private IDropTarget mCurrentDropTarget;
	private DragDropEffects mCurrentEffect = .None;

	/// Drag threshold in screen pixels.
	public float DragThreshold = 4.0f;

	/// Offset of the drag visual from the cursor (logical pixels).
	/// Set before or during OnDragStarted to customize placement.
	public float AdornerOffsetX = 4.0f;
	public float AdornerOffsetY = 4.0f;

	/// Cursor shown when over an accepting drop target. Default: Move.
	public CursorType AcceptCursor = .Move;

	/// Cursor shown when over a rejecting drop target. Default: NotAllowed.
	public CursorType RejectCursor = .NotAllowed;

	/// Last known screen position during or at the end of a drag.
	/// These are relative to the active input root's window.
	public float LastScreenX { get; private set; }
	public float LastScreenY { get; private set; }

	/// Last known global (desktop) mouse position during a drag.
	/// Set by the application layer; used for positioning floating windows.
	public float LastGlobalX { get; set; }
	public float LastGlobalY { get; set; }

	/// Current drag state.
	public DragState State => mState;

	/// Whether a drag is active (adorner visible, drop targets being queried).
	public bool IsDragging => mState == .Active;

	/// Whether a potential drag is being tracked (mouse down, threshold not yet met).
	public bool IsPotentialDrag => mState == .Potential;

	/// The current drag data, or null if no drag is active.
	public DragData CurrentDragData => mDragData;

	/// The current drop effect (whether the drop target would accept the drag).
	public DragDropEffects CurrentEffect => mCurrentEffect;

	public this(UIContext context)
	{
		mContext = context;
	}

	public ~this()
	{
		if (mState != .Idle)
			CancelDrag();
	}

	//==========================================================================
	// Public API (called by InputManager)
	//==========================================================================

	/// Called by InputManager.ProcessMouseDown when a view or ancestor
	/// implements IDragSource. Returns true if potential drag started.
	public bool BeginPotentialDrag(View sourceView, IDragSource source,
		float screenX, float screenY, MouseButton button)
	{
		if (mState != .Idle)
			return false;

		if (button != .Left)
			return false;

		mSourceView = sourceView;
		mDragSource = source;
		mDragButton = button;
		mStartScreenX = screenX;
		mStartScreenY = screenY;
		mState = .Potential;

		System.Console.WriteLine($"[DragDrop.BeginPotential] source={sourceView.GetType()} at ({screenX}, {screenY})");
		return true;
	}

	/// Called by InputManager.ProcessMouseMove.
	/// Returns true if the drag system consumed the event.
	public bool UpdateDrag(float screenX, float screenY, KeyModifiers modifiers)
	{
		if (mState == .Idle)
			return false;

		LastScreenX = screenX;
		LastScreenY = screenY;

		if (mState == .Potential)
		{
			// Check threshold
			float dx = screenX - mStartScreenX;
			float dy = screenY - mStartScreenY;
			float dist = Math.Sqrt(dx * dx + dy * dy);

			if (dist < DragThreshold)
				return false; // Not yet — let normal mouse processing continue

			// Threshold exceeded — activate drag
			if (!ActivateDrag())
			{
				// Source cancelled (returned null DragData)
				mState = .Idle;
				mSourceView = null;
				mDragSource = null;
				return false;
			}
		}

		// Active drag — update adorner and drop target
		UpdateAdornerPosition(screenX, screenY);
		UpdateDropTarget(screenX, screenY);

		return true; // Consumed
	}

	/// Called by InputManager.ProcessMouseUp.
	/// Returns true if the drag system consumed the event.
	public bool EndDrag(float screenX, float screenY)
	{
		if (mState == .Idle)
			return false;

		LastScreenX = screenX;
		LastScreenY = screenY;

		if (mState == .Potential)
		{
			// Never reached threshold — cancel silently
			mState = .Idle;
			mSourceView = null;
			mDragSource = null;
			return false; // Let normal mouseup processing continue
		}

		// Active drag — attempt drop
		DragDropEffects effect = .None;

		// Final hit-test for drop target
		UpdateDropTarget(screenX, screenY);

		System.Console.WriteLine($"[DragDrop.EndDrag] dropTarget={mCurrentDropTargetView?.GetType()} effect={mCurrentEffect}");

		// Close the adorner BEFORE OnDrop. OnDrop may destroy the floating
		// window (and its RootView/PopupLayer) as part of re-docking, which
		// would free mAdornerPopupLayer out from under us.
		if (mAdorner != null)
		{
			if (mAdornerPopupLayer != null)
				mAdornerPopupLayer.ClosePopup(mAdorner);
			mAdorner = null;
			mAdornerPopupLayer = null;
		}

		if (mCurrentDropTarget != null && mCurrentEffect != .None)
		{
			let local = mCurrentDropTargetView.ToLocal(.(screenX, screenY));
			effect = mCurrentDropTarget.OnDrop(mDragData, local.X, local.Y);
			System.Console.WriteLine($"[DragDrop.EndDrag] OnDrop returned {effect}");
		}

		CompleteDrag(effect, effect == .None);
		return true; // Consumed
	}

	/// Cancel the current drag operation (e.g., Escape key).
	public void CancelDrag()
	{
		if (mState == .Idle)
			return;

		if (mState == .Active)
			CompleteDrag(.None, true);
		else
		{
			mState = .Idle;
			mSourceView = null;
			mDragSource = null;
		}
	}

	/// Called when a view is about to be deleted.
	/// Cancels drag if the source or current drop target is deleted.
	public void OnElementDeleted(View view)
	{
		if (mState == .Idle)
			return;

		if (view == mSourceView)
		{
			if (mState == .Active)
				CompleteDrag(.None, true);
			else
			{
				mState = .Idle;
				mSourceView = null;
				mDragSource = null;
			}
			return;
		}

		if (view == mCurrentDropTargetView)
		{
			mCurrentDropTarget.OnDragLeave(mDragData);
			mCurrentDropTargetView = null;
			mCurrentDropTarget = null;
			mCurrentEffect = .None;
		}
	}

	//==========================================================================
	// Internal
	//==========================================================================

	/// Activate the drag: create data, adorner, set capture.
	private bool ActivateDrag()
	{
		// Reset customizable properties to defaults
		AdornerOffsetX = 4.0f;
		AdornerOffsetY = 4.0f;
		AcceptCursor = .Move;
		RejectCursor = .NotAllowed;

		// Ask source for data
		mDragData = mDragSource.CreateDragData();
		if (mDragData == null)
		{
			System.Console.WriteLine("[DragDrop.ActivateDrag] CreateDragData returned null — aborting");
			return false;
		}

		mDropTargetLogCount = 0;
		System.Console.WriteLine($"[DragDrop.ActivateDrag] Data format='{mDragData.Format}' sourceView={mSourceView.GetType()} context={mSourceView.[Friend]mContext != null}");

		// Ask source for visual — source can also customize offset/cursor here
		let visual = mDragSource.CreateDragVisual(mDragData);

		// Notify source (gives it a chance to customize AdornerOffset/Cursor)
		mDragSource.OnDragStarted(mDragData);

		System.Console.WriteLine($"[DragDrop.ActivateDrag] After OnDragStarted: sourceView context={mSourceView.[Friend]mContext != null} parent={mSourceView.Parent?.GetType()}");

		// Create adorner with final offset values
		mAdorner = new DragAdorner(visual, AdornerOffsetX, AdornerOffsetY);

		// Measure adorner
		float viewportW = mContext.LogicalWidth;
		float viewportH = mContext.LogicalHeight;
		mAdorner.Measure(MeasureSpec.MakeAtMost(viewportW), MeasureSpec.MakeAtMost(viewportH));

		// Show adorner via PopupLayer (closeOnClickOutside=false, ownsView=true)
		// Remember which PopupLayer owns it — ActiveInputRoot (and thus ActivePopupLayer)
		// may change mid-drag during cross-window operations.
		mAdornerPopupLayer = mContext.ActivePopupLayer;
		float dpiScale = mContext.DpiScale;
		float logicalX = mStartScreenX / dpiScale;
		float logicalY = mStartScreenY / dpiScale;
		mAdornerPopupLayer.ShowPopup(mAdorner, null, logicalX + AdornerOffsetX, logicalY + AdornerOffsetY, false, true);

		// Set mouse capture on source view
		mContext.FocusManager.SetCapture(mSourceView);

		mState = .Active;
		return true;
	}

	/// Update the adorner's screen position.
	private void UpdateAdornerPosition(float screenX, float screenY)
	{
		if (mAdorner == null || mAdornerPopupLayer == null)
			return;

		// During cross-window drag, ActivePopupLayer may differ from the one
		// that owns the adorner. Only update if we're still on the same layer;
		// otherwise the adorner stays frozen in its originating window.
		if (mContext.ActivePopupLayer != mAdornerPopupLayer)
			return;

		float dpiScale = mContext.DpiScale;
		float logicalX = screenX / dpiScale;
		float logicalY = screenY / dpiScale;
		mAdornerPopupLayer.UpdatePopupPosition(mAdorner,
			logicalX + mAdorner.[Friend]mOffsetX,
			logicalY + mAdorner.[Friend]mOffsetY);
	}

	private int mDropTargetLogCount = 0;

	/// Hit-test for drop targets, fire enter/leave/over.
	private void UpdateDropTarget(float screenX, float screenY)
	{
		// Hit-test (adorner is IsHitTestVisible=false, so it's ignored)
		let hitView = mContext.HitTest(.(screenX, screenY));

		// Walk up parent chain to find IDropTarget
		View newTargetView = null;
		IDropTarget newTarget = null;
		FindDropTarget(hitView, out newTargetView, out newTarget);

		if (mDropTargetLogCount < 5 || newTarget != mCurrentDropTarget)
		{
			System.Console.WriteLine($"[DragDrop.UpdateDropTarget] screen=({screenX},{screenY}) hitView={hitView?.GetType()} dropTarget={newTargetView?.GetType()} (was {mCurrentDropTargetView?.GetType()})");
			mDropTargetLogCount++;
		}

		if (newTarget != mCurrentDropTarget)
		{

			// Leave old target
			if (mCurrentDropTarget != null)
				mCurrentDropTarget.OnDragLeave(mDragData);

			mCurrentDropTargetView = newTargetView;
			mCurrentDropTarget = newTarget;

			// Enter new target
			if (mCurrentDropTarget != null)
			{
				let local = newTargetView.ToLocal(.(screenX, screenY));
				mCurrentDropTarget.OnDragEnter(mDragData, local.X, local.Y);
				mCurrentEffect = mCurrentDropTarget.CanAcceptDrop(mDragData, local.X, local.Y);
			}
			else
			{
				mCurrentEffect = .None;
			}
		}
		else if (mCurrentDropTarget != null)
		{
			// Same target — fire over
			let local = mCurrentDropTargetView.ToLocal(.(screenX, screenY));
			mCurrentDropTarget.OnDragOver(mDragData, local.X, local.Y);
			mCurrentEffect = mCurrentDropTarget.CanAcceptDrop(mDragData, local.X, local.Y);
		}

		// Update cursor based on effect
		if (mState == .Active)
		{
			CursorType cursor;
			if (mCurrentDropTarget == null)
				cursor = .Default;
			else if (mCurrentEffect != .None)
				cursor = AcceptCursor;
			else
				cursor = RejectCursor;

			if (mContext.ActiveInputRoot != null)
				mContext.ActiveInputRoot.RequestedCursor = cursor;
		}
	}

	/// Walk up the parent chain from hitView to find the first IDropTarget.
	private void FindDropTarget(View hitView, out View targetView, out IDropTarget target)
	{
		targetView = null;
		target = null;

		var current = hitView;
		while (current != null)
		{
			if (let dt = current as IDropTarget)
			{
				targetView = current;
				target = dt;
				return;
			}
			current = current.Parent;
		}
	}

	/// Clean up after drag ends (success or cancel).
	private void CompleteDrag(DragDropEffects effect, bool cancelled)
	{
		// Leave current drop target
		if (mCurrentDropTarget != null)
		{
			mCurrentDropTarget.OnDragLeave(mDragData);
			mCurrentDropTargetView = null;
			mCurrentDropTarget = null;
			mCurrentEffect = .None;
		}

		// Release capture
		mContext.FocusManager.ReleaseCapture();

		// Remove adorner from PopupLayer (PopupLayer owns it, will delete)
		if (mAdorner != null)
		{
			if (mAdornerPopupLayer != null)
				mAdornerPopupLayer.ClosePopup(mAdorner);
			mAdorner = null;
			mAdornerPopupLayer = null;
		}

		// Notify source
		if (mDragSource != null)
			mDragSource.OnDragCompleted(mDragData, effect, cancelled);

		// Reset cursor
		if (mContext.ActiveInputRoot != null)
			mContext.ActiveInputRoot.RequestedCursor = .Default;

		// Clean up
		delete mDragData;
		mDragData = null;
		mSourceView = null;
		mDragSource = null;
		mState = .Idle;
	}
}
