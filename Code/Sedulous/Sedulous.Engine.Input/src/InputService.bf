namespace Sedulous.Engine.Input;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Shell.Input;

/// Engine service that manages input contexts and action processing.
/// Bridges Shell.InputManager with high-level action system.
class InputService : ContextService
{
	/// Input should be processed very early, before game logic.
	public override int32 UpdateOrder => -100;

	private Context mContext;
	private IInputManager mInputManager;
	private List<InputContext> mContextStack = new .() ~ delete _;
	private Dictionary<String, InputContext> mContextsByName = new .();

	/// Whether UI consumed input this frame (set by UISceneComponent).
	public bool UIConsumedInput { get; set; }

	/// Creates an InputService with the specified input manager.
	public this(IInputManager inputManager)
	{
		mInputManager = inputManager;
	}

	public ~this()
	{
		// Clear contexts
		for (let ctx in mContextStack)
			delete ctx;
		mContextStack.Clear();

		DeleteDictionaryAndKeys!(mContextsByName);
		//mContextsByName.Clear();
	}

	// ==================== IContextService ====================

	public override void OnRegister(Context context)
	{
		mContext = context;
	}

	public override void OnUnregister()
	{
		mContext = null;
	}

	public override void Startup()
	{
	}

	public override void Shutdown()
	{
	}

	public override void Update(float deltaTime)
	{
		if (mInputManager == null)
			return;

		// Reset consumption flag at start of frame
		UIConsumedInput = false;

		// Update contexts in priority order (highest first)
		for (let context in mContextStack)
		{
			if (!context.Enabled)
				continue;

			context.Update(mInputManager);

			if (context.BlocksInput)
				break; // Don't process lower-priority contexts
		}
	}

	// ==================== Public API ====================

	/// Gets the low-level input manager.
	public IInputManager InputManager => mInputManager;

	/// Creates and pushes a new context.
	public InputContext CreateContext(StringView name, int32 priority = 0)
	{
		let context = new InputContext(name, priority);
		PushContext(context);
		return context;
	}

	/// Pushes an existing context onto the stack.
	public void PushContext(InputContext context)
	{
		// Insert sorted by priority (descending)
		int insertIndex = 0;
		for (int i = 0; i < mContextStack.Count; i++)
		{
			if (mContextStack[i].Priority < context.Priority)
			{
				insertIndex = i;
				break;
			}
			insertIndex = i + 1;
		}
		mContextStack.Insert(insertIndex, context);
		mContextsByName[new String(context.Name)] = context;
	}

	/// Removes a context from the stack.
	/// Note: Does NOT delete the context - caller is responsible for deletion.
	public void PopContext(InputContext context)
	{
		mContextStack.Remove(context);

		// Find and remove from name dictionary
		String keyToRemove = null;
		for (let kv in mContextsByName)
		{
			if (kv.value == context)
			{
				keyToRemove = kv.key;
				break;
			}
		}
		if (keyToRemove != null)
		{
			mContextsByName.Remove(keyToRemove);
			delete keyToRemove;
		}
	}

	/// Gets a context by name.
	public InputContext GetContext(StringView name)
	{
		if (mContextsByName.TryGetValue(scope String(name), let ctx))
			return ctx;
		return null;
	}

	/// Enables/disables a context by name.
	public void SetContextEnabled(StringView name, bool enabled)
	{
		if (let ctx = GetContext(name))
			ctx.Enabled = enabled;
	}

	/// Gets an action from the first context that contains it.
	/// Searches from highest to lowest priority.
	public InputAction GetAction(StringView name)
	{
		for (let ctx in mContextStack)
		{
			if (!ctx.Enabled)
				continue;

			if (let action = ctx.GetAction(name))
				return action;
		}
		return null;
	}

	/// Gets the number of active contexts.
	public int ContextCount => mContextStack.Count;

	/// Enumerates all contexts (highest priority first).
	public List<InputContext>.Enumerator Contexts => mContextStack.GetEnumerator();
}
