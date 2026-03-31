namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// Root-level context that manages the UI tree, services, and frame processing.
/// Supports multiple root views for multi-window scenarios.
/// Each window gets a RootView with its own size, DPI, PopupLayer, and cursor.
public class UIContext
{
	//==========================================================================
	// Services
	//==========================================================================

	private IFontService mFontService;
	private IClipboard mClipboard;

	public IFontService FontService => mFontService;
	public IClipboard Clipboard => mClipboard;

	//==========================================================================
	// Theme
	//==========================================================================

	private Theme mTheme ~ delete _;

	/// The active theme. Controls query this every frame for colors/dimensions.
	public Theme Theme
	{
		get => mTheme;
		set
		{
			if (mTheme != value)
			{
				delete mTheme;
				mTheme = value;

				for (let root in mRootViews)
					root.OnThemeChanged();
			}
		}
	}

	//==========================================================================
	// Active Input Root
	//==========================================================================

	private RootView mActiveInputRoot;

	/// The RootView that currently receives input.
	/// Set by the Application before dispatching input events.
	public RootView ActiveInputRoot
	{
		get => mActiveInputRoot;
		set { mActiveInputRoot = value; }
	}

	/// PopupLayer for the active window.
	public PopupLayer ActivePopupLayer => mActiveInputRoot?.PopupLayer;

	/// DPI scale for the active window. Default 1.0.
	public float DpiScale => mActiveInputRoot?.DpiScale ?? 1.0f;

	/// Physical pixel width of the active window.
	public float Width => mActiveInputRoot?.WindowWidth ?? 0;

	/// Physical pixel height of the active window.
	public float Height => mActiveInputRoot?.WindowHeight ?? 0;

	/// Logical viewport width for the active window.
	public float LogicalWidth => mActiveInputRoot?.LogicalWidth ?? 0;

	/// Logical viewport height for the active window.
	public float LogicalHeight => mActiveInputRoot?.LogicalHeight ?? 0;

	//==========================================================================
	// Root Views
	//==========================================================================

	private List<View> mRootViews = new .() ~ delete _;

	/// Number of root views.
	public int RootViewCount => mRootViews.Count;

	/// Get root view at index.
	public View GetRootView(int index) => mRootViews[index];

	/// Add a root view. The UIContext does NOT take ownership.
	/// The caller is responsible for deleting the root view.
	public void AddRootView(View root)
	{
		if (root == null || mRootViews.Contains(root))
			return;

		mRootViews.Add(root);
		root.OnAttachedToContext(this);
	}

	/// Remove a root view. Does not delete it.
	public void RemoveRootView(View root)
	{
		if (root == null)
			return;

		root.OnDetachedFromContext(this);
		mRootViews.Remove(root);
	}

	//==========================================================================
	// Element Registry
	//==========================================================================

	private Dictionary<int, View> mRegistry = new .() ~ delete _;

	/// Register an element for ID-based lookup (used by ElementHandle).
	public void RegisterElement(View view)
	{
		if (view == null || !view.Id.IsValid)
			return;

		mRegistry[view.Id.Id] = view;
	}

	/// Unregister an element.
	public void UnregisterElement(View view)
	{
		if (view == null || !view.Id.IsValid)
			return;

		mRegistry.Remove(view.Id.Id);
	}

	/// Look up an element by ViewId.
	public View GetElementById(ViewId id)
	{
		if (!id.IsValid)
			return null;

		if (mRegistry.TryGetValue(id.Id, let view))
			return view;

		return null;
	}

	//==========================================================================
	// Mutation Queue
	//==========================================================================

	private MutationQueue mMutationQueue = new .() ~ delete _;

	/// Access the mutation queue for deferred tree operations.
	public MutationQueue MutationQueue => mMutationQueue;

	//==========================================================================
	// Input & Focus
	//==========================================================================

	private InputManager mInputManager;
	private FocusManager mFocusManager;
	private DragDropManager mDragDropManager;

	/// The input manager handling mouse, keyboard, and text event routing.
	public InputManager InputManager => mInputManager;

	/// The focus manager handling focus state and tab navigation.
	public FocusManager FocusManager => mFocusManager;

	/// The drag-and-drop manager for this context.
	public DragDropManager DragDrop => mDragDropManager;

	//==========================================================================
	// Debug
	//==========================================================================

	/// When true, draws layout bounds, margins, padding, and focus indicators.
	public bool DebugDraw = false;

	//==========================================================================
	// Dirty Tracking
	//==========================================================================

	/// When true, only redraws views that have been invalidated.
	/// Default false (always redraw every frame).
	public bool UseDirtyTracking = false;

	//==========================================================================
	// Animation
	//==========================================================================

	private AnimationManager mAnimationManager = new .() ~ delete _;

	/// The animation manager for this context.
	public AnimationManager Animations => mAnimationManager;

	//==========================================================================
	// Overlays
	//==========================================================================

	private TooltipManager mTooltipManager;

	/// The tooltip manager.
	public TooltipManager Tooltips => mTooltipManager;

	//==========================================================================
	// Timing
	//==========================================================================

	private float mTotalTime;

	/// Total elapsed time in seconds since the UIContext was created.
	public float TotalTime => mTotalTime;

	//==========================================================================
	// Constructor
	//==========================================================================

	public this(IFontService fontService = null, IClipboard clipboard = null)
	{
		mFontService = fontService;
		mClipboard = clipboard;
		mTheme = DarkTheme.Create();
		mFocusManager = new FocusManager(this);
		mInputManager = new InputManager(this);
		mDragDropManager = new DragDropManager(this);
		mTooltipManager = new TooltipManager(this);
	}

	public ~this()
	{
		delete mTooltipManager;
		delete mDragDropManager;
		delete mInputManager;
		delete mFocusManager;
	}

	//==========================================================================
	// Frame Processing
	//==========================================================================

	/// Global per-frame processing. Call once before UpdateRootView.
	public void BeginFrame(float deltaTime)
	{
		mTotalTime += deltaTime;
		mMutationQueue.Process(this);
		mAnimationManager.Update(deltaTime);
		mTooltipManager.Update(deltaTime);
	}

	/// Update a single root view. Call per-root after BeginFrame.
	public void UpdateRootView(RootView root, float deltaTime)
	{
		if (root == null || root.Visibility == .Gone) return;
		TickView(root, deltaTime);
		root.Measure(MeasureSpec.MakeExactly(root.LogicalWidth),
			MeasureSpec.MakeExactly(root.LogicalHeight));
		root.Layout(0, 0, root.MeasuredWidth, root.MeasuredHeight);
	}

	private void TickView(View view, float deltaTime)
	{
		view.OnTick(deltaTime);
		if (let group = view as ViewGroup)
		{
			for (int i = 0; i < group.ChildCount; i++)
				TickView(group.GetChildAt(i), deltaTime);
		}
	}

	/// Draw a single root view with its DPI scale.
	public void DrawRootView(RootView root, DrawContext ctx)
	{
		if (root == null) return;

		ctx.PushState();

		if (root.DpiScale != 1.0f)
			ctx.Scale(root.DpiScale, root.DpiScale);

		root.Draw(ctx);

		if (DebugDraw)
			DebugDrawOverlay.DrawDebugOverlay(root, ctx);

		ctx.PopState();
	}

	//==========================================================================
	// Input Dispatch (delegates to InputManager)
	//==========================================================================

	/// Process mouse movement. Call from the platform bridge.
	public void ProcessMouseMove(float screenX, float screenY, KeyModifiers modifiers = .None)
	{
		mInputManager.ProcessMouseMove(screenX, screenY, modifiers);
	}

	/// Process mouse button press. Returns true if consumed by the UI.
	public bool ProcessMouseDown(float screenX, float screenY, MouseButton button, KeyModifiers modifiers = .None)
	{
		return mInputManager.ProcessMouseDown(screenX, screenY, button, modifiers);
	}

	/// Process mouse button release. Returns true if consumed by the UI.
	public bool ProcessMouseUp(float screenX, float screenY, MouseButton button, KeyModifiers modifiers = .None)
	{
		return mInputManager.ProcessMouseUp(screenX, screenY, button, modifiers);
	}

	/// Process mouse wheel scroll. Returns true if consumed by the UI.
	public bool ProcessMouseWheel(float screenX, float screenY, float deltaX, float deltaY, KeyModifiers modifiers = .None)
	{
		return mInputManager.ProcessMouseWheel(screenX, screenY, deltaX, deltaY, modifiers);
	}

	/// Process key down. Returns true if the key was consumed by the UI.
	public bool ProcessKeyDown(KeyCode key, KeyModifiers modifiers = .None, bool isRepeat = false)
	{
		return mInputManager.ProcessKeyDown(key, modifiers, isRepeat);
	}

	/// Process key up. Returns true if the key was consumed by the UI.
	public bool ProcessKeyUp(KeyCode key, KeyModifiers modifiers = .None)
	{
		return mInputManager.ProcessKeyUp(key, modifiers);
	}

	/// Process text input.
	public void ProcessTextInput(char32 character)
	{
		mInputManager.ProcessTextInput(character);
	}

	/// Notify managers that a view is about to be deleted.
	public void NotifyElementDeleted(View view)
	{
		mInputManager.OnElementDeleted(view);
		mFocusManager.OnElementDeleted(view);
		mDragDropManager.OnElementDeleted(view);
	}

	//==========================================================================
	// Popup Convenience Methods
	//==========================================================================

	/// Show a popup at the given position.
	public void ShowPopup(View popup, IPopupOwner owner, float x, float y, bool closeOnClickOutside = true, bool ownsView = true)
	{
		ActivePopupLayer.ShowPopup(popup, owner, x, y, closeOnClickOutside, ownsView);
	}

	/// Show a modal popup centered in the viewport.
	public void ShowModalPopup(View popup, IPopupOwner owner = null)
	{
		ActivePopupLayer.ShowModalPopup(popup, owner);
	}

	/// Close a specific popup.
	public void ClosePopup(View popup)
	{
		ActivePopupLayer.ClosePopup(popup);
	}

	//==========================================================================
	// Hit Testing
	//==========================================================================

	/// Hit test within the active input root.
	/// Point is in screen coordinates.
	public View HitTest(Vector2 screenPoint)
	{
		if (mActiveInputRoot == null)
			return null;

		var logicalPoint = Vector2(screenPoint.X / mActiveInputRoot.DpiScale,
			screenPoint.Y / mActiveInputRoot.DpiScale);
		return mActiveInputRoot.HitTest(logicalPoint);
	}
}
