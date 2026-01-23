namespace Sedulous.UI.Shell;

using System;

/// Adapter that bridges Sedulous.Shell.IClipboard to Sedulous.UI.IClipboard.
/// Shared between Sedulous.Framework.UI and Sedulous.Engine.UI.
public class ShellClipboardAdapter : Sedulous.UI.IClipboard
{
	private Sedulous.Shell.IClipboard mShellClipboard;

	public this(Sedulous.Shell.IClipboard shellClipboard)
	{
		mShellClipboard = shellClipboard;
	}

	public ~this()
	{
	}

	public Result<void> GetText(String outText)
	{
		return mShellClipboard.GetText(outText);
	}

	public Result<void> SetText(StringView text)
	{
		return mShellClipboard.SetText(text);
	}

	public bool HasText => mShellClipboard.HasText;
}
