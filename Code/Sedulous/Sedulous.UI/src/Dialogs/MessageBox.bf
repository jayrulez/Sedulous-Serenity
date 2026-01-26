using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// Icon type for message boxes.
public enum MessageBoxIcon
{
	/// No icon.
	None,
	/// Information icon.
	Information,
	/// Warning icon.
	Warning,
	/// Error icon.
	Error,
	/// Question icon.
	Question
}

/// A simple message dialog with static methods for easy use.
public class MessageBox : Dialog
{
	private TextBlock mMessageText; // Reference only - owned by Dialog.mContent via DialogContent
	private MessageBoxIcon mIcon = .None;

	/// The message text displayed in the dialog.
	public StringView Message
	{
		get => mMessageText?.Text ?? "";
		set
		{
			if (mMessageText != null)
				mMessageText.Text = value;
		}
	}

	/// The icon displayed in the message box.
	public MessageBoxIcon Icon
	{
		get => mIcon;
		set
		{
			mIcon = value;
			// Adjust text margin based on whether icon is present
			if (mMessageText != null)
			{
				if (mIcon != .None)
					mMessageText.Margin = Thickness(52, 8, 8, 8); // Left offset for 32px icon + padding
				else
					mMessageText.Margin = Thickness(8);
			}
			InvalidateVisual();
		}
	}

	public this()
	{
		mMessageText = new TextBlock();
		mMessageText.TextWrapping = .Wrap;
		mMessageText.Margin = Thickness(8);
		DialogContent = mMessageText;

		MinWidth = 280;
		MinHeight = 120;
	}

	/// Shows a message box and returns the result.
	public static DialogResult Show(UIContext context, StringView message, StringView title = "Message", DialogButtons buttons = .OK)
	{
		let msgBox = new MessageBox();
		msgBox.Title = title;
		msgBox.Message = message;
		msgBox.Buttons = buttons;
		msgBox.DeleteOnClose = true; // Auto-delete when closed

		var result = DialogResult.None;

		// Set up result handler
		msgBox.ClosedWithResult.Subscribe(new [&result](dialog, dialogResult) =>
		{
			result = dialogResult;
		});

		msgBox.ShowDialog(context);

		// Note: In a real async implementation, we'd wait for the dialog to close.
		// For now, the caller should handle the result via the ClosedWithResult event.

		return result;
	}

	/// Shows an information message box.
	public static DialogResult ShowInfo(UIContext context, StringView message, StringView title = "Information")
	{
		let msgBox = new MessageBox();
		msgBox.Title = title;
		msgBox.Message = message;
		msgBox.Buttons = .OK;
		msgBox.Icon = .Information;
		msgBox.DeleteOnClose = true;
		msgBox.ShowDialog(context);
		return .None;
	}

	/// Shows a warning message box.
	public static DialogResult ShowWarning(UIContext context, StringView message, StringView title = "Warning")
	{
		let msgBox = new MessageBox();
		msgBox.Title = title;
		msgBox.Message = message;
		msgBox.Buttons = .OK;
		msgBox.Icon = .Warning;
		msgBox.DeleteOnClose = true;
		msgBox.ShowDialog(context);
		return .None;
	}

	/// Shows an error message box.
	public static DialogResult ShowError(UIContext context, StringView message, StringView title = "Error")
	{
		let msgBox = new MessageBox();
		msgBox.Title = title;
		msgBox.Message = message;
		msgBox.Buttons = .OK;
		msgBox.Icon = .Error;
		msgBox.DeleteOnClose = true;
		msgBox.ShowDialog(context);
		return .None;
	}

	/// Shows a question message box with Yes/No buttons.
	public static DialogResult ShowQuestion(UIContext context, StringView message, StringView title = "Question")
	{
		let msgBox = new MessageBox();
		msgBox.Title = title;
		msgBox.Message = message;
		msgBox.Buttons = .YesNo;
		msgBox.Icon = .Question;
		msgBox.DeleteOnClose = true;
		msgBox.ShowDialog(context);
		return .None;
	}

	/// Shows a confirmation message box with OK/Cancel buttons.
	public static DialogResult ShowConfirm(UIContext context, StringView message, StringView title = "Confirm")
	{
		let msgBox = new MessageBox();
		msgBox.Title = title;
		msgBox.Message = message;
		msgBox.Buttons = .OKCancel;
		msgBox.Icon = .Question;
		msgBox.DeleteOnClose = true;
		msgBox.ShowDialog(context);
		return .None;
	}

	protected override void OnRender(DrawContext drawContext)
	{
		base.OnRender(drawContext);

		// Draw icon if specified
		if (mIcon != .None)
		{
			let bounds = Bounds;
			let iconSize = 32f;
			let iconX = bounds.X + 12;
			let iconY = bounds.Y + mTitleBarHeight + 12;

			Color iconColor;
			switch (mIcon)
			{
			case .Information:
				iconColor = Color(0, 120, 215);
			case .Warning:
				iconColor = Color(255, 185, 0);
			case .Error:
				iconColor = Color(232, 17, 35);
			case .Question:
				iconColor = Color(0, 120, 215);
			default:
				iconColor = Color.Black;
			}

			// Draw simple icon representation
			switch (mIcon)
			{
			case .Information:
				// Draw "i" in circle
				drawContext.FillRect(.(iconX + iconSize/2 - 2, iconY + 8, 4, 4), iconColor);
				drawContext.FillRect(.(iconX + iconSize/2 - 2, iconY + 14, 4, 12), iconColor);

			case .Warning:
				// Draw "!" triangle shape indicator
				drawContext.FillRect(.(iconX + iconSize/2 - 2, iconY + 6, 4, 14), iconColor);
				drawContext.FillRect(.(iconX + iconSize/2 - 2, iconY + 24, 4, 4), iconColor);

			case .Error:
				// Draw "X"
				for (int i < 16)
				{
					drawContext.FillRect(.(iconX + 8 + i, iconY + 8 + i, 2, 2), iconColor);
					drawContext.FillRect(.(iconX + 8 + i, iconY + 22 - i, 2, 2), iconColor);
				}

			case .Question:
				// Draw "?"
				drawContext.FillRect(.(iconX + iconSize/2 - 6, iconY + 6, 12, 3), iconColor);
				drawContext.FillRect(.(iconX + iconSize/2 + 4, iconY + 9, 3, 8), iconColor);
				drawContext.FillRect(.(iconX + iconSize/2 - 2, iconY + 15, 6, 3), iconColor);
				drawContext.FillRect(.(iconX + iconSize/2 - 2, iconY + 22, 4, 4), iconColor);

			default:
			}
		}
	}
}
