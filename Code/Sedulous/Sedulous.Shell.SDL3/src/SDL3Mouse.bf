using System;
using SDL3;
using Sedulous.Shell.Input;
using Sedulous.Foundation.Core;

namespace Sedulous.Shell.SDL3;

/// SDL3 implementation of mouse input.
class SDL3Mouse : IMouse
{
	private float mX;
	private float mY;
	private float mDeltaX;
	private float mDeltaY;
	private float mScrollX;
	private float mScrollY;
	private bool[5] mCurrentButtons;
	private bool[5] mPreviousButtons;
	private SDL_Window* mFocusWindow;

	private EventAccessor<MouseMoveDelegate> mOnMove = new .() ~ delete _;
	private EventAccessor<MouseButtonDelegate> mOnButton = new .() ~ delete _;
	private EventAccessor<MouseScrollDelegate> mOnScroll = new .() ~ delete _;

	public float X => mX;
	public float Y => mY;
	public float DeltaX => mDeltaX;
	public float DeltaY => mDeltaY;
	public float ScrollX => mScrollX;
	public float ScrollY => mScrollY;

	public EventAccessor<MouseMoveDelegate> OnMove => mOnMove;
	public EventAccessor<MouseButtonDelegate> OnButton => mOnButton;
	public EventAccessor<MouseScrollDelegate> OnScroll => mOnScroll;

	public bool RelativeMode
	{
		get => mFocusWindow != null && SDL_GetWindowRelativeMouseMode(mFocusWindow);
		set
		{
			if (mFocusWindow != null)
				SDL_SetWindowRelativeMouseMode(mFocusWindow, value);
		}
	}

	public bool Visible
	{
		get => SDL_CursorVisible();
		set
		{
			if (value)
				SDL_ShowCursor();
			else
				SDL_HideCursor();
		}
	}

	public bool IsButtonDown(MouseButton button)
	{
		let index = (int)button;
		if (index < 0 || index >= 5)
			return false;
		return mCurrentButtons[index];
	}

	public bool IsButtonPressed(MouseButton button)
	{
		let index = (int)button;
		if (index < 0 || index >= 5)
			return false;
		return mCurrentButtons[index] && !mPreviousButtons[index];
	}

	public bool IsButtonReleased(MouseButton button)
	{
		let index = (int)button;
		if (index < 0 || index >= 5)
			return false;
		return !mCurrentButtons[index] && mPreviousButtons[index];
	}

	/// Called before processing new events.
	public void BeginFrame()
	{
		mPreviousButtons = mCurrentButtons;
		mDeltaX = 0;
		mDeltaY = 0;
		mScrollX = 0;
		mScrollY = 0;
	}

	/// Sets the current focus window for relative mode.
	public void SetFocusWindow(SDL_Window* window)
	{
		mFocusWindow = window;
	}

	/// Handles an SDL mouse motion event.
	public void HandleMotionEvent(SDL_MouseMotionEvent* e)
	{
		mX = e.x;
		mY = e.y;
		mDeltaX += e.xrel;
		mDeltaY += e.yrel;
		mOnMove.[Friend]Invoke(mX, mY);
	}

	/// Handles an SDL mouse button event.
	public void HandleButtonEvent(SDL_MouseButtonEvent* e)
	{
		let button = ConvertButton(e.button);
		let index = (int)button;
		if (index >= 0 && index < 5)
		{
			mCurrentButtons[index] = e.down;
			mOnButton.[Friend]Invoke(button, e.down);
		}
	}

	/// Handles an SDL mouse wheel event.
	public void HandleWheelEvent(SDL_MouseWheelEvent* e)
	{
		mScrollX += e.x;
		mScrollY += e.y;
		mOnScroll.[Friend]Invoke(e.x, e.y);
	}

	private static MouseButton ConvertButton(uint8 sdlButton)
	{
		switch (sdlButton)
		{
		case 1: return .Left;
		case 2: return .Middle;
		case 3: return .Right;
		case 4: return .X1;
		case 5: return .X2;
		default: return .Left;
		}
	}
}
