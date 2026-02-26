namespace StormTactics.Client;

using Sedulous.GUI;
using Sedulous.Foundation.Mathematics;
using Sedulous.Drawing;
using System;

/// Simple floating toast notification that auto-dismisses.
class ToastNotification
{
	private Popup mPopup ~ delete _;
	private TextBlock mLabel;
	private float mTimer;
	private float mDuration;
	private bool mActive;

	public this()
	{
		mPopup = new Popup();
		mPopup.Background = Color(30, 30, 40, 230);
		mPopup.Padding = Thickness(20, 10, 20, 10);
		mPopup.Behavior = .None; // No auto-close on click — we manage lifetime

		mLabel = new TextBlock("");
		mLabel.Foreground = Color(255, 200, 100);
		mLabel.FontSize = 16;
		mLabel.TextAlignment = .Center;
		mLabel.HorizontalAlignment = .Center;
		mPopup.Content = mLabel;
	}

	/// Show a toast message for the given duration (seconds).
	public void Show(GUIContext context, StringView message, float duration = 2.0f)
	{
		if (mActive)
			mPopup.Close();

		mLabel.Text = message;
		mDuration = duration;
		mTimer = 0;
		mActive = true;

		// Position near top-center of viewport
		let msgWidth = message.Length * 10 + 40; // rough estimate
		let x = (context.ViewportWidth - msgWidth) / 2;
		let y = 80.0f;
		mPopup.OpenAt(context, x, y);
	}

	/// Call each frame. Closes the toast when time expires.
	public void Update(float dt)
	{
		if (!mActive) return;

		mTimer += dt;
		if (mTimer >= mDuration)
		{
			mPopup.Close();
			mActive = false;
		}
	}

	public bool IsActive => mActive;
}
